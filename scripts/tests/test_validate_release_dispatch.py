"""Contract tests for the OCI coordinator receiver (no cloud or OpenTofu execution)."""

from __future__ import annotations

import copy
import json
import os
import re
import subprocess
import textwrap
import unittest
from pathlib import Path

from scripts.validate_release_dispatch import DispatchError, validate_payload


DIGEST = "sha256:" + "a" * 64
SHA = "b" * 40


def valid_payload() -> dict[str, object]:
    """Return the smallest complete accepted controller delivery."""
    return {
        "release_id": "talos-1.9.3-20260904",
        "source_repo": "syscode-labs/syscode-homelab-gitops-apps",
        "source_sha": SHA,
        "sender_repo": "syscode-labs/talos-release-controller",
        "idempotency_key": "talos-1.9.3-20260904",
        "build_run_id": 123,
        "talos_version": "v1.9.3",
        "kubernetes_version": "v1.31.2",
        "artifacts": {
            "unraid": {
                "ref": "ghcr.io/syscode-labs/talos-images/installer:v1.9.3-libvirt",
                "digest": DIGEST,
            },
            "oci": {
                "ref": "ghcr.io/syscode-labs/talos-images/installer:v1.9.3",
                "digest": DIGEST,
                "image_ocid": "ocid1.image.oc1.uk-london-1.example",
            },
        },
        "oci_scope": {
            "targets": ["oci_core_instance.ampere_instance[0]"],
            "replace": ["oci_core_instance.ampere_instance[0]"],
        },
    }


