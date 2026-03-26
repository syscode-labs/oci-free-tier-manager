# tofu/oci/variables.tf
/*
 * Input variables for OCI Free Tier configuration
 *
 * Both Always Free and PAYG accounts offer the same free compute resources:
 * ┌─────────────────────┬──────────────────────┬────────────────────────┐
 * │ Resource            │ Always Free account  │ PAYG account           │
 * ├─────────────────────┼──────────────────────┼────────────────────────┤
 * │ A1.Flex OCPUs       │ 4 total, integer only│ 4 total, integer only  │
 * │ A1.Flex RAM         │ 24 GB total          │ 24 GB total            │
 * │ E2.1.Micro          │ Up to 2 instances    │ Up to 2 instances      │
 * │ Block Storage       │ 200 GB total         │ 200 GB total           │
 * └─────────────────────┴──────────────────────┴────────────────────────┘
 *
 * The account type is auto-detected via the standard-a1-core-count service limit:
 *   ≤ 4  → Always Free account (hard cap — cannot add paid OCPUs)
 *   > 4  → PAYG account (same free tier, but can exceed limits for a fee)
 *
 * All node/LB fields are optional — omit any field to use defaults:
 *   3 × A1.Flex (1 OCPU / 8 GB / 50 GB) + 1 × Micro (50 GB)
 *
 * Override examples:
 *
 *   # 3 equal nodes (default)
 *   ampere_nodes = [{}, {}, {}]
 *
 *   # 4 equal nodes, maxes out 4 OCPUs / 24 GB RAM
 *   ampere_nodes = [{}, {}, {}, {}]
 *
 *   # Mixed sizes (must stay within 4 OCPUs / 24 GB / 200 GB total)
 *   ampere_nodes = [
 *     { name = "k8s-cp", ocpus = 2, memory_gb = 12, boot_vol_gb = 60 },
 *     { name = "k8s-w1", ocpus = 2, memory_gb = 12, boot_vol_gb = 60 },
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
  description = "OCID of the Talos+Tailscale Image Factory image imported into OCI. Required when omni_ready = true. Create at factory.talos.dev (ARM64, add Tailscale extension), import with scripts/oci-import.sh, store OCID as GitHub variable TALOS_IMAGE_OCID."
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
#   tailscale_auth_key — Reusable/ephemeral auth key from Tailscale admin with tag:oci
#
# When omni_ready = false (default), Ampere instances use Ubuntu 22.04.
# ---------------------------------------------------------------------------
variable "omni_ready" {
  description = "When true, provision Talos+Omni nodes instead of Ubuntu. Requires talos_image_ocid, omni_endpoint, omni_join_token, tailscale_auth_key."
  type        = bool
  default     = false
}

variable "omni_endpoint" {
  description = "Omni gRPC endpoint for SideroLink, e.g. omni.example.com:8090. Required when omni_ready = true."
  type        = string
  default     = null
}

variable "omni_join_token" {
  description = "Static SideroLink join token. Get from: omnictl get connections -o yaml | grep joinToken. Required when omni_ready = true. Store as GitHub secret OMNI_JOIN_TOKEN."
  type        = string
  sensitive   = true
  default     = null
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key for the Tailscale system extension on Talos nodes. Must have tag:oci applied. Required when omni_ready = true. Store as GitHub secret TAILSCALE_AUTH_KEY."
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
  description = "Create a reserved public IP for the Kubernetes ingress controller. Set to false for non-k8s deployments to avoid consuming reserved IP quota."
  type        = bool
  default     = true
}

variable "ssh_public_key" {
  description = "SSH public key injected via metadata for all instances in Ubuntu mode (omni_ready = false). Talos ignores SSH keys."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Ampere A1.Flex nodes (ARM64)
#
# Each entry in the list becomes one VM.Standard.A1.Flex instance.
# All fields are optional; omitted fields default to:
#   ocpus=1, memory_gb=8, boot_vol_gb=50  (same for all account types)
#
# Note: OCPUs must be integers (1, 2, 3, or 4) — the OCI API enforces
#       integer-only values on all account types (min=1, step=1).
#
# Budgets (enforced by check blocks in validation.tf):
#   Total OCPUs     ≤ 4
#   Total RAM       ≤ 24 GB
#   Total storage   ≤ 200 GB (ampere + micro boot volumes combined)
# ---------------------------------------------------------------------------
variable "ampere_nodes" {
  description = "Ampere A1.Flex node configurations. null = use defaults (3 nodes, 1 OCPU / 8 GB / 50 GB each)."
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
# If null (default), 1 micro node is created automatically.
# Set to [] to suppress micro nodes entirely.
#
# Each E2.1.Micro instance has: 1/8 OCPU, 1 GB RAM (fixed, not configurable).
# ---------------------------------------------------------------------------
variable "micro_nodes" {
  description = "E2.1.Micro node configurations. null = 1 node (default). [] = no micro nodes."
  type = list(object({
    boot_vol_gb = optional(number)
    name        = optional(string)
  }))
  default = null
}

# ---------------------------------------------------------------------------
# Load Balancer
#
# OCI provides 1 × 10 Mbps flexible LB at no cost (Always Free marker on both
# account types). null = no LB created. {} = create with free-tier defaults.
#
# To use this LB as the Kubernetes ingress LoadBalancer, annotate your Service:
#   service.beta.kubernetes.io/oci-load-balancer-shape: "10Mbps"
# Without that annotation, OCI CCM defaults to a paid flexible shape.
# ---------------------------------------------------------------------------
variable "existing_subnet_ocid" {
  description = "If set, skip VCN/networking creation and attach all instances to this existing subnet."
  type        = string
  default     = null
}

variable "load_balancer" {
  description = "Load balancer configuration. null = no LB created. {} = free-tier 10 Mbps LB. Defaults to the free 10 Mbps LB."
  type = object({
    shape          = optional(string, "flexible")
    bandwidth_mbps = optional(number, 10)
  })
  default = {}
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
