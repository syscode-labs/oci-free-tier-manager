# CPE Remediator Cutover

`cpe_remediator_mode` defaults to `function`. It has three mutually exclusive
executor states:

- `function`: OCI Function, Resource Scheduler, and Function invocation timer
  remain active; the local timer is disabled.
- `verify-local`: Function scheduling remains active and the local timer stays
  disabled, while the bastion receives the local remediator's CPE/IPSec/DRG/Vault
  permissions for one manual no-op verification.
- `retire-function`: Function-only OCI resources are absent; cloud-init disables
  both executor timers.
- `local-remediator`: Function-only OCI resources remain absent; only the local
  timer is enabled.

First move to `verify-local`, then confirm the staged binary download and no-op on the bastion:

```bash
sudo /usr/local/sbin/install-cpe-remediator
sudo /usr/local/bin/cpe-remediator
sudo systemctl status cpe-remediator.timer cpe-drift-check.timer
```

The binary run must be a verified no-op against matching DDNS/CPE state. Do not
continue if the download, checksum, or no-op check fails. The Function invocation
timer must still be active and the local timer disabled before the cutover plan.

## Two Reviewed Applies

Use the `Deploy` workflow at the reviewed commit. This intentionally uses the
existing destructive-plan protection; it does not bypass or weaken it. The
three reviewed applies are required: `verify-local`, `retire-function`, then
`local-remediator`.

## IAM Scope

OCI IAM does not support a resource-OCID condition for CPEs, IPSec connections,
or DRGs. The active remediator policy therefore has the narrowest OCI-supported
scope: `manage cpes`, `manage ipsec-connections`, and `use drgs` in this
compartment. This is an OCI policy-model limitation, not a broader intended
authority. The Vault permission remains restricted to the exact
`cpe-tunnel-details` secret OCID with `target.secret.id`.

Use the `Deploy` workflow at the reviewed commit. It retains the existing
destructive-plan protection; it does not bypass or weaken it. Each apply starts
with `apply=false`, `allow_replace=true`, and the following space-separated
   `targets` value. The existing workflow permits deletes only when every delete
   matches an explicit target.

   ```text
   oci_core_instance.bastion[0]
   oci_identity_policy.cpe_drift_check_bastion[0]
   oci_identity_dynamic_group.cpe_recreate_fn[0]
   oci_identity_policy.cpe_recreate_fn[0]
   oci_artifacts_container_repository.cpe_recreate_fn[0]
   oci_functions_application.cpe_recreate[0]
   oci_functions_function.cpe_recreate[0]
   oci_logging_log_group.cpe_recreate[0]
   oci_logging_log.cpe_recreate_fn[0]
   oci_resource_scheduler_schedule.cpe_recreate[0]
   oci_identity_auth_token.cpe_recreate_fn_push[0]
   ```

1. Set `cpe_remediator_mode=retire-function`. Do not pass executor keys through
   `extra_tfvars`; the workflow rejects both the removed boolean and mode key.
   Extra values must be one safe `key=value` assignment per line: no whitespace,
   flags, shell syntax, or command substitution.

2. Review and apply the targeted plan. It must remove the Function invocation
   timer and all Function-only resources, replace the bastion policy
   with CPE/IPSec/DRG/the single Vault-secret permissions, and retain the Vault,
   VPN, private artifact bucket/object, and `cpe_remediator` bastion IAM tag.
   It must not contain an unlisted destructive change. Verify neither executor
   timer is active after this apply.

3. Start a second reviewed plan with the same targets and
   `cpe_remediator_mode=local-remediator`. Verify it enables only
   `cpe-remediator.timer`, then apply. Do not use `destroy=true`; these are
   normal targeted applies with intentional Function-resource deletions only in
   the first stage. The workflow queries OCI before both plan and apply and
   refuses local mode while the named Function or scheduler still exists.

4. After the second apply, confirm exactly one executor is active:

   ```bash
   sudo systemctl is-enabled cpe-remediator.timer
   sudo systemctl is-active cpe-remediator.timer
   sudo systemctl is-enabled cpe-drift-check.timer || true
   sudo systemctl is-active cpe-drift-check.timer || true
   sudo journalctl -u cpe-remediator.service -n 100 --no-pager
   ```

Only then perform the separately approved controlled IP-drift recovery and record
the Vault-backed phase evidence. This runbook does not authorize an OCI apply by
itself.
