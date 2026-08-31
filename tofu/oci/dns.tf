/*
 * OCI Public DNS — delegated subdomain syscode-lab.oci.syscode.uk.
 *
 * syscode.uk itself is NOT managed here (lives in whatever DNS provider
 * already hosts it, e.g. Cloudflare). This zone owns everything under
 * syscode-lab.oci.syscode.uk once the parent adds a single NS delegation
 * record pointing at oci_dns_zone.lab.nameservers (see the output below).
 *
 * Gives Terraform-managed, memorable hostnames for OCI resources that only
 * had a bare reserved IP before (e.g. bastion.syscode-lab.oci.syscode.uk),
 * instead of "look up the reserved IP output every time."
 */

resource "oci_dns_zone" "lab" {
  count          = var.create_bastion ? 1 : 0
  compartment_id = local.compartment_id
  name           = "syscode-lab.oci.syscode.uk"
  zone_type      = "PRIMARY"
}

resource "oci_dns_rrset" "bastion" {
  count           = var.create_bastion ? 1 : 0
  zone_name_or_id = oci_dns_zone.lab[0].id
  domain          = "bastion.syscode-lab.oci.syscode.uk"
  rtype           = "A"

  items {
    domain = "bastion.syscode-lab.oci.syscode.uk"
    rtype  = "A"
    ttl    = 300
    rdata  = oci_core_public_ip.bastion[0].ip_address
  }
}
