# tofu/oci/variables.tf
/*
 * Input variables for OCI Free Tier configuration
 *
 * Both Always Free and PAYG accounts offer the same free compute resources:
 * ┌─────────────────────┬──────────────────────┬────────────────────────┐
 * │ Resource            │ Always Free account  │ PAYG account           │
 * ├─────────────────────┼──────────────────────┼────────────────────────┤
 * │ A1.Flex instances   │ Up to 2              │ Up to 2 free           │
 * │ A1.Flex OCPUs       │ 2 total, integer only│ 2 total free           │
 * │ A1.Flex RAM         │ 12 GB total          │ 12 GB total free       │
 * │ E2.1.Micro          │ Up to 2 instances    │ Up to 2 instances      │
 * │ Block Storage       │ 200 GB total         │ 200 GB total           │
 * └─────────────────────┴──────────────────────┴────────────────────────┘
 *
 * The account type is auto-detected via the standard-a1-core-count service limit:
 *   ≤ 2  → Always Free account (hard cap — cannot add paid OCPUs)
 *   > 2  → PAYG account (same free tier, but can exceed limits for a fee)
 *
 * All node/LB fields are optional — omit any field to use defaults:
 *   2 x A1.Flex (1 OCPU / 6 GB / 50 GB); E2.1.Micro is opt-in
 *
 * Override examples:
 *
 *   # 2 equal nodes (default, maxes out 2 OCPUs / 12 GB RAM)
 *   ampere_nodes = [{}, {}]
 *
 *   # Mixed sizes (must stay within 2 instances / 2 OCPUs / 12 GB / 200 GB total)
 *   ampere_nodes = [
 *     { name = "k8s-cp", ocpus = 1, memory_gb = 6, boot_vol_gb = 60 },
 *     { name = "k8s-w1", ocpus = 1, memory_gb = 6, boot_vol_gb = 60 },
 *   ]
 *
 *   # Explicit bastion (available on all account types)
 *   micro_nodes = [{ name = "bastion", boot_vol_gb = 47 }]
 *
 *   # Free 10 Mbps load balancer
 *   load_balancer = {}
 */

# OCI Authentication
# Uses a named profile from ~/.oci/config. Run `oci setup config` to configure.

variable "oci_config_profile" {
  description = "OCI CLI config profile name from ~/.oci/config"
  type        = string
  default     = "DEFAULT"
}

variable "region" {
  description = "OCI region"
  type        = string
  default     = "uk-london-1"
}

variable "availability_domain" {
  description = "Availability domain for Ampere A1 instances"
  type        = string
  default     = "EGzq:UK-LONDON-1-AD-1"
}

variable "micro_availability_domain" {
  description = "Availability domain for E2.1.Micro instances (may differ from Ampere AD due to quota allocation)"
  type        = string
  default     = "EGzq:UK-LONDON-1-AD-3"
}

variable "tenancy_ocid" {
  description = "OCID of the tenancy root compartment — required for budget creation"
  type        = string
}

variable "compartment_ocid" {
  description = "OCID of the compartment (required — cannot be auto-detected)"
  type        = string
}


