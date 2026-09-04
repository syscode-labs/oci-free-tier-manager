/*
 * Output values for easy access to created resources
 */

output "vcn_id" {
  description = "ID of the VCN (null if existing_subnet_ocid is set)"
  value       = length(oci_core_vcn.free_tier_vcn) > 0 ? oci_core_vcn.free_tier_vcn[0].id : null
}

output "subnet_id" {
  description = "ID of the subnet (existing or created)"
  value       = local.subnet_id
}

# ---------------------------------------------------------------------------
# Ampere A1 instances
# ---------------------------------------------------------------------------

output "ampere_instance_ids" {
  description = "IDs of Ampere A1 instances"
  value       = oci_core_instance.ampere_instance[*].id
}

output "ampere_instance_names" {
  description = "Names of Ampere A1 instances"
  value       = oci_core_instance.ampere_instance[*].display_name
}

output "ampere_instance_public_ips" {
  description = "Public IP addresses of Ampere A1 instances (explicit reserved IP resources)"
  value       = oci_core_public_ip.ampere_instance[*].ip_address
}

output "ampere_private_ips" {
  description = "Private IPs of Ampere nodes (for Ansible inventory)"
  value       = oci_core_instance.ampere_instance[*].private_ip
}

output "ampere_shapes" {
  description = "Shape and size of each Ampere A1 instance"
  value = [
    for i, n in local._ampere_nodes : {
      name        = n.name
      ocpus       = n.ocpus
      memory_gb   = n.memory_gb
      boot_vol_gb = n.boot_vol_gb
    }
  ]
}

# ---------------------------------------------------------------------------
# E2.1.Micro instances
# ---------------------------------------------------------------------------

output "micro_instance_ids" {
  description = "IDs of E2.1.Micro instances"
  value       = oci_core_instance.micro_instance[*].id
}

output "micro_instance_names" {
  description = "Names of E2.1.Micro instances"
  value       = oci_core_instance.micro_instance[*].display_name
}

output "micro_instance_public_ips" {
  description = "Public IP addresses of E2.1.Micro workload instances (empty; access via bastion only)"
  value       = []
}

output "micro_private_ips" {
  description = "Private IPs of Micro instances"
  value       = oci_core_instance.micro_instance[*].private_ip
}

output "micro_shapes" {
  description = "Shape and size of each E2.1.Micro instance"
  value = [
    for n in local._micro_nodes : {
      name        = n.name
      shape       = "VM.Standard.E2.1.Micro"
      boot_vol_gb = n.boot_vol_gb
    }
  ]
}

# ---------------------------------------------------------------------------
# Reserved IPs
# ---------------------------------------------------------------------------

output "bastion_reserved_ip" {
  description = "Reserved public IP for the self-managed bastion host"
  value       = length(oci_core_public_ip.bastion) > 0 ? oci_core_public_ip.bastion[0].ip_address : null
}

output "bastion_private_ip" {
  description = "Private IP of the self-managed bastion host"
  value       = length(oci_core_instance.bastion) > 0 ? oci_core_instance.bastion[0].private_ip : null
}

output "ampere_ssh_reserved_ip" {
  description = "Reserved public IP for the first Ampere node (null if no Ampere nodes)"
  value       = length(oci_core_public_ip.ampere_instance) > 0 ? oci_core_public_ip.ampere_instance[0].ip_address : null
}

output "ingress_reserved_ip" {
  description = "Reserved public IP for the K8s ingress controller (null if create_ingress_ip = false)"
  value       = var.create_ingress_ip ? oci_core_public_ip.ingress[0].ip_address : null
}

# ---------------------------------------------------------------------------
# Load Balancer
# ---------------------------------------------------------------------------

output "load_balancer_ip" {
  description = "Public IP of the free-tier load balancer (null if not created)"
  value       = length(oci_load_balancer_load_balancer.free_tier_lb) > 0 ? try(oci_load_balancer_load_balancer.free_tier_lb[0].ip_address_details[0].ip_address, null) : null
}

output "load_balancer_id" {
  description = "ID of the load balancer (null if not created)"
  value       = length(oci_load_balancer_load_balancer.free_tier_lb) > 0 ? oci_load_balancer_load_balancer.free_tier_lb[0].id : null
}

# ---------------------------------------------------------------------------
# Budget
# ---------------------------------------------------------------------------

output "budget_id" {
  description = "ID of the budget alert (null if create_budget = false)"
  value       = var.create_budget ? oci_budget_budget.free_tier_budget[0].id : null
}

