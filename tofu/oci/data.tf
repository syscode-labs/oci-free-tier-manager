/*
 * Data sources for retrieving OCI information
 */

# Get availability domains
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# Get latest Ubuntu image for Ampere A1 (ARM64)
data "oci_core_images" "ampere_images" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# Get latest Oracle Linux image for E2.1.Micro (x86_64)
data "oci_core_images" "micro_images" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = "VM.Standard.E2.1.Micro"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# Resolve which image to use for Ampere instances:
# - If proxmox_image_ocid is set: use the custom Proxmox image
# - Otherwise: fall back to the platform Ubuntu image (development/testing)
locals {
  ampere_image_id = var.proxmox_image_ocid != "" ? var.proxmox_image_ocid : data.oci_core_images.ampere_images.images[0].id
}
