/*
 * OCI → home OpenWrt Site-to-Site VPN (Always Free)
 *
 * Lets OCI Talos maintenance-mode nodes reach the tailnet-only Omni without
 * early Tailscale-in-Talos. See plan:
 *   syscode-ai-internal-plans/projects/omni-on-unraid/plans/
 *     2026-07-13-oci-openwrt-site-to-site-vpn.md
 *
 * Everything here is gated on var.enable_oci_vpn (default false) so it is
 * purely additive: an apply without the flag set creates nothing here and
 * leaves the VCN cidr_blocks and the two A1 capacity-holder instances alone.
 *
 * NON-DESTRUCTIVE CONTRACT (Task 4): the secondary CIDR is APPENDED to the
 * existing VCN's cidr_blocks list (AddVcnCidr = in-place update). It must never
 * renumber the primary 10.0.0.0/16 or the 10.0.1.0/24 subnet — that recreates
 * the Ampere instances. If `tofu plan` shows -/+ replace on the VCN, the
 * subnet, or any instance/VNIC, DO NOT APPLY.
 *
 * Handoff interface to the OpenWrt side (Piece B, Task 7) = the outputs at the
 * bottom of outputs.tf: tunnel public IPs + PSKs.
 */

locals {
  # Only ever create VPN resources when the module also manages the VCN.
  vpn_enabled = var.enable_oci_vpn && var.existing_subnet_ocid == null

  # OCI nodes need two scoped routes over the VPN:
  # - Omni's advertised tailnet /32 for SideroLink.
  # - OpenWrt resolver /32 when custom DHCP DNS is enabled.
  vpn_static_route_cidrs = distinct(compact([
    "${var.omni_target_ip}/32",
    var.openwrt_resolver_ip != null ? "${var.openwrt_resolver_ip}/32" : null,
  ]))
}

# ---------------------------------------------------------------------------
# Task 4: new subnet inside the appended secondary CIDR block.
# (The cidr_blocks append itself lives on oci_core_vcn.free_tier_vcn in main.tf.)
# ---------------------------------------------------------------------------
resource "oci_core_subnet" "vpn_subnet" {
  count             = local.vpn_enabled ? 1 : 0
  compartment_id    = local.compartment_id
  vcn_id            = oci_core_vcn.free_tier_vcn[0].id
  cidr_block        = var.vpn_subnet_cidr
  display_name      = "oci-vpn-subnet"
  dns_label         = "vpnsubnet"
  route_table_id    = oci_core_route_table.vpn_route_table[0].id
  security_list_ids = [oci_core_security_list.vpn_security_list[0].id]
  # Custom resolver (Task 0) only when the OpenWrt resolver IP is known;
  # otherwise the subnet inherits the VCN default DHCP options.
  dhcp_options_id = var.openwrt_resolver_ip != null ? oci_core_dhcp_options.vpn_resolver[0].id : null
}

# Route Omni's /32 into the DRG. Scoped to the single target per plan guardrail
# ("route only Omni /32", never 0.0.0.0/0 and never the home LAN).
resource "oci_core_route_table" "vpn_route_table" {
  count          = local.vpn_enabled ? 1 : 0
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.free_tier_vcn[0].id
  display_name   = "oci-vpn-route-table"

  dynamic "route_rules" {
    for_each = local.vpn_static_route_cidrs

    content {
      destination       = route_rules.value
      destination_type  = "CIDR_BLOCK"
      network_entity_id = oci_core_drg.vpn_drg[0].id
      description       = "Scoped home VPN target"
    }
  }
}

# Egress scoped to the Omni target ports only; ingress scoped to the Omni /32.
# Security lists are stateful, so egress replies return without an ingress rule.
resource "oci_core_security_list" "vpn_security_list" {
  count          = local.vpn_enabled ? 1 : 0
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.free_tier_vcn[0].id
  display_name   = "oci-vpn-security-list"

  # Egress: Omni machine API
  egress_security_rules {
    protocol    = "6" # TCP
    destination = "${var.omni_target_ip}/32"
    tcp_options {
      min = var.omni_api_port
      max = var.omni_api_port
    }
  }

  # Egress: Omni SideroLink WireGuard
  egress_security_rules {
    protocol    = "17" # UDP
    destination = "${var.omni_target_ip}/32"
    udp_options {
      min = var.omni_wireguard_port
      max = var.omni_wireguard_port
    }
  }

  # Egress: DNS to the OpenWrt resolver over the VPN (Task 0). Falls back to the
  # Omni /32 when no dedicated resolver IP is set so the rule stays scoped.
  egress_security_rules {
    protocol    = "17" # UDP
    destination = "${var.openwrt_resolver_ip != null ? var.openwrt_resolver_ip : var.omni_target_ip}/32"
    udp_options {
      min = 53
      max = 53
    }
  }

  # Egress: intra-VPN-subnet (node-to-node within the VPN subnet)
  egress_security_rules {
    protocol    = "all"
    destination = var.vpn_subnet_cidr
  }

  # Ingress: allow Omni to reach the nodes over the tunnel (management path),
  # scoped to the single Omni /32.
  ingress_security_rules {
    protocol = "all"
    source   = "${var.omni_target_ip}/32"
  }

  # Ingress: intra-VPN-subnet
  ingress_security_rules {
    protocol = "all"
    source   = var.vpn_subnet_cidr
  }
}

