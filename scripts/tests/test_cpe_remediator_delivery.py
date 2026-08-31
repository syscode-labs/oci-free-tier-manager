#!/usr/bin/env python3
"""Regression tests for private bastion remediator artifact delivery."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import textwrap
import unittest
from tempfile import TemporaryDirectory
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BUILD_SCRIPT_PATH = REPOSITORY_ROOT / "scripts" / "build-cpe-remediator.sh"
TASKFILE_PATH = REPOSITORY_ROOT / "Taskfile.yml"
CI_PATH = REPOSITORY_ROOT / ".github" / "workflows" / "ci.yml"
DEPLOY_CI_PATH = REPOSITORY_ROOT / ".github" / "workflows" / "deploy.yml"
REMEDIATOR_TF_PATH = REPOSITORY_ROOT / "tofu" / "oci" / "cpe-remediator.tf"
DATA_TF_PATH = REPOSITORY_ROOT / "tofu" / "oci" / "data.tf"
CPE_TF_PATH = REPOSITORY_ROOT / "tofu" / "oci" / "cpe-auto-recreate.tf"
Bastion_TF_PATH = REPOSITORY_ROOT / "tofu" / "oci" / "bastion.tf"
CLOUD_INIT_PATH = (
    REPOSITORY_ROOT / "tofu" / "oci" / "files" / "cloud-init-bastion.yaml.tmpl"
)
VALIDATE_OCI_PATH = REPOSITORY_ROOT / "scripts" / "validate-phase2.sh"
CUTOVER_RUNBOOK_PATH = REPOSITORY_ROOT / "docs" / "CPE_REMEDIATOR_CUTOVER.md"
TOFU_DIRECTORY = REPOSITORY_ROOT / "tofu" / "oci"


def task_block(text: str, task_name: str) -> str:
    """Return one top-level Taskfile task block."""
    match = re.search(
        rf"(?ms)^  {re.escape(task_name)}:\n(.*?)(?=^  [^ \n][^:]*:|\Z)",
        text,
    )
    if match is None:
        raise AssertionError(f"Task block not found: {task_name}")
    return match.group(1)


class CpeRemediatorDeliveryTests(unittest.TestCase):
    """Ensure the bastion receives a verified but inactive remediator."""

    def test_build_path_is_reproducible_and_ci_builds_before_tofu_validation(
        self,
    ) -> None:
        """The local task and CI build the same Linux amd64 artifact path."""
        build_script = BUILD_SCRIPT_PATH.read_text(encoding="utf-8")
        taskfile = TASKFILE_PATH.read_text(encoding="utf-8")
        ci = CI_PATH.read_text(encoding="utf-8")

        self.assertIn("GOOS=linux", build_script)
        self.assertIn("GOARCH=amd64", build_script)
        self.assertIn("unset GOROOT", build_script)
        self.assertIn("artifacts/cpe-remediator", build_script)
        self.assertIn("touch -t 200001010000 artifacts/cpe-remediator", build_script)
        self.assertIn("build:cpe-remediator", taskfile)
        self.assertIn("scripts/build-cpe-remediator.sh", taskfile)
        self.assertIn("scripts/build-cpe-remediator.sh", ci)
        self.assertLess(
            ci.index("scripts/build-cpe-remediator.sh"),
            ci.index("Validate OpenTofu"),
        )

    def test_oci_deploy_tasks_build_before_open_tofu(self) -> None:
        """Plans and applies always refresh the artifact from source first."""
        taskfile = TASKFILE_PATH.read_text(encoding="utf-8")

        for task_name in ("deploy:oci", "deploy:oci:plan"):
            block = task_block(taskfile, task_name)
            self.assertIn("task: build:cpe-remediator", block)
            self.assertLess(
                block.index("task: build:cpe-remediator"), block.index("tofu init")
            )

    def test_local_oci_deploy_tasks_override_tfvars_with_an_explicit_executor_mode(
        self,
    ) -> None:
        """An explicitly set local mode has the same precedence as CI's -var mode."""
        taskfile = TASKFILE_PATH.read_text(encoding="utf-8")

        for task_name, plan_command in (
            ("deploy:oci", "tofu plan -out=tfplan"),
            ("deploy:oci:plan", "tofu plan"),
        ):
            block = task_block(taskfile, task_name)
            self.assertIn('if [ -n "${CPE_REMEDIATOR_MODE+x}" ]; then', block)
            self.assertIn('-var="cpe_remediator_mode=$CPE_REMEDIATOR_MODE"', block)
            self.assertLess(
                block.index(plan_command),
                block.index('-var="cpe_remediator_mode=$CPE_REMEDIATOR_MODE"'),
            )

    def test_ci_runs_delivery_tests(self) -> None:
        """CI exercises the delivery contract as well as static Go checks."""
        ci = CI_PATH.read_text(encoding="utf-8")

        self.assertIn("scripts.tests.test_cpe_remediator_delivery", ci)

    def test_deploy_jobs_each_build_the_remediator_before_plan_or_apply(self) -> None:
        """Plan and apply runners build independently because artifacts are not shared."""
        deploy = DEPLOY_CI_PATH.read_text(encoding="utf-8")

        for job_name, command in (("plan", "tofu plan"), ("apply", "tofu apply")):
            block = re.search(
                rf"(?ms)^  {job_name}:\n(.*?)(?=^  [^ \n][^:]*:|\Z)", deploy
            )
            self.assertIsNotNone(block, f"Deploy job not found: {job_name}")
            contents = block.group(1)
            self.assertIn("actions/setup-go", contents)
            self.assertIn("scripts/build-cpe-remediator.sh", contents)
            self.assertLess(
                contents.index("scripts/build-cpe-remediator.sh"),
                contents.index(command),
            )

    def test_validate_oci_initializes_and_validates_without_backend_credentials(
        self,
    ) -> None:
        """OCI validation uses a local backend and propagates OpenTofu failures."""
        script = VALIDATE_OCI_PATH.read_text(encoding="utf-8")

        self.assertIn("set -euo pipefail", script)
        self.assertIn("tofu init -backend=false", script)
        self.assertIn("tofu validate", script)

        with TemporaryDirectory() as temporary_directory:
            bin_directory = Path(temporary_directory) / "bin"
            bin_directory.mkdir()
            log_path = Path(temporary_directory) / "tofu.log"
            fake_tofu = bin_directory / "tofu"
            fake_tofu.write_text(
                '#!/usr/bin/env bash\nprintf \'%s\\n\' "$*" >> "$TOFU_LOG"\n',
                encoding="utf-8",
            )
            fake_tofu.chmod(0o755)
            environment = os.environ.copy()
            environment.update(
                {
                    "PATH": f"{bin_directory}{os.pathsep}{os.environ['PATH']}",
                    "TOFU_LOG": str(log_path),
                }
            )
            subprocess.run(
                ["bash", str(VALIDATE_OCI_PATH)],
                check=True,
                cwd=REPOSITORY_ROOT,
                env=environment,
            )

            self.assertEqual(
                log_path.read_text(encoding="utf-8").splitlines(),
                ["init -backend=false", "validate"],
            )

    def test_validate_builds_the_artifact_before_open_tofu(self) -> None:
        """Validation has the local file required by filesha256 on clean checkouts."""
        block = task_block(TASKFILE_PATH.read_text(encoding="utf-8"), "validate")

        self.assertIn("task: build:cpe-remediator", block)
        self.assertLess(
            block.index("task: build:cpe-remediator"), block.index("task: validate:oci")
        )

    def test_artifact_is_private_and_checksum_is_rendered_into_cloud_init(self) -> None:
        """OpenTofu uploads only to a private bucket and renders object identity."""
        remediator_tf = REMEDIATOR_TF_PATH.read_text(encoding="utf-8")
        data_tf = DATA_TF_PATH.read_text(encoding="utf-8")

        self.assertIn(
            'resource "oci_objectstorage_bucket" "cpe_remediator"', remediator_tf
        )
        self.assertIn("access_type", remediator_tf)
        self.assertIn('"NoPublicAccess"', remediator_tf)
        self.assertIn(
            'resource "oci_objectstorage_object" "cpe_remediator"', remediator_tf
        )
        self.assertIn("filesha256", remediator_tf)
        self.assertIn("cpe_remediator_bucket_name", data_tf)
        self.assertIn("cpe_remediator_object_name", data_tf)
        self.assertIn("cpe_remediator_sha256", data_tf)

    def test_executor_mode_retains_function_invocation_during_verify_local(
        self,
    ) -> None:
        """verify-local grants local permissions without removing Function invocation."""
        cpe_tf = CPE_TF_PATH.read_text(encoding="utf-8")
        policy = re.search(
            r'(?ms)resource "oci_identity_policy" "cpe_drift_check_bastion" \{(.*?)^\}',
            cpe_tf,
        )
        self.assertIsNotNone(policy)
        statements = policy.group(1)

        self.assertIn("to read objects", statements)
        self.assertIn("target.bucket.name", statements)
        self.assertIn("target.object.name", statements)
        self.assertIn(
            'contains(["function", "verify-local"], var.cpe_remediator_mode)',
            statements,
        )
        self.assertIn("to use functions-family", statements)
        self.assertIn(
            'contains(["verify-local", "local-remediator"], var.cpe_remediator_mode)',
            statements,
        )
        self.assertIn("to manage cpes", statements)
        self.assertIn("to manage ipsec-connections", statements)
        self.assertIn("to use drgs", statements)
        self.assertIn("to use secret-family", statements)
        self.assertIn("target.secret.id", statements)

    def test_executor_mode_defaults_to_function_and_retires_function_resources_before_local_activation(
        self,
    ) -> None:
        """The desired executor changes atomically without deleting VPN, Vault, artifact, or tag resources."""
        variables = (TOFU_DIRECTORY / "variables.tf").read_text(encoding="utf-8")
        cpe_tf = CPE_TF_PATH.read_text(encoding="utf-8")
        data_tf = DATA_TF_PATH.read_text(encoding="utf-8")
        remediator_tf = REMEDIATOR_TF_PATH.read_text(encoding="utf-8")
        bastion_tf = Bastion_TF_PATH.read_text(encoding="utf-8")

        mode = re.search(r'(?ms)variable "cpe_remediator_mode" \{(.*?)^\}', variables)
        self.assertIsNotNone(mode)
        self.assertIn('default     = "function"', mode.group(1))
        self.assertIn(
            'contains(["function", "verify-local", "retire-function", "local-remediator"]',
            mode.group(1),
        )
        self.assertIn('var.cpe_remediator_mode == "verify-local"', data_tf)
        self.assertIn('data "external" "cpe_remediator_retired"', remediator_tf)
        self.assertIn(
            'var.cpe_remediator_mode == "local-remediator" ? 1 : 0', remediator_tf
        )
        self.assertIn(
            'contains(["function", "verify-local"], var.cpe_remediator_mode)', cpe_tf
        )
        self.assertIn(
            'var.cpe_remediator_mode == "function" || var.cpe_remediator_mode == "verify-local"',
            data_tf,
        )
        self.assertIn(
            'enable_cpe_remediator_timer     = local.vpn_enabled && var.cpe_remediator_mode == "local-remediator"',
            data_tf,
        )

        for address in (
            'oci_identity_dynamic_group" "cpe_recreate_fn',
            'oci_identity_policy" "cpe_recreate_fn',
            'oci_artifacts_container_repository" "cpe_recreate_fn',
            'oci_functions_application" "cpe_recreate',
            'oci_functions_function" "cpe_recreate',
            'oci_logging_log_group" "cpe_recreate',
            'oci_logging_log" "cpe_recreate_fn',
            'oci_resource_scheduler_schedule" "cpe_recreate',
            'oci_identity_auth_token" "cpe_recreate_fn_push',
        ):
            self.assertIn(address, cpe_tf)
        self.assertIn(
            "count          = local.vpn_enabled && contains(["
            '"function", "verify-local"], var.cpe_remediator_mode) ? 1 : 0',
            cpe_tf,
        )
        self.assertIn(
            "count       = local.vpn_enabled && contains(["
            '"function", "verify-local"], var.cpe_remediator_mode) ? 1 : 0',
            cpe_tf,
        )
        self.assertIn(
            "count              = local.vpn_enabled && contains(["
            '"function", "verify-local"], var.cpe_remediator_mode) ? 1 : 0',
            cpe_tf,
        )
        self.assertIn("count          = local.vpn_enabled ? 1 : 0", remediator_tf)
        self.assertIn(
            'resource "oci_identity_tag_namespace" "cpe_remediator"', bastion_tf
        )

    def test_cutover_or_artifact_change_replaces_bastion_after_its_policy_without_releasing_ip(
        self,
    ) -> None:
        """Every cloud-init state change reaches a replacement only after its IAM policy is ready."""
        bastion_tf = Bastion_TF_PATH.read_text(encoding="utf-8")
        remediator_tf = REMEDIATOR_TF_PATH.read_text(encoding="utf-8")

        self.assertIn("replace_triggered_by", bastion_tf)
        self.assertIn("cpe_remediator_artifact", bastion_tf)
        self.assertIn("cpe_remediator_mode", remediator_tf)
        self.assertIn("depends_on", bastion_tf)
        self.assertIn("oci_objectstorage_object.cpe_remediator", bastion_tf)
        self.assertIn("oci_identity_policy.cpe_drift_check_bastion", bastion_tf)
        self.assertIn("oci_identity_tag.cpe_remediator_role", bastion_tf)
        self.assertIn("local.vpn_enabled", remediator_tf)
        self.assertIn('lifetime       = "RESERVED"', bastion_tf)

    def test_bastion_dynamic_group_uses_stable_defined_tag_identity(self) -> None:
        """Replacement instances retain their artifact-read principal identity."""
        bastion_tf = Bastion_TF_PATH.read_text(encoding="utf-8")
        cpe_tf = CPE_TF_PATH.read_text(encoding="utf-8")

        self.assertIn(
            'resource "oci_identity_tag_namespace" "cpe_remediator"', bastion_tf
        )
        self.assertIn('resource "oci_identity_tag" "cpe_remediator_role"', bastion_tf)
        self.assertIn("defined_tags", bastion_tf)
        self.assertIn("tag.cpe_remediator.bastion_role.value", cpe_tf)
        self.assertNotIn("instance.id = '${oci_core_instance.bastion[0].id}'", cpe_tf)

    def test_cloud_init_has_mutually_exclusive_executor_timers(self) -> None:
        """A bad download cannot replace the executable and the two executors never share a render."""
        cloud_init = CLOUD_INIT_PATH.read_text(encoding="utf-8")

        self.assertIn("oci --auth instance_principal os object get", cloud_init)
        self.assertIn("sha256sum -c", cloud_init)
        self.assertIn("install -m 0755", cloud_init)
        self.assertIn("mv -f", cloud_init)
        self.assertIn("for attempt in", cloud_init)
        self.assertIn("sleep", cloud_init)
        self.assertIn("/etc/systemd/system/cpe-remediator.service", cloud_init)
        self.assertIn("/etc/systemd/system/cpe-remediator.timer", cloud_init)
        self.assertIn("OnUnitActiveSec=5min", cloud_init)
        self.assertIn("%{ if enable_cpe_drift_check ~}", cloud_init)
        self.assertIn("%{ if enable_cpe_remediator_timer ~}", cloud_init)
        self.assertIn("enable, --now, cpe-remediator.timer", cloud_init)

    @unittest.skipUnless(
        os.environ.get("TOFU_BIN") or shutil.which("tofu"),
        "OpenTofu is required to render cloud-init",
    )
    def test_rendered_cloud_init_has_exactly_one_executor_for_each_cutover_state(
        self,
    ) -> None:
        """Fixture rendering covers the active template path, not just its source text."""
        tofu = os.environ.get("TOFU_BIN") or shutil.which("tofu")
        expression = textwrap.dedent(
            """\
            templatefile("files/cloud-init-bastion.yaml.tmpl", {
              ssh_public_key = "ssh-ed25519 AAAATEST fixture"
              extra_ssh_keys = []
              primary_nic = "ens3"
              knock_sequence = "1111:tcp"
              knock_timeout = 10
              ssh_window_seconds = 60
              knock_ports = [1111]
              enable_vpn_probe = false
              omni_target_ip = "10.0.0.1"
               enable_cpe_drift_check = __DRIFT_CHECK__
               cpe_recreate_function_id = "ocid1.fnfunc.fixture"
               enable_cpe_remediator = true
               enable_cpe_remediator_timer = __LOCAL_TIMER__
               enable_oci_cli = true
              cpe_remediator_bucket_name = "cpe-remediator-fixture"
              cpe_remediator_object_name = "cpe-remediator-linux-amd64"
               cpe_remediator_sha256 = "0000000000000000000000000000000000000000000000000000000000000000"
              cpe_remediator_compartment_id = "ocid1.compartment.fixture"
              cpe_remediator_ddns_hostname = "home.example.test"
              cpe_remediator_local_identifier = "203.0.113.10"
              cpe_remediator_drg_id = "ocid1.drg.fixture"
              cpe_remediator_static_routes_json = "[\\\"10.0.0.0/24\\\"]"
              cpe_remediator_secret_id = "ocid1.vaultsecret.fixture"
            })
            """
        )
        expression = expression.replace(
            'templatefile("files/cloud-init-bastion.yaml.tmpl"',
            f'templatefile("{CLOUD_INIT_PATH}"',
        )
        for mode, drift_check, local_timer in (
            ("function", True, False),
            ("verify-local", True, False),
            ("retire-function", False, False),
            ("local-remediator", False, True),
        ):
            with TemporaryDirectory() as temporary_directory:
                result = subprocess.run(
                    [tofu, "console", "-no-color"],
                    input=expression.replace(
                        "__DRIFT_CHECK__", str(drift_check).lower()
                    ).replace("__LOCAL_TIMER__", str(local_timer).lower()),
                    text=True,
                    capture_output=True,
                    check=True,
                    cwd=temporary_directory,
                )
            rendered = result.stdout

            self.assertIn("oci --auth instance_principal os object get", rendered)
            self.assertIn('"cpe-remediator-fixture"', rendered)
            self.assertIn("sha256sum -c", rendered)
            self.assertIn('mv -f "$staged" /usr/local/bin/cpe-remediator', rendered)
            self.assertIn("pipx install oci-cli", rendered)
            self.assertEqual("cpe-drift-check.timer" in rendered, drift_check, mode)
            self.assertEqual(
                "enable, --now, cpe-remediator.timer" in rendered, local_timer, mode
            )

    def test_deploy_workflow_preserves_targeted_destructive_plan_protection(
        self,
    ) -> None:
        """Cutover remains an operator-reviewed targeted plan, not a workflow bypass."""
        deploy = DEPLOY_CI_PATH.read_text(encoding="utf-8")

        self.assertIn("Reject destructive plan", deploy)
        self.assertIn("destroy=true requires explicit targets", deploy)
        self.assertIn("replace requires allow_replace=true", deploy)
        self.assertIn("destructive change outside requested targets", deploy)
        self.assertIn("cpe_remediator_mode", deploy)
        self.assertIn('-var="cpe_remediator_mode=$CPE_REMEDIATOR_MODE"', deploy)
        self.assertIn("enable_cpe_remediator|cpe_remediator_mode", deploy)
        self.assertIn("must be set only through cpe_remediator_mode", deploy)

    def test_local_mode_workflow_preflight_requires_completed_function_retirement(
        self,
    ) -> None:
        """A direct local-mode apply cannot remove the Function while enabling the local timer."""
        deploy = DEPLOY_CI_PATH.read_text(encoding="utf-8")

        self.assertEqual(deploy.count("Verify local remediator retirement"), 2)
        self.assertIn('CPE_REMEDIATOR_MODE" != "local-remediator"', deploy)
        self.assertIn("oci fn function list", deploy)
        self.assertIn("oci resource-scheduler schedule list", deploy)
        self.assertIn("Complete the reviewed retire-function apply first", deploy)
        self.assertLess(
            deploy.index("Verify local remediator retirement"),
            deploy.index("      - name: Tofu Plan"),
        )
        self.assertLess(
            deploy.rindex("Verify local remediator retirement"),
            deploy.rindex("      - name: Tofu Apply"),
        )

    def test_extra_tfvars_are_validated_and_passed_as_quoted_array_entries(
        self,
    ) -> None:
        """Free-form variables cannot inject flags, whitespace, or executor controls into OpenTofu."""
        deploy = DEPLOY_CI_PATH.read_text(encoding="utf-8")

        self.assertIn("EXTRA_TFVARS_ARGS=()", deploy)
        self.assertIn("^[A-Za-z_][A-Za-z0-9_]*=", deploy)
        self.assertIn("invalid extra_tfvars assignment", deploy)
        self.assertIn('EXTRA_TFVARS_ARGS+=("-var=$line")', deploy)
        self.assertIn('"${EXTRA_TFVARS_ARGS[@]}"', deploy)
        self.assertNotIn('EXTRA_TFVARS_ARGS="$EXTRA_TFVARS_ARGS -var=$line"', deploy)

    def test_cutover_runbook_requires_an_explicit_reviewed_targeted_workflow(
        self,
    ) -> None:
        """Operators have a source-controlled command that uses, rather than bypasses, workflow guards."""
        runbook = CUTOVER_RUNBOOK_PATH.read_text(encoding="utf-8")

        self.assertIn("retire-function", runbook)
        self.assertIn("local-remediator", runbook)
        self.assertIn("three reviewed applies", runbook)
        self.assertIn("allow_replace=true", runbook)
        self.assertIn("targets", runbook)
        self.assertIn("Function invocation timer", runbook)
        self.assertIn("no-op", runbook)


if __name__ == "__main__":
    unittest.main()
