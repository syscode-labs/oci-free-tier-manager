/*
 * Auto-recreate the home VPN CPE/tunnels when the home router's public IP drifts.
 * See: syscode-ai-internal-plans/projects/oci-free-tier-manager/openspec/
 *      changes/oci-cpe-auto-recreate/
 *
 * Everything here is gated on local.vpn_enabled, same as the rest of vpn.tf.
 */

# ---------------------------------------------------------------------------
# Vault + key + secret. The Function writes new tunnel PSKs/public IPs here
# after a recreate; the home router reads it (read-only, separately-scoped token)
# to re-sync swanctl.conf. Bootstrapped with a placeholder so the Function's
# read-if-present-else-create logic has something to read on first run.
# ---------------------------------------------------------------------------
resource "oci_kms_vault" "cpe_secrets" {
  count          = local.vpn_enabled ? 1 : 0
  compartment_id = local.compartment_id
  display_name   = "oci-lab-cpe-secrets"
  vault_type     = "DEFAULT" # software-protected, Always Free eligible
}

resource "oci_kms_key" "cpe_secrets" {
  count               = local.vpn_enabled ? 1 : 0
  compartment_id      = local.compartment_id
  display_name        = "oci-lab-cpe-secrets-key"
  management_endpoint = oci_kms_vault.cpe_secrets[0].management_endpoint

  key_shape {
    algorithm = "AES"
    length    = 32
  }
}

resource "oci_vault_secret" "cpe_tunnel_details" {
  count          = local.vpn_enabled ? 1 : 0
  compartment_id = local.compartment_id
  vault_id       = oci_kms_vault.cpe_secrets[0].id
  key_id         = oci_kms_key.cpe_secrets[0].id
  secret_name    = "cpe-tunnel-details" # pragma: allowlist secret

  secret_content {
    content_type = "BASE64"
    # Placeholder JSON: {"tunnel1_ip":null,"tunnel1_psk":null,"tunnel2_ip":null,"tunnel2_psk":null,"updated_at":null}
    content = base64encode(jsonencode({
      tunnel1_ip  = null
      tunnel1_psk = null
      tunnel2_ip  = null
      tunnel2_psk = null
      updated_at  = null
    }))
  }

  # The Function writes new versions directly via the SDK; Terraform should
  # not fight it over content after the initial bootstrap version.
  lifecycle {
    ignore_changes = [secret_content]
  }
}

# ---------------------------------------------------------------------------
# IAM. Dynamic groups are always tenancy-level in OCI (matches the existing
# convention in main.tf for groups/users/policies). Policy is scoped as
# narrowly as the CPE-recreate operation actually needs: manage the specific
# network resource-types involved, read/use the one secret above — nothing
# else in the compartment, no account-wide rights.
# ---------------------------------------------------------------------------
resource "oci_identity_dynamic_group" "cpe_recreate_fn" {
  count          = local.vpn_enabled && contains(["function", "verify-local"], var.cpe_remediator_mode) ? 1 : 0
  compartment_id = var.tenancy_ocid
  name           = "oci-lab-cpe-recreate-fn"
  description    = "Matches the CPE auto-recreate OCI Function's resource principal"
  matching_rule  = "ALL {resource.type = 'fnfunc', resource.compartment.id = '${local.compartment_id}'}"
}

resource "oci_identity_policy" "cpe_recreate_fn" {
  count          = local.vpn_enabled && contains(["function", "verify-local"], var.cpe_remediator_mode) ? 1 : 0
  compartment_id = var.tenancy_ocid
  name           = "oci-lab-cpe-recreate-fn-policy"
  description    = "Least-privilege policy for the CPE auto-recreate Function — network CPE/IPSec/tunnel management plus one Vault secret, nothing else"

  statements = [
    # cpes + ipsec-connections: no separate resource-type for tunnels --
    # UpdateIPSecConnectionTunnel etc. are covered by IPSEC_CONNECTION_UPDATE,
    # part of "manage ipsec-connections" itself. Confirmed against OCI's
    # Core Services policy reference, not guessed -- getting either of these
    # resource-type names wrong fails silently at apply time (Terraform
    # doesn't validate policy statement strings) and only surfaces as a 403
    # when the Function actually runs.
    "Allow dynamic-group ${oci_identity_dynamic_group.cpe_recreate_fn[0].name} to manage cpes in compartment id ${local.compartment_id}",
    "Allow dynamic-group ${oci_identity_dynamic_group.cpe_recreate_fn[0].name} to manage ipsec-connections in compartment id ${local.compartment_id}",
    "Allow dynamic-group ${oci_identity_dynamic_group.cpe_recreate_fn[0].name} to use secret-family in compartment id ${local.compartment_id} where target.secret.id = '${oci_vault_secret.cpe_tunnel_details[0].id}'",
    # CreateIPSecConnection against a DRG requires DRG_ATTACH on the drgs
    # resource-type too, not just manage on cpes/ipsec-connections --
    # missed on the first pass, only surfaced as a live 404
    # NotAuthorizedOrNotFound on create_ip_sec_connection during the first
    # real forced-drift test (2026-08-15). No `where target.drg.id = ...`
    # scoping here -- confirmed against OCI's own Core Services policy
    # reference, drgs has no documented resource-specific condition
    # variable (unlike target.secret.id/target.function.id above, which
    # are real). A first attempt with that condition silently granted
    # nothing -- unsupported condition variables don't error, they just
    # never match.
    "Allow dynamic-group ${oci_identity_dynamic_group.cpe_recreate_fn[0].name} to use drgs in compartment id ${local.compartment_id}",
  ]
}

