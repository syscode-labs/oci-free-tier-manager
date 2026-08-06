/*
 * Self-managed bastion host
 *
 * Replaces the standalone oci-vpn-probe Micro instance. The bastion lives in a
 * dedicated public subnet (IGW route table), exposes a reserved public IP, and
 * uses knockd to open SSH only for the IP that completes the configured port
 * sequence.
 *
 * When enable_oci_vpn_probe=true, a secondary VNIC is attached to the VPN subnet
 * so the bastion can run the VPN probe tests through the IPSec tunnel.
 */

# ---------------------------------------------------------------------------
# Bastion compute instance
# ---------------------------------------------------------------------------
resource "oci_core_instance" "bastion" {
  count               = var.create_bastion ? 1 : 0
  availability_domain = var.micro_availability_domain
  compartment_id      = local.compartment_id
  display_name        = var.bastion_name
  shape               = "VM.Standard.E2.1.Micro"

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

  lifecycle {
    create_before_destroy = true
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

# ---------------------------------------------------------------------------
# Secondary VNIC in the VPN subnet for probe/testing
# ---------------------------------------------------------------------------
resource "oci_core_vnic_attachment" "bastion_vpn_vnic" {
  count        = var.create_bastion && local.vpn_enabled && var.enable_oci_vpn_probe ? 1 : 0
  instance_id  = oci_core_instance.bastion[0].id
  display_name = "${var.bastion_name}-vpn-vnic"
  nic_index    = 1

  create_vnic_details {
    subnet_id        = oci_core_subnet.vpn_subnet[0].id
    assign_public_ip = false
    display_name     = "${var.bastion_name}-vpn-vnic"
  }
}

# Lookup the secondary VNIC and its private IP so outputs can expose it.
data "oci_core_vnic" "bastion_vpn_vnic" {
  count   = var.create_bastion && local.vpn_enabled && var.enable_oci_vpn_probe ? 1 : 0
  vnic_id = oci_core_vnic_attachment.bastion_vpn_vnic[0].vnic_id
}

data "oci_core_private_ips" "bastion_vpn_private_ip" {
  count      = var.create_bastion && local.vpn_enabled && var.enable_oci_vpn_probe ? 1 : 0
  subnet_id  = oci_core_subnet.vpn_subnet[0].id
  ip_address = data.oci_core_vnic.bastion_vpn_vnic[0].private_ip_address
}