# ---------------------------------------------------------------------------
# Task 0: OCI VCN DHCP Options → OpenWrt resolver.
# Created only once the resolver IP (a Piece B / OpenWrt value) is provided.
# Keeps the advertised FQDN (omni.wind-bearded.ts.net) so TLS still validates.
# ---------------------------------------------------------------------------
resource "oci_core_dhcp_options" "vpn_resolver" {
  count          = local.vpn_enabled && var.openwrt_resolver_ip != null ? 1 : 0
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.free_tier_vcn[0].id
  display_name   = "oci-vpn-dhcp-resolver"

  options {
    type               = "DomainNameServer"
    server_type        = "CustomDnsServer"
    custom_dns_servers = [var.openwrt_resolver_ip]
  }

  options {
    type                = "SearchDomain"
    search_domain_names = [var.omni_search_domain]
  }
}

# ---------------------------------------------------------------------------
# Task 5: DRG + CPE + IPSec (Site-to-Site VPN). All Always Free.
# ---------------------------------------------------------------------------
resource "oci_core_drg" "vpn_drg" {
  count          = local.vpn_enabled ? 1 : 0
  compartment_id = local.compartment_id
  display_name   = "oci-vpn-drg"
}

resource "oci_core_drg_attachment" "vpn_vcn_attach" {
  count        = local.vpn_enabled ? 1 : 0
  drg_id       = oci_core_drg.vpn_drg[0].id
  vcn_id       = oci_core_vcn.free_tier_vcn[0].id
  display_name = "oci-vpn-vcn-attach"
}

# Customer Premises Equipment = the home OpenWrt public egress IP.
resource "oci_core_cpe" "home_cpe" {
  count          = local.vpn_enabled ? 1 : 0
  compartment_id = local.compartment_id
  ip_address     = var.home_cpe_public_ip
  display_name   = "home-openwrt-cpe"
}

# IPSec connection — OCI auto-creates two redundant tunnels.
# static_routes = the on-prem prefix OCI routes into the tunnel (the Omni /32).
resource "oci_core_ipsec" "home_ipsec" {
  count          = local.vpn_enabled ? 1 : 0
  compartment_id = local.compartment_id
  cpe_id         = oci_core_cpe.home_cpe[0].id
  drg_id         = oci_core_drg.vpn_drg[0].id
  display_name   = "home-openwrt-ipsec"
  static_routes  = local.vpn_static_route_cidrs

  # CPE is behind NAT (WAN 10.10.100.108, public egress 45.148.13.185); the local
  # IKE identifier is the private WAN IP, not the public IP (see plan Q5).
  cpe_local_identifier      = var.cpe_local_identifier
  cpe_local_identifier_type = "IP_ADDRESS"
}

# Read the two auto-created tunnels so we can manage each and export their
# public IPs / PSKs. Deferred to apply time (depends on the ipsec resource).
data "oci_core_ipsec_connection_tunnels" "home" {
  count    = local.vpn_enabled ? 1 : 0
  ipsec_id = oci_core_ipsec.home_ipsec[0].id
}

# Force STATIC routing (route-based) on both tunnels. OCI route-based tunnels
# negotiate 0.0.0.0/0 selectors and scope via routing — the OpenWrt side uses
# XFRM if_id + firewall to scope to Omni (Task 6/7), not narrow traffic selectors.
resource "oci_core_ipsec_connection_tunnel_management" "home" {
  count        = local.vpn_enabled ? 2 : 0
  ipsec_id     = oci_core_ipsec.home_ipsec[0].id
  tunnel_id    = data.oci_core_ipsec_connection_tunnels.home[0].ip_sec_connection_tunnels[count.index].id
  routing      = "STATIC"
  ike_version  = "V2"
  display_name = "home-tunnel-${count.index + 1}"
}