class ReleaseDispatchContractTests(unittest.TestCase):
    """Ensure unsafe coordinator requests fail before a deployment is dispatched."""

    def test_accepts_exact_artifact_identity_and_talos_scope(self) -> None:
        request = validate_payload(valid_payload())
        self.assertEqual(request["idempotency_key"], request["release_id"])
        self.assertEqual(request["artifacts"]["oci"]["digest"], DIGEST)  # type: ignore[index]

    def test_rejects_missing_scope(self) -> None:
        payload = valid_payload()
        payload.pop("oci_scope")
        with self.assertRaisesRegex(DispatchError, "oci_scope"):
            validate_payload(payload)

    def test_rejects_network_or_micro_target(self) -> None:
        payload = valid_payload()
        payload["oci_scope"] = {
            "targets": ["oci_core_instance.micro_instance[0]"],
            "replace": [],
        }
        with self.assertRaisesRegex(DispatchError, "unapproved"):
            validate_payload(payload)

    def test_rejects_unbound_or_mutable_artifact(self) -> None:
        payload = valid_payload()
        payload["artifacts"] = copy.deepcopy(payload["artifacts"])
        payload["artifacts"]["oci"]["digest"] = "latest"  # type: ignore[index]
        with self.assertRaisesRegex(DispatchError, "digest"):
            validate_payload(payload)

    def test_rejects_invalid_kubernetes_version(self) -> None:
        payload = valid_payload()
        payload["kubernetes_version"] = "latest"
        with self.assertRaisesRegex(DispatchError, "kubernetes_version"):
            validate_payload(payload)

    def test_rejects_foreign_sender_or_release_identity(self) -> None:
        payload = valid_payload()
        payload["sender_repo"] = "attacker/example"
        with self.assertRaisesRegex(DispatchError, "release controller"):
            validate_payload(payload)
        payload = valid_payload()
        payload["idempotency_key"] = "other-release"
        with self.assertRaisesRegex(DispatchError, "idempotency_key"):
            validate_payload(payload)

    def test_rejects_replace_outside_exact_target_scope(self) -> None:
        payload = valid_payload()
        payload["oci_scope"] = {
            "targets": ["oci_core_instance.ampere_instance[0]"],
            "replace": ["oci_core_instance.ampere_instance[1]"],
        }
        with self.assertRaisesRegex(DispatchError, "subset"):
            validate_payload(payload)

    def test_receiver_callback_keeps_artifacts_and_fails_duplicate_delivery(
        self,
    ) -> None:
        workflow = Path(".github/workflows/release-dispatch.yml").read_text(
            encoding="utf-8"
        )
        self.assertIn("Reserve this release ID exactly once", workflow)
        self.assertIn(
            "Release ${RELEASE_ID} was already reserved; refusing to repeat it.",
            workflow,
        )
        self.assertIn('if os.environ["EXECUTED"] != "true":', workflow)
        self.assertIn('outcome = "failure"', workflow)
        self.assertIn('"build_run_id": payload.get("build_run_id")', workflow)
        self.assertIn('"artifacts": payload.get("artifacts")', workflow)
        self.assertIn(
            '"attempt_state": "existing_claim" if os.environ["DUPLICATE"] == "true" else None',
            workflow,
        )
        self.assertIn('"duplicate=true" >> "$GITHUB_OUTPUT"', workflow)
        self.assertIn("displayTitle", workflow)
        self.assertIn('select(.displayTitle == \\"Deploy ${release_id}\\")', workflow)
        deploy = Path(".github/workflows/deploy.yml").read_text(encoding="utf-8")
        self.assertIn(
            "run-name: Deploy ${{ inputs.release_id || inputs.reason }}", deploy
        )
        self.assertIn("kubernetes_version", deploy)
        self.assertIn("needs: apply", deploy)
        self.assertIn("needs.apply.result == 'success'", deploy)
        self.assertIn("group: omni-runner", deploy)
        self.assertIn(
            'gh run watch "$run_id" --repo "$GITHUB_REPOSITORY" --exit-status',
            workflow,
        )
        self.assertIn(
            ".release-health/omnictl-linux-amd64 cluster status oci-lab --wait 90s",
            deploy,
        )
        self.assertIn(
            "omnictl-linux-amd64 kubeconfig -c oci-lab --service-account", deploy
        )
        self.assertIn("--user oci-release-health --ttl 15m", deploy)
        self.assertIn("python3 scripts/verify_oci_release_health.py", deploy)
        self.assertIn(
            "--talos-version-output .release-health/talos-version.json", deploy
        )
        self.assertIn(
            "--kubernetes-nodes .release-health/kubernetes-nodes.json", deploy
        )

    def test_plan_receives_the_required_cloudflare_zone_input(self) -> None:
        deploy = Path(".github/workflows/deploy.yml").read_text(encoding="utf-8")
        plan = deploy.split("      - name: Tofu Plan", 1)[1].split(
            "      - name: Enforce Always Free plan", 1
        )[0]
        self.assertIn(
            "TF_VAR_cloudflare_zone_id: ${{ secrets.CLOUDFLARE_SYSCODEUK_ID }}",
            plan,
        )

    def test_callback_payload_is_compact_and_keeps_controller_correlation_fields(
        self,
    ) -> None:
        workflow = Path(".github/workflows/release-dispatch.yml").read_text(
            encoding="utf-8"
        )
        report = workflow.split("      - name: Report a fully correlated result", 1)[1]
        match = re.search(
            r"python3 - <<'PY' > dispatch\.json\n(?P<code>.*?)^          PY$",
            report,
            flags=re.DOTALL | re.MULTILINE,
        )
        self.assertIsNotNone(match, "callback payload producer is missing")
        payload = valid_payload()
        completed = subprocess.run(
            ["python3", "-c", textwrap.dedent(match.group("code"))],  # type: ignore[union-attr]
            check=True,
            capture_output=True,
            text=True,
            env={
                **os.environ,
                "PAYLOAD": json.dumps(payload),
                "OUTCOME": "failure",
                "EXECUTED": "true",
                "DUPLICATE": "false",
                "GITHUB_SERVER_URL": "https://github.com",
                "GITHUB_REPOSITORY": "syscode-labs/oci-free-tier-manager",
                "GITHUB_RUN_ID": "456",
            },
        )
        callback = json.loads(completed.stdout)["client_payload"]
        self.assertEqual(len(callback), 10)
        self.assertEqual(
            set(callback),
            {
                "release_id",
                "provider",
                "outcome",
                "source_repo",
                "source_sha",
                "build_run_id",
                "artifacts",
                "attempt_state",
                "run_id",
                "details_url",
            },
        )
        self.assertEqual(callback["build_run_id"], payload["build_run_id"])
        self.assertEqual(callback["artifacts"], payload["artifacts"])
        self.assertIsNone(callback["attempt_state"])

        duplicate = subprocess.run(
            ["python3", "-c", textwrap.dedent(match.group("code"))],  # type: ignore[union-attr]
            check=True,
            capture_output=True,
            text=True,
            env={
                **os.environ,
                "PAYLOAD": json.dumps(payload),
                "OUTCOME": "failure",
                "EXECUTED": "false",
                "DUPLICATE": "true",
                "GITHUB_SERVER_URL": "https://github.com",
                "GITHUB_REPOSITORY": "syscode-labs/oci-free-tier-manager",
                "GITHUB_RUN_ID": "457",
            },
        )
        duplicate_callback = json.loads(duplicate.stdout)["client_payload"]
        self.assertEqual(len(duplicate_callback), 10)
        self.assertEqual(duplicate_callback["attempt_state"], "existing_claim")


if __name__ == "__main__":
    unittest.main()