output "budget_target_compartment_id" {
  description = "Compartment targeted by the cost budget (tenancy root for account-wide coverage)"
  value       = var.create_budget ? var.tenancy_ocid : null
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

output "ssh_connection_commands" {
  description = "SSH commands to connect to instances (Ubuntu mode only; Talos nodes use Talos API)"
  value = concat(
    [for i, public_ip in oci_core_public_ip.ampere_instance : "ssh ubuntu@${public_ip.ip_address}  # ${local._ampere_nodes[i].name}"],
    length(oci_core_public_ip.bastion) > 0 ? [
      "# Knock sequence: ${join(", ", [for p in var.bastion_knock_ports : "${p}/tcp"])}",
      "ssh ubuntu@${oci_core_public_ip.bastion[0].ip_address}  # ${var.bastion_name}",
    ] : [],
    [for i in range(length(local._micro_nodes)) : "ssh ubuntu@${oci_core_instance.micro_instance[i].private_ip}  # ${local._micro_nodes[i].name} (via bastion)"]
  )
}

# ---------------------------------------------------------------------------
# Managed compartment and IAM user (only populated when create_compartment = true)
# ---------------------------------------------------------------------------

output "managed_compartment_id" {
  description = "OCID of the managed compartment (null if create_compartment = false)"
  value       = var.create_compartment ? oci_identity_compartment.managed[0].id : null
}

output "iam_user_ocid" {
  description = "OCID of the IAM service user (null if create_compartment = false)"
  value       = var.create_compartment ? oci_identity_user.free_tier[0].id : null
}

output "iam_user_name" {
  description = "Name of the IAM service user (null if create_compartment = false)"
  value       = var.create_compartment ? oci_identity_user.free_tier[0].name : null
}

output "iam_api_key_fingerprint" {
  description = "Fingerprint of the registered API key (null if iam_api_public_key not provided)"
  value       = var.create_compartment && var.iam_api_public_key != null ? oci_identity_api_key.free_tier[0].fingerprint : null
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Site-to-Site VPN — handoff interface to the OpenWrt side (plan Task 5→7).
# Empty when enable_oci_vpn = false.
# ---------------------------------------------------------------------------

# Tunnel public IPs / PSKs are no longer surfaced as Terraform outputs: the
# Function rewrites both tunnels' OCIDs (and PSKs) on every recreate, so a
# `tofu output` here would go stale exactly like the removed resources did.
# The Vault secret (oci_vault_secret.cpe_tunnel_details) is the live handoff
# interface to the OpenWrt side now -- read it directly, e.g.:
#   oci secrets secret-bundle get --secret-id <id> --raw-output \
#     --query 'data."secret-bundle-content".content' | base64 -d

output "oci_vpn_cpe_id" {
  description = "OCID of the CPE (home OpenWrt) — for OCI console tunnel detail lookups. Resolved by display_name lookup, not a managed resource; see vpn.tf."
  value       = local.home_cpe_id
}

output "oci_vpn_ipsec_id" {
  description = "OCID of the IPSec connection. Resolved by display_name lookup, not a managed resource; see vpn.tf."
  value       = local.home_ipsec_id
}

output "oci_vpn_probe_instance_id" {
  description = "OCID of the host running VPN probe tests (now the bastion; null unless enable_oci_vpn_probe=true)."
  value       = length(oci_core_instance.bastion) > 0 && local.vpn_probe_enabled ? oci_core_instance.bastion[0].id : null
}

output "resource_summary" {
  description = "Summary of provisioned free-tier resources"
  value = {
    ampere_nodes     = length(local._ampere_nodes)
    micro_nodes      = length(local._micro_nodes)
    bastion          = var.create_bastion
    total_ocpus      = local.total_ocpus
    total_ram_gb     = local.total_ram_gb
    total_storage_gb = local.total_storage_gb
    load_balancer    = var.load_balancer != null
  }
}

# One-time-visible OCIR push credential for functions/cpe-auto-recreate.
# Never printed in plan/apply output; pipe straight into Bitwarden Secrets
# Manager, don't `tofu output` this to a terminal.
output "cpe_recreate_fn_push_auth_token" {
  description = "One-time OCIR push credential for the Function image; null after local-remediator cutover."
  value       = local.vpn_enabled && contains(["function", "verify-local"], var.cpe_remediator_mode) ? oci_identity_auth_token.cpe_recreate_fn_push[0].token : null
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Public DNS — hosted directly by Cloudflare in the syscode.uk zone.
# ---------------------------------------------------------------------------
output "bastion_fqdn" {
  description = "Public DNS name for the bastion host."
  value       = var.create_bastion ? cloudflare_dns_record.bastion[0].name : null
}
