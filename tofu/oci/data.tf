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
# This module enforces OCI free-tier limits regardless of account type:
#   3 × A1.Flex (1 OCPU / 8 GB / 50 GB) + 1 × Micro (50 GB)
#   Total: 3 OCPUs, 24 GB RAM, 200 GB storage
#
# OCPUs are integer-only (API min=1, step=1).
# ---------------------------------------------------------------------------
locals {
  _tier_defaults = {
    ampere_ocpus       = 1
    ampere_memory_gb   = 8
    ampere_boot_vol_gb = 50
    ampere_count       = 3
    micro_count        = 1
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
    }
  ]

  _ampere_nodes = var.ampere_nodes != null ? [
    for i, n in var.ampere_nodes : {
      ocpus       = n.ocpus != null ? n.ocpus : local._tier_defaults.ampere_ocpus
      memory_gb   = n.memory_gb != null ? n.memory_gb : local._tier_defaults.ampere_memory_gb
      boot_vol_gb = n.boot_vol_gb != null ? n.boot_vol_gb : local._tier_defaults.ampere_boot_vol_gb
      name        = n.name != null ? n.name : "ampere-instance-${i + 1}"
    }
  ] : local._default_ampere_nodes
}

# ---------------------------------------------------------------------------
# Resolved Micro node list
#
# If micro_nodes is null, generate 1 default micro node.
# If micro_nodes is set (including []), use that list as-is.
# ---------------------------------------------------------------------------
locals {
  _default_micro_nodes = [
    for i in range(local._tier_defaults.micro_count) : {
      boot_vol_gb = local._tier_defaults.micro_boot_vol_gb
      name        = "micro-instance-${i + 1}"
    }
  ]

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
    (length(local._micro_nodes) > 0 ? sum([for n in local._micro_nodes : n.boot_vol_gb]) : 0)
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
  operating_system_version = "22.04"
  shape                    = "VM.Standard.E2.1.Micro"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

locals {
  # When omni_ready = true: use the imported Talos+Tailscale image.
  # When omni_ready = false: use latest Ubuntu 22.04 from the data source.
  ampere_image_id = var.omni_ready ? var.talos_image_ocid : data.oci_core_images.ampere_images.images[0].id
  micro_image_id  = data.oci_core_images.micro_images.images[0].id
}

# ---------------------------------------------------------------------------
# Talos MachineConfig user_data (omni_ready = true only)
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
  _omni_endpoint      = var.omni_endpoint != null ? var.omni_endpoint : ""
  _omni_join_token    = var.omni_join_token != null ? var.omni_join_token : ""
  _tailscale_auth_key = var.tailscale_auth_key != null ? var.tailscale_auth_key : ""

  _ampere_user_data = var.omni_ready ? join("\n", [
    "---",
    "apiVersion: v1alpha1",
    "kind: SideroLinkConfig",
    "apiUrl: \"grpc://${local._omni_endpoint}?jointoken=${local._omni_join_token}\"",
    "---",
    "apiVersion: v1alpha1",
    "kind: ExtensionServiceConfig",
    "name: tailscale",
    "environment:",
    "  - TS_AUTHKEY=${local._tailscale_auth_key}",
    "",
  ]) : null
}