variable "talos_image_ocid" {
  description = "OCID of the Talos Image Factory image imported into OCI. When set, Ampere nodes boot Talos. The image must include Tailscale when tailscale_auth_key or omni_ready is set."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Omni-ready mode
#
# When omni_ready = true, Ampere instances boot Talos and auto-enroll into
# your Omni instance via SideroLink over Tailscale. Requires:
#   talos_image_ocid  — Talos+Tailscale image OCID (import once, store in GitHub vars)
#   omni_endpoint     — Omni gRPC host:port (e.g. omni.example.com:8090)
#   omni_join_token   — Static join token from: omnictl get connections -o yaml
#   tailscale_auth_key — Reusable Tailscale auth key from NODES_TAILSCALE_AUTHKEY with tag:talos
#
# When omni_ready = false (default), Ampere instances use Ubuntu 22.04 unless
# talos_image_ocid is set. tailscale_auth_key can be set without omni_ready to
# put bare Talos nodes into the tailnet without enrolling them in Omni.
# ---------------------------------------------------------------------------
variable "omni_ready" {
  description = "When true, provision Talos+Omni nodes instead of Ubuntu. Requires talos_image_ocid, omni_endpoint, omni_join_token, tailscale_auth_key."
  type        = bool
  default     = false
}

variable "omni_endpoint" {
  description = "Omni endpoint base URL for SideroLink, e.g. https://omni.example.ts.net or omni.example.com:8090. Required when omni_ready = true."
  type        = string
  default     = null
}

variable "omni_join_token" {
  description = "Static SideroLink join token. Get from: omnictl jointoken omni-endpoint. Required when omni_ready = true. Store as GitHub secret OMNI_JOIN_TOKEN."
  type        = string
  sensitive   = true
  default     = null
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key for the Tailscale system extension on Talos nodes. Must be reusable and have tag:talos applied. Required when omni_ready = true. Store as GitHub secret NODES_TAILSCALE_AUTHKEY."
  type        = string
  sensitive   = true
  default     = null
}

variable "budget_alert_email" {
  description = "Email address for budget alerts (comma-separated for multiple). Required when create_budget = true."
  type        = string
  default     = null
}

variable "create_budget" {
  description = "Create the OCI budget and alert rule. Requires the configured OCI profile to have tenancy-level IAM permissions for the Budget service."
  type        = bool
  default     = true
}

variable "create_ingress_ip" {
  description = "Create a reserved public IP for the Kubernetes ingress controller. Set true only when a Kubernetes ingress reserved IP is required."
  type        = bool
  default     = false
}

variable "ssh_public_key" {
  description = "SSH public key injected via metadata for all instances in Ubuntu mode. Talos ignores SSH keys."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Ampere A1.Flex nodes (ARM64)
#
# Each entry in the list becomes one VM.Standard.A1.Flex instance.
# All fields are optional; omitted fields default to:
#   ocpus=1, memory_gb=6, boot_vol_gb=50  (same for all account types)
#
# Note: OCPUs must be integers (1, 2, 3, or 4) — the OCI API enforces
#       integer-only values on all account types (min=1, step=1).
#
# Budgets (enforced by check blocks in validation.tf):
#   Total instances ≤ 2
#   Total OCPUs     ≤ 2
#   Total RAM       ≤ 12 GB
#   Total storage   ≤ 200 GB (ampere + micro boot volumes combined)
# ---------------------------------------------------------------------------
variable "ampere_nodes" {
  description = "Ampere A1.Flex node configurations. null = use defaults (2 nodes, 1 OCPU / 6 GB / 50 GB each)."
  type = list(object({
    ocpus       = optional(number)
    memory_gb   = optional(number)
    boot_vol_gb = optional(number)
    name        = optional(string)
  }))
  default = null
}

# ---------------------------------------------------------------------------
# E2.1.Micro nodes (x86, AMD)
#
# Available on all OCI account types (up to 2 free instances).
# If null (default), no micro nodes are created.
# Set to a non-empty list to create E2.1.Micro instances explicitly.
#
# Each E2.1.Micro instance has: 1/8 OCPU, 1 GB RAM (fixed, not configurable).
# ---------------------------------------------------------------------------
variable "micro_nodes" {
  description = "E2.1.Micro node configurations. null or [] = no micro nodes; set a non-empty list to create them."
  type = list(object({
    boot_vol_gb = optional(number)
    name        = optional(string)
  }))
  default = null
}

# ---------------------------------------------------------------------------
# Load Balancer
#
# OCI provides 1 × flexible LB at 10/10 Mbps at no cost (Always Free).
# null = no LB created. {} = create with free-tier defaults (10/10 Mbps).
#
# If OCI CCM is ever installed and creates LBs from K8s Services, annotate
# every LoadBalancer Service to stay within the free tier:
#
#   service.beta.kubernetes.io/oci-load-balancer-shape: "flexible"
#   service.beta.kubernetes.io/oci-load-balancer-shape-flex-min: "10"
#   service.beta.kubernetes.io/oci-load-balancer-shape-flex-max: "10"
#
# Alternatively, set these defaults in the CCM cloud-config so all Services
# inherit them without per-Service annotations:
#
#   loadBalancer:
#     shape: "flexible"
#     flexShapeMinMbps: 10
#     flexShapeMaxMbps: 10
#
# Without these settings, OCI CCM creates flexible LBs at 10/100 Mbps by
# default — the 100 Mbps maximum triggers paid billing.
# ---------------------------------------------------------------------------
variable "existing_subnet_ocid" {
  description = "If set, skip VCN/networking creation and attach all instances to this existing subnet."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# OCI → home OpenWrt Site-to-Site VPN (Always Free) — see vpn.tf.
# Master toggle; all VPN resources are gated on it so the module stays additive.
# ---------------------------------------------------------------------------
variable "enable_oci_vpn" {
  description = "Create the OCI→home Site-to-Site VPN (DRG/CPE/IPSec) + secondary CIDR + VPN subnet. Additive; leaves the primary VCN CIDR and Ampere instances untouched."
  type        = bool
  default     = false
}

variable "vpn_vcn_secondary_cidr" {
  description = "Secondary CIDR block appended to the existing VCN for VPN-reachable nodes. Clear of home LAN, tailnet, and Docker pools."
  type        = string
  default     = "10.44.0.0/16"
}

variable "vpn_subnet_cidr" {
  description = "Subnet inside the secondary CIDR for VPN-reachable Talos nodes."
  type        = string
  default     = "10.44.1.0/24"
}

variable "home_cpe_public_ip" {
  description = "Public egress IP of the home OpenWrt router (the CPE)."
  type        = string
  default     = "45.148.13.185"
}

variable "cpe_local_identifier" {
  description = "IKE local identifier for the CPE. OpenWrt is behind NAT, so this is its private WAN IP, not the public IP (see plan Q5)."
  type        = string
  default     = "10.10.100.108"
}

variable "omni_target_ip" {
  description = "Omni endpoint reachable over the VPN. Tailnet /32, routed via OpenWrt tailscale0. Only this /32 is routed into the tunnel."
  type        = string
  default     = "100.72.134.50"
}

variable "omni_api_port" {
  description = "Omni machine API TCP port."
  type        = number
  default     = 8090
}

variable "omni_wireguard_port" {
  description = "Omni SideroLink WireGuard UDP port."
  type        = number
  default     = 50180
}

variable "openwrt_resolver_ip" {
  description = "OpenWrt tunnel-reachable DNS resolver IP for OCI nodes (Task 0). Piece B / OpenWrt value; when null the VPN subnet inherits the VCN default DHCP options."
  type        = string
  default     = null
}

variable "omni_search_domain" {
  description = "DNS search domain pushed to VPN-subnet nodes so the advertised Omni FQDN resolves (keeps TLS valid)."
  type        = string
  default     = "wind-bearded.ts.net"
}

variable "enable_oci_vpn_probe" {
  description = "Create a temporary Ubuntu E2.1.Micro probe in the VPN subnet to verify DNS/API/UDP reachability to Omni. Use targeted apply/destroy only."
  type        = bool
  default     = false
}

variable "load_balancer" {
  description = "Load balancer configuration. null = no LB (default). {} = free-tier 10/10 Mbps flexible LB."
  type = object({
    shape          = optional(string, "flexible")
    bandwidth_mbps = optional(number, 10)
  })
  default = null
}

# ---------------------------------------------------------------------------
# Compartment and IAM (optional)
#
# When create_compartment = true, the module creates:
#   - A child compartment under the tenancy root
#   - An IAM group + user with a policy scoped to that compartment
#   - Optionally an API key if iam_api_public_key is provided
#
# All module resources are placed in the new compartment automatically.
# var.compartment_ocid is ignored when create_compartment = true.
# ---------------------------------------------------------------------------
variable "create_compartment" {
  description = "Create a dedicated child compartment for all free-tier resources. Requires tenancy-level IAM. When true, compartment_name is required."
  type        = bool
  default     = false
}

variable "compartment_name" {
  description = "Name for the new compartment. Required when create_compartment = true."
  type        = string
  default     = null
}

variable "iam_api_public_key" {
  description = "PEM-encoded RSA public key to register as an API key for the new IAM user. Optional — when null, the user is created but no API key is registered (you can add one manually). Only used when create_compartment = true."
  type        = string
  sensitive   = true
  default     = null
}
