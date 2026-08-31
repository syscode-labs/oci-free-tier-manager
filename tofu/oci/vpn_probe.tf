/*
 * VPN probe control
 *
 * Historically this created a standalone Micro instance in the VPN subnet.
 * That role is now performed by the self-managed bastion via a secondary VNIC
 * (see bastion.tf). This file only retains the enablement flag used by the
 * VPN subnet security list to allow test traffic from the bastion's VPN VNIC.
 */

locals {
  vpn_probe_enabled = local.vpn_enabled && var.enable_oci_vpn_probe
}
