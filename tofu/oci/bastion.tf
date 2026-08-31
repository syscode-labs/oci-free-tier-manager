/*
 * Self-managed bastion host
 *
 * Replaces the standalone oci-vpn-probe Micro instance. The bastion lives in a
 * dedicated public subnet (IGW route table), exposes a reserved public IP, and
 * uses knockd to open SSH only for the IP that completes the configured port
 * sequence.
 *
 * The public subnet routes selected home targets through the DRG, so this
 * single-VNIC Micro bastion can run VPN probe tests through the IPSec tunnel.
 */

# ---------------------------------------------------------------------------
# Bastion compute instance
# ---------------------------------------------------------------------------
resource "oci_identity_tag_namespace" "cpe_remediator" {
  count          = var.create_bastion ? 1 : 0
  compartment_id = var.tenancy_ocid
  name           = "cpe_remediator"
  description    = "Stable identity tag namespace for the CPE remediator bastion"
}

resource "oci_identity_tag" "cpe_remediator_role" {
  count            = var.create_bastion ? 1 : 0
  tag_namespace_id = oci_identity_tag_namespace.cpe_remediator[0].id
  name             = "bastion_role"
  description      = "Marks the bastion eligible to read the staged CPE remediator artifact"
}

resource "oci_core_instance" "bastion" {
  count               = var.create_bastion ? 1 : 0
  availability_domain = var.micro_availability_domain
  compartment_id      = local.compartment_id
  display_name        = var.bastion_name
  shape               = "VM.Standard.E2.1.Micro"
  # The replacement must not boot the local executor until its policy is live.
  # OCI applies policy changes before dependent instances, while the installer
  # retries artifact reads to absorb post-apply IAM propagation delay.
  depends_on = [
    oci_objectstorage_object.cpe_remediator,
    oci_identity_tag.cpe_remediator_role,
    oci_identity_policy.cpe_drift_check_bastion,
  ]

  source_details {
    source_type             = "image"
    source_id               = local.micro_image_id
    boot_volume_size_in_gbs = var.bastion_boot_vol_gb
  }

  create_vnic_details {
    subnet_id        = local.public_subnet_id
    assign_public_ip = false # reserved IP attached explicitly below
    display_name     = "${var.bastion_name}-vnic"
  }

  metadata = {
    user_data           = local._bastion_user_data
    ssh_authorized_keys = join("\n", local._ssh_authorized_keys)
  }

  defined_tags = {
    "cpe_remediator.bastion_role" = "true"
  }

  lifecycle {
    # Cloud-init runs only on first boot. Replace on either staged-artifact or
    # executor-state changes; the reserved IP remains a separate resource.
    replace_triggered_by = [terraform_data.cpe_remediator_artifact]

    ignore_changes = [
      availability_domain,
      shape_config,
    ]
  }
}

# Reserved public IP for the bastion — stable endpoint for SSH.
resource "oci_core_public_ip" "bastion" {
  count          = var.create_bastion ? 1 : 0
  compartment_id = local.compartment_id
  lifetime       = "RESERVED"
  display_name   = "${var.bastion_name}-ip"
  private_ip_id  = data.oci_core_private_ips.bastion_private_ip[0].private_ips[0].id
}

# Resolved by instance ID (via its VNIC), not subnet+address — see the ampere
# instance's equivalent data source in main.tf for why.
data "oci_core_vnic_attachments" "bastion" {
  count          = var.create_bastion ? 1 : 0
  compartment_id = local.compartment_id
  instance_id    = oci_core_instance.bastion[0].id
}

data "oci_core_private_ips" "bastion_private_ip" {
  count   = var.create_bastion ? 1 : 0
  vnic_id = data.oci_core_vnic_attachments.bastion[0].vnic_attachments[0].vnic_id
}
