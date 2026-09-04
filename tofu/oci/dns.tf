/*
 * Public DNS for the bastion is hosted in the existing Cloudflare syscode.uk
 * zone. The record is DNS-only because Cloudflare's HTTP proxy cannot carry
 * SSH or port-knocking traffic.
 */

resource "cloudflare_dns_record" "bastion" {
  count   = var.create_bastion ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "bastion.syscode-lab.oci.syscode.uk"
  type    = "A"
  content = oci_core_public_ip.bastion[0].ip_address
  ttl     = 300
  proxied = false
}