# ---------------------------------------------------------------------------
# Function deployment. Image is built + pushed manually for now (see
# openspec/changes/oci-cpe-auto-recreate, Out of Scope: CI wiring for the
# image pipeline is a follow-up once the Function itself is proven working).
# Reuses the existing NAT-routed subnet (outbound internet for image pull +
# DNS resolution of the DDNS hostname; Resource Principal calls to other OCI
# services don't need internet) rather than creating a new one.
# ---------------------------------------------------------------------------
resource "oci_artifacts_container_repository" "cpe_recreate_fn" {
  count          = local.vpn_enabled && contains(["function", "verify-local"], var.cpe_remediator_mode) ? 1 : 0
  compartment_id = local.compartment_id
  display_name   = "cpe-auto-recreate"
}

resource "oci_functions_application" "cpe_recreate" {
  count          = local.vpn_enabled && contains(["function", "verify-local"], var.cpe_remediator_mode) ? 1 : 0
  compartment_id = local.compartment_id
  display_name   = "cpe-auto-recreate"
  subnet_ids     = [local.subnet_id]
}

resource "oci_functions_function" "cpe_recreate" {
  count              = local.vpn_enabled && contains(["function", "verify-local"], var.cpe_remediator_mode) ? 1 : 0
  application_id     = oci_functions_application.cpe_recreate[0].id
  display_name       = "cpe-auto-recreate"
  memory_in_mbs      = "256"
  timeout_in_seconds = 300
  image              = var.cpe_recreate_fn_image
  image_digest       = var.cpe_recreate_fn_image_digest

  # Exposed to the Function as environment variables -- see func.py's
  # handler(), which reads these via os.environ rather than the invocation
  # payload (Resource Scheduler fires a bare invoke with no body).
  config = {
    COMPARTMENT_ID          = local.compartment_id
    DDNS_HOSTNAME           = var.ddns_hostname
    CPE_LOCAL_IDENTIFIER    = var.cpe_local_identifier
    DRG_ID                  = oci_core_drg.vpn_drg[0].id
    STATIC_ROUTE_CIDRS_JSON = jsonencode(local.vpn_static_route_cidrs)
    SECRET_ID               = oci_vault_secret.cpe_tunnel_details[0].id
  }
}

# Read-only observability -- captures the Function's own stdout/stderr
# (Python tracebacks included) on invoke. Added specifically to diagnose the
# first real end-to-end invoke's "502 FunctionInvokeExecutionFailed" with no
# detail otherwise available. Safe/additive, no effect on live CPE/tunnel
# resources.
resource "oci_logging_log_group" "cpe_recreate" {
  count          = local.vpn_enabled && contains(["function", "verify-local"], var.cpe_remediator_mode) ? 1 : 0
  compartment_id = local.compartment_id
  display_name   = "cpe-auto-recreate-logs"
}

resource "oci_logging_log" "cpe_recreate_fn" {
  count              = local.vpn_enabled && contains(["function", "verify-local"], var.cpe_remediator_mode) ? 1 : 0
  display_name       = "cpe-auto-recreate-fn-invoke"
  log_group_id       = oci_logging_log_group.cpe_recreate[0].id
  log_type           = "SERVICE"
  is_enabled         = true
  retention_duration = 30

  configuration {
    source {
      category    = "invoke"
      resource    = oci_functions_application.cpe_recreate[0].id
      service     = "functions"
      source_type = "OCISERVICE"
    }
  }
}

# action = "START_RESOURCE" invokes the target Function on each firing.
# Confirmed against the live API, not docs -- ValidateResourceTypeConfig
# accepted the wrong value "START" at plan time; only the real
# ApplyResourceChange call rejected it: "unsupported enum value for Action:
# START. Supported values are: START_RESOURCE,STOP_RESOURCE,BACKUP_RESOURCE."
resource "oci_resource_scheduler_schedule" "cpe_recreate" {
  count          = local.vpn_enabled && contains(["function", "verify-local"], var.cpe_remediator_mode) ? 1 : 0
  compartment_id = local.compartment_id
  display_name   = "cpe-auto-recreate-schedule"
  description    = "Hourly: check var.ddns_hostname against the CPE's registered IP, recreate on drift"
  action         = "START_RESOURCE"
  # Confirmed against the live API: 400-InvalidParameter, "Invalid
  # recurrenceDetails. Frequency cannot be higher than HOURLY" -- Resource
  # Scheduler caps cron frequency at hourly, sub-hourly crons are rejected.
  recurrence_type    = "CRON"
  recurrence_details = "0 * * * *"

  resources {
    id = oci_functions_function.cpe_recreate[0].id
  }
}

