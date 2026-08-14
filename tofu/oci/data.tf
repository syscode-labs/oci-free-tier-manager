/*
 * Data sources and computed locals for OCI free-tier infrastructure
 */

# ---------------------------------------------------------------------------
# Availability domain — hardcoded for uk-london-1.
# The oci_identity_availability_domains data source returns null in some
# provider/profile combinations; ADs are stable and don't change.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Defaults
#
# This module enforces OCI Always Free compute/storage limits regardless of
# account type:
#   2 x A1.Flex (configurable OCPU/RAM, min 1 OCPU / 6 GB / 50 GB each)
#   2 x E2.1.Micro (fixed: 1/8 OCPU, 1 GB RAM, 50 GB boot volume each)
#   Total OCPUs: 2 (Ampere), plus up to 2 Micro instances
#   Total RAM  : 12 GB (Ampere); Micro add 1 GB each
#   Total storage: 200 GB block volume, SHARED across Ampere + Micro boot volumes
#   20 GB object storage, 10 TB egress/month
#
# OCPUs are CPU-only (API min=1, step=1).
# Boot volumes are allocated toward the shared 200 GB block-volume budget.
# ---------------------------------------------------------------------------
locals {
  _tier_defaults = {
    ampere_ocpus       = 1
    ampere_memory_gb   = 6
    ampere_boot_vol_gb = 50
    ampere_count       = 2
    micro_boot_vol_gb  = 50
  }
}

# ---------------------------------------------------------------------------
# Resolved Ampere node list
#
# If ampere_nodes is null, generate the tier-default list.
# If ampere_nodes is set, fill each node's missing fields with tier defaults.
# ---------------------------------------------------------------------------
locals {
  _default_ampere_nodes = [
    for i in range(local._tier_defaults.ampere_count) : {
      ocpus       = local._tier_defaults.ampere_ocpus
      memory_gb   = local._tier_defaults.ampere_memory_gb
      boot_vol_gb = local._tier_defaults.ampere_boot_vol_gb
      name        = "ampere-instance-${i + 1}"
      vpn_subnet  = false
    }
  ]

  _ampere_nodes = var.ampere_nodes != null ? [
    for i, n in var.ampere_nodes : {
      ocpus       = n.ocpus != null ? n.ocpus : local._tier_defaults.ampere_ocpus
      memory_gb   = n.memory_gb != null ? n.memory_gb : local._tier_defaults.ampere_memory_gb
      boot_vol_gb = n.boot_vol_gb != null ? n.boot_vol_gb : local._tier_defaults.ampere_boot_vol_gb
      name        = n.name != null ? n.name : "ampere-instance-${i + 1}"
      vpn_subnet  = n.vpn_subnet != null ? n.vpn_subnet : false
    }
  ] : local._default_ampere_nodes
}

# ---------------------------------------------------------------------------
# Resolved Micro node list
#
# If micro_nodes is null, generate no micro nodes.
# If micro_nodes is set (including []), use that list as-is.
# ---------------------------------------------------------------------------
locals {
  _default_micro_nodes = []

  _micro_nodes = var.micro_nodes != null ? [
    for i, n in var.micro_nodes : {
      boot_vol_gb = n.boot_vol_gb != null ? n.boot_vol_gb : local._tier_defaults.micro_boot_vol_gb
      name        = n.name != null ? n.name : "micro-instance-${i + 1}"
    }
  ] : local._default_micro_nodes
}

# ---------------------------------------------------------------------------
# Budget totals (used by check blocks in validation.tf)
# ---------------------------------------------------------------------------
locals {
  total_ocpus = length(local._ampere_nodes) > 0 ? sum([
    for n in local._ampere_nodes : n.ocpus
  ]) : 0

  total_ram_gb = length(local._ampere_nodes) > 0 ? sum([
    for n in local._ampere_nodes : n.memory_gb
  ]) : 0

  total_storage_gb = (
    (length(local._ampere_nodes) > 0 ? sum([for n in local._ampere_nodes : n.boot_vol_gb]) : 0) +
    (length(local._micro_nodes) > 0 ? sum([for n in local._micro_nodes : n.boot_vol_gb]) : 0) +
    (var.create_bastion ? var.bastion_boot_vol_gb : 0)
  )
}

# ---------------------------------------------------------------------------
# Image resolution
# ---------------------------------------------------------------------------

# Get latest Ubuntu 22.04 for Ampere A1 (ARM64)
data "oci_core_images" "ampere_images" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# Get latest Ubuntu 22.04 for E2.1.Micro (x86)
data "oci_core_images" "micro_images" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.E2.1.Micro"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

