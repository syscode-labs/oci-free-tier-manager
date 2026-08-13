/*
 * Auto-recreate the home VPN CPE/tunnels when REDACTED-ROUTER-HOSTNAME's public IP drifts.
 * See: syscode-ai-internal-plans/projects/oci-free-tier-manager/openspec/
 *      changes/oci-cpe-auto-recreate/
 *
 * Everything here is gated on local.vpn_enabled, same as the rest of vpn.tf.
 */

# ---------------------------------------------------------------------------
# Vault + key + secret. The Function writes new tunnel PSKs/public IPs here
# after a recreate; REDACTED-ROUTER-HOSTNAME reads it (read-only, separately-scoped token)
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
  count          = local.vpn_enabled ? 1 : 0
  compartment_id = var.tenancy_ocid
  name           = "oci-lab-cpe-recreate-fn"
  description    = "Matches the CPE auto-recreate OCI Function's resource principal"
  matching_rule  = "ALL {resource.type = 'fnfunc', resource.compartment.id = '${local.compartment_id}'}"
}

resource "oci_identity_policy" "cpe_recreate_fn" {
  count          = local.vpn_enabled ? 1 : 0
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
  ]
}