# OCIR push auth. Docker-API-compatible registries authenticate with an OCI
# Auth Token, not the API signing key used elsewhere in this repo. The token
# value is only ever returned once, at creation -- captured into state here
# and surfaced via the sensitive output below, then piped straight into
# Bitwarden Secrets Manager (never printed/logged in plain text).
resource "oci_identity_auth_token" "cpe_recreate_fn_push" {
  count       = local.vpn_enabled && contains(["function", "verify-local"], var.cpe_remediator_mode) ? 1 : 0
  user_id     = var.cpe_recreate_fn_push_user_ocid
  description = "OCIR push for functions/cpe-auto-recreate — see openspec/changes/oci-cpe-auto-recreate"
}

# ---------------------------------------------------------------------------
# Bastion sub-hourly drift-check trigger. OCI Resource Scheduler's own cron
# floor is hourly (confirmed via a real API error, not docs -- see the
# Scheduler resource above), so the already-running bastion invokes the
# Function every 5 min via a systemd timer (cloud-init-bastion.yaml.tmpl).
# The Scheduler's hourly cron stays as a backup for when the bastion itself
# is down. IAM is scoped to exactly this: one instance, one verb (use =
# invoke, which also covers the CLI's own GetFunction endpoint lookup),
# one target function -- nothing else.
# ---------------------------------------------------------------------------
resource "oci_identity_dynamic_group" "cpe_drift_check_bastion" {
  count          = local.vpn_enabled && var.create_bastion ? 1 : 0
  compartment_id = var.tenancy_ocid
  name           = "oci-lab-cpe-drift-check-bastion"
  description    = "Matches the bastion instance that triggers cpe-auto-recreate drift checks"
  matching_rule  = "All {instance.compartment.id = '${local.compartment_id}', tag.cpe_remediator.bastion_role.value = 'true'}"
}

resource "oci_identity_policy" "cpe_drift_check_bastion" {
  count          = local.vpn_enabled && var.create_bastion ? 1 : 0
  compartment_id = var.tenancy_ocid
  name           = "oci-lab-cpe-drift-check-bastion-policy"
  description    = "Least-privilege policy for the staged artifact or active local CPE remediator"

  statements = concat(contains(["function", "verify-local"], var.cpe_remediator_mode) ? [
    # Function and verify-local modes retain the Function-invocation grant.
    "Allow dynamic-group ${oci_identity_dynamic_group.cpe_drift_check_bastion[0].name} to use functions-family in compartment id ${local.compartment_id} where target.function.id = '${oci_functions_function.cpe_recreate[0].id}'",
    "Allow dynamic-group ${oci_identity_dynamic_group.cpe_drift_check_bastion[0].name} to read objects in compartment id ${local.compartment_id} where all {target.bucket.name = '${oci_objectstorage_bucket.cpe_remediator[0].name}', target.object.name = '${local.cpe_remediator_object_name}'}",
    ] : [
    # Post-Function modes remove invocation permission before local activation.
    "Allow dynamic-group ${oci_identity_dynamic_group.cpe_drift_check_bastion[0].name} to read objects in compartment id ${local.compartment_id} where all {target.bucket.name = '${oci_objectstorage_bucket.cpe_remediator[0].name}', target.object.name = '${local.cpe_remediator_object_name}'}",
    ], contains(["verify-local", "local-remediator"], var.cpe_remediator_mode) ? [
    # verify-local grants the local remediator's no-op permissions before its timer is enabled.
    "Allow dynamic-group ${oci_identity_dynamic_group.cpe_drift_check_bastion[0].name} to manage cpes in compartment id ${local.compartment_id}",
    "Allow dynamic-group ${oci_identity_dynamic_group.cpe_drift_check_bastion[0].name} to manage ipsec-connections in compartment id ${local.compartment_id}",
    "Allow dynamic-group ${oci_identity_dynamic_group.cpe_drift_check_bastion[0].name} to use drgs in compartment id ${local.compartment_id}",
    "Allow dynamic-group ${oci_identity_dynamic_group.cpe_drift_check_bastion[0].name} to use secret-family in compartment id ${local.compartment_id} where target.secret.id = '${oci_vault_secret.cpe_tunnel_details[0].id}'",
  ] : [])
}