locals {
  subnet_id        = var.existing_subnet_ocid != null ? var.existing_subnet_ocid : oci_core_subnet.free_tier_subnet[0].id
  public_subnet_id = var.existing_subnet_ocid != null ? var.existing_subnet_ocid : oci_core_subnet.free_tier_public_subnet[0].id
  ampere_subnet_ids = [
    for n in local._ampere_nodes :
    n.vpn_subnet && local.vpn_enabled ? oci_core_subnet.vpn_subnet[0].id : local.subnet_id
  ]
}

locals {
  # If talos_image_ocid is set, boot Talos. If omni_ready is also true,
  # metadata below enrolls the node into Omni. Without talos_image_ocid,
  # use latest Ubuntu 22.04 from the data source.
  ampere_image_id = var.talos_image_ocid != null ? var.talos_image_ocid : data.oci_core_images.ampere_images.images[0].id
  # Prefer the pre-baked golden Micro image (base OS + hardening); falls back to
  # latest Ubuntu 24.04 marketplace image if not set.
  micro_image_id = var.micro_golden_image_ocid != null ? var.micro_golden_image_ocid : data.oci_core_images.micro_images.images[0].id
}

# ---------------------------------------------------------------------------
# Talos MachineConfig user_data
#
# Multi-document YAML consumed by Talos on first boot:
#   SideroLinkConfig  — connects node to Omni via WireGuard
#   ExtensionServiceConfig — starts Tailscale with the provided auth key
#
# Talos reads user_data from OCI instance metadata (base64-decoded).
# SideroLink is node-initiated: OCI node dials out → Omni, no inbound needed.
# ---------------------------------------------------------------------------
locals {
  # Null-safe wrappers used only inside _ampere_user_data to avoid string
  # interpolation errors when prerequisite variables are null.  The check
  # blocks in validation.tf will catch the missing-value case before apply.
  _omni_machine_config = var.omni_machine_config != null ? trimspace(var.omni_machine_config) : ""
  _tailscale_auth_key  = var.tailscale_auth_key != null ? var.tailscale_auth_key : ""

  _siderolink_user_data = var.omni_ready ? [local._omni_machine_config] : []

  _tailscale_user_data = var.tailscale_auth_key != null ? [
    "---",
    "apiVersion: v1alpha1",
    "kind: ExtensionServiceConfig",
    "name: tailscale",
    "environment:",
    "  - TS_AUTHKEY=${local._tailscale_auth_key}",
  ] : []

  _ampere_user_data_parts = concat(local._siderolink_user_data, local._tailscale_user_data)
  _ampere_user_data = length(local._ampere_user_data_parts) > 0 ? join("\n", concat(local._ampere_user_data_parts, [
    "",
  ])) : null

  # Combine the primary key with any extras (personal + syscode, etc.)
  _ssh_authorized_keys = compact(distinct(concat(
    var.ssh_public_key != null ? [var.ssh_public_key] : [],
    var.ssh_extra_public_keys,
  )))

  # Knock sequence as a comma-separated string for knockd.conf.
  _bastion_knock_sequence = join(",", [for p in var.bastion_knock_ports : "${p}:tcp"])

  # Bastion cloud-init: knockd + optional VPN probe runner.
  _bastion_user_data = base64encode(templatefile("${path.module}/files/cloud-init-bastion.yaml.tmpl", {
    ssh_public_key           = length(local._ssh_authorized_keys) > 0 ? local._ssh_authorized_keys[0] : ""
    extra_ssh_keys           = length(local._ssh_authorized_keys) > 1 ? slice(local._ssh_authorized_keys, 1, length(local._ssh_authorized_keys)) : []
    primary_nic              = "ens3"
    knock_sequence           = local._bastion_knock_sequence
    knock_timeout            = var.bastion_knock_timeout
    knock_ports              = var.bastion_knock_ports
    enable_vpn_probe         = local.vpn_enabled && var.enable_oci_vpn_probe
    omni_target_ip           = var.omni_target_ip
    enable_cpe_drift_check   = local.vpn_enabled
    cpe_recreate_function_id = local.vpn_enabled ? oci_functions_function.cpe_recreate[0].id : ""
  }))

  # Workload Micro cloud-init: Docker/Tailscale + SSH restricted to bastion.
  _micro_user_data = base64encode(templatefile("${path.module}/files/cloud-init-micro.yaml.tmpl", {
    ssh_public_key = length(local._ssh_authorized_keys) > 0 ? local._ssh_authorized_keys[0] : ""
    extra_ssh_keys = length(local._ssh_authorized_keys) > 1 ? slice(local._ssh_authorized_keys, 1, length(local._ssh_authorized_keys)) : []
    bastion_ip     = var.create_bastion ? oci_core_instance.bastion[0].private_ip : "0.0.0.0/0"
  }))
}
