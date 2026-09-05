"""Executable contract tests for the OCI post-apply health workflow."""

from __future__ import annotations

import re
import subprocess
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = REPOSITORY_ROOT / ".github/workflows/deploy.yml"


def health_script() -> str:
    """Extract the actual shell executed by the release-health workflow step."""
    workflow = WORKFLOW.read_text(encoding="utf-8")
    match = re.search(
        r"      - name: Verify exact Talos and Kubernetes release health\n.*?        run: \|\n"
        r"(?P<script>(?:          .*\n)+)",
        workflow,
        flags=re.DOTALL,
    )
    if match is None:
        raise AssertionError("release-health run script is missing")
    return "".join(
        line.removeprefix("          ")
        for line in match.group("script").splitlines(keepends=True)
    )


class DeployHealthWorkflowTests(unittest.TestCase):
    def test_actual_workflow_shell_and_embedded_python_compile(self) -> None:
        script = health_script()
        with tempfile.NamedTemporaryFile("w", suffix=".sh") as shell:
            shell.write(script)
            shell.flush()
            subprocess.run(["bash", "-n", shell.name], check=True)
        python = re.search(
            r"python3 - <<'PY'\n(?P<code>.*?)^PY$",
            script,
            flags=re.DOTALL | re.MULTILINE,
        )
        self.assertIsNotNone(python, "machine UUID selection Python is missing")
        compile(python.group("code"), "deploy-health-machine-selection", "exec")  # type: ignore[union-attr]

    def test_machine_selection_accepts_omni_json_stream(self) -> None:
        import json
        import os
        import sys

        python = re.search(
            r"python3 - <<'PY'\n(?P<code>.*?)^PY$",
            health_script(),
            flags=re.DOTALL | re.MULTILINE,
        )
        assert python is not None
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory) / ".release-health"
            evidence.mkdir()
            records = [
                {
                    "metadata": {
                        "id": identity,
                        "labels": {"omni.sidero.dev/cluster": "oci-lab"},
                    }
                }
                for identity in ("node-a", "node-b")
            ]
            (evidence / "cluster-machines.json").write_text(
                "\n".join(json.dumps(record) for record in records),
                encoding="utf-8",
            )
            subprocess.run(
                [sys.executable, "-c", python.group("code")],
                check=True,
                cwd=directory,
                env={**os.environ, "PYTHONPATH": str(REPOSITORY_ROOT)},
            )
            self.assertEqual(
                (evidence / "machine-ids.txt").read_text(), "node-a\nnode-b\n"
            )

    def test_actual_workflow_downloads_and_checks_the_same_talosctl_name(self) -> None:
        script = health_script()
        self.assertIn("--output .release-health/talosctl-linux-amd64", script)
        self.assertIn(
            "grep ' talosctl-linux-amd64$' sha256sum.txt | sha256sum -c -", script
        )
        self.assertIn("chmod 700 .release-health/talosctl-linux-amd64", script)
        self.assertIn(".release-health/talosctl-linux-amd64 get version", script)
        self.assertNotIn("talosctl-linux-amd64 version", script)

    def test_actual_workflow_uses_sa_only_and_selected_omni_nodes(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        script = health_script()
        self.assertIn(
            "omnictl get clustermachine -l 'omni.sidero.dev/cluster=oci-lab' -o json",
            workflow,
        )
        self.assertIn(
            "OMNI_SERVICE_ACCOUNT_KEY: ${{ secrets.OMNI_SERVICE_ACCOUNT_KEY }}",
            workflow,
        )
        self.assertIn('test -n "$OMNI_ENDPOINT"', script)
        self.assertIn('test -n "$OMNI_SERVICE_ACCOUNT_KEY"', script)
        self.assertIn('SIDEROV1_KEY="$OMNI_SERVICE_ACCOUNT_KEY"', script)
        self.assertIn("SIDEROV1_KEYS_DIR=.release-health/empty-siderov1-keys", script)
        self.assertIn('--nodes "$(paste -sd, .release-health/machine-ids.txt)"', script)
        self.assertIn(
            "Omni must select exactly two distinct oci-lab machine UUIDs", script
        )

    def test_actual_workflow_invokes_the_checked_helper(self) -> None:
        script = health_script()
        self.assertIn("python3 scripts/verify_oci_release_health.py", script)
        for argument in (
            "--machine-ids .release-health/machine-ids.txt",
            "--talos-version-output .release-health/talos-version.json",
            "--kubernetes-nodes .release-health/kubernetes-nodes.json",
            "--kubernetes-version .release-health/kubernetes-version.json",
        ):
            self.assertIn(argument, script)


if __name__ == "__main__":
    unittest.main()
