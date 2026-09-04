/*
 * OCI Free Tier Infrastructure
 *
 * This Terraform configuration provisions resources within Oracle Cloud Infrastructure's
 * Always Free tier limits. It includes:
 * - VCN and networking components
 * - Ampere A1 compute instances (up to 2 instances, 2 OCPUs, 12GB RAM total)
 * - AMD E2.1.Micro instances (up to 2 instances, Always Free accounts only)
 * - Block storage (up to 200GB total including boot volumes)
 * - Optional 10 Mbps load balancer (free on both account types)
 * - Budget alerts for cost monitoring
 *
 * All resources are configured to stay within free tier limits.
 * See variables.tf for the full list of configurable options.
 */

terraform {
  required_version = ">= 1.7" # mock_provider in tests requires 1.7+; check blocks require 1.5+

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 8.4"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

provider "oci" {
  region              = var.region
  config_file_profile = var.oci_config_profile
}

provider "cloudflare" {}

# Resolved compartment OCID — either the newly created one or the one passed in.
# All resources in this module reference local.compartment_id, not var.compartment_ocid.
locals {
  compartment_id = var.create_compartment ? oci_identity_compartment.managed[0].id : var.compartment_ocid
}

# ---------------------------------------------------------------------------
# Managed compartment + IAM (optional)
# ---------------------------------------------------------------------------

resource "oci_identity_compartment" "managed" {
  count          = var.create_compartment ? 1 : 0
  compartment_id = var.tenancy_ocid
  name           = var.compartment_name
  description    = "Managed free-tier compartment"
  enable_delete  = true

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

resource "oci_identity_group" "free_tier" {
  count          = var.create_compartment ? 1 : 0
  compartment_id = var.tenancy_ocid # groups are always tenancy-level
  name           = "${var.compartment_name}-managers"
  description    = "Service group with access to ${var.compartment_name} compartment"

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

resource "oci_identity_user" "free_tier" {
  count          = var.create_compartment ? 1 : 0
  compartment_id = var.tenancy_ocid # users are always tenancy-level
  name           = "${var.compartment_name}-user"
  description    = "Service user for ${var.compartment_name} compartment"

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

resource "oci_identity_user_group_membership" "free_tier" {
  count    = var.create_compartment ? 1 : 0
  group_id = oci_identity_group.free_tier[0].id
  user_id  = oci_identity_user.free_tier[0].id
}

resource "oci_identity_policy" "free_tier" {
  count          = var.create_compartment ? 1 : 0
  compartment_id = var.tenancy_ocid # policies granting compartment access must be at tenancy level
  name           = "${var.compartment_name}-policy"
  description    = "Grants ${var.compartment_name}-managers full access to ${var.compartment_name}"
  statements = [
    "Allow group ${oci_identity_group.free_tier[0].name} to manage all-resources in compartment ${var.compartment_name}",
  ]

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

resource "oci_identity_api_key" "free_tier" {
  count     = var.create_compartment && var.iam_api_public_key != null ? 1 : 0
  user_id   = oci_identity_user.free_tier[0].id
  key_value = var.iam_api_public_key
}

# Virtual Cloud Network
resource "oci_core_vcn" "free_tier_vcn" {
  count          = var.existing_subnet_ocid == null ? 1 : 0
  compartment_id = local.compartment_id
  display_name   = "free-tier-vcn"
  # Appending the secondary block is an in-place AddVcnCidr update. The primary
  # 10.0.0.0/16 stays first and unchanged — never renumber it (recreates the
  # subnet + Ampere instances). See vpn.tf for the non-destructive contract.
  cidr_blocks = var.enable_oci_vpn ? ["10.0.0.0/16", var.vpn_vcn_secondary_cidr] : ["10.0.0.0/16"]
  dns_label   = "freetier"
}

# Internet Gateway
resource "oci_core_internet_gateway" "free_tier_igw" {
  count          = var.existing_subnet_ocid == null ? 1 : 0
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.free_tier_vcn[0].id
  display_name   = "free-tier-igw"
  enabled        = true
}

# NAT Gateway — gives private-IP instances (E2.1.Micro) outbound internet
# access (e.g. Tailscale, apt). OCI's IGW only routes egress for instances
# WITH a public IP; private instances need a NAT gateway.
resource "oci_core_nat_gateway" "free_tier_nat" {
  count          = var.existing_subnet_ocid == null ? 1 : 0
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.free_tier_vcn[0].id
  display_name   = "free-tier-nat"
  block_traffic  = false
}

# Private Route Table — used by the main workload subnet (private-IP Micros +
# Ampere nodes). Outbound internet goes through the NAT gateway so instances
# without a public IP can reach apt, Tailscale, etc.
resource "oci_core_route_table" "free_tier_route_table" {
  count          = var.existing_subnet_ocid == null ? 1 : 0
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.free_tier_vcn[0].id
  display_name   = "free-tier-route-table"

  route_rules {
    network_entity_id = oci_core_nat_gateway.free_tier_nat[0].id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }
}

# Public Route Table — used by the public bastion subnet. Inbound traffic to a
# reserved public IP reaches the bastion, and outbound return traffic leaves via
# the Internet Gateway so the public IP is preserved (required for SSH).
resource "oci_core_route_table" "free_tier_public_route_table" {
  count          = var.existing_subnet_ocid == null ? 1 : 0
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.free_tier_vcn[0].id
  display_name   = "free-tier-public-route-table"

  # E2.1.Micro permits one VNIC. Route only approved home targets through the
  # DRG so the bastion reaches Harbor without a secondary VPN-subnet VNIC.
  dynamic "route_rules" {
    for_each = local.vpn_enabled ? local.vpn_static_route_cidrs : []

    content {
      destination       = route_rules.value
      destination_type  = "CIDR_BLOCK"
      network_entity_id = oci_core_drg.vpn_drg[0].id
      description       = "Scoped home VPN target"
    }
  }

  route_rules {
    network_entity_id = oci_core_internet_gateway.free_tier_igw[0].id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }
}

# Security List
resource "oci_core_security_list" "free_tier_security_list" {
  count          = var.existing_subnet_ocid == null ? 1 : 0
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.free_tier_vcn[0].id
  display_name   = "free-tier-security-list"

  # Egress: Allow all outbound
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  # Ingress: SSH (required by the self-managed bastion; UFW + knockd restrict
  # access on the instance. Workload Micros block SSH via UFW.)
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
  }

  # Ingress: Bastion knockd ports. SSH stays closed until the sequence is
  # completed; these ports only wake up knockd, not any listening service.
  dynamic "ingress_security_rules" {
    for_each = var.create_bastion ? var.bastion_knock_ports : []
    content {
      protocol = "6" # TCP
      source   = "0.0.0.0/0"
      tcp_options {
        min = ingress_security_rules.value
        max = ingress_security_rules.value
      }
    }
  }

  # Ingress: HTTP
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 80
      max = 80
    }
  }

  # Ingress: HTTPS
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 443
      max = 443
    }
  }

  # Ingress: ICMP for ping
  ingress_security_rules {
    protocol = "1" # ICMP
    source   = "0.0.0.0/0"
  }

  # Ingress: Talos API (apid)
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 50000
      max = 50000
    }
  }

  # Ingress: Kubernetes API server
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 6443
      max = 6443
    }
  }

  # Ingress: SideroLink (WireGuard — Omni homelab → OCI nodes)
  ingress_security_rules {
    protocol = "17" # UDP
    source   = "0.0.0.0/0"
    udp_options {
      min = 50180
      max = 50180
    }
  }

  # Ingress: Kubernetes node-to-node (inter-pod, intra-cluster)
  ingress_security_rules {
    protocol = "all"
    source   = "10.0.0.0/16"
  }
}

# Subnet
resource "oci_core_subnet" "free_tier_subnet" {
  count             = var.existing_subnet_ocid == null ? 1 : 0
  compartment_id    = local.compartment_id
  vcn_id            = oci_core_vcn.free_tier_vcn[0].id
  cidr_block        = "10.0.1.0/24"
  display_name      = "free-tier-subnet"
  dns_label         = "subnet"
  route_table_id    = oci_core_route_table.free_tier_route_table[0].id
  security_list_ids = [oci_core_security_list.free_tier_security_list[0].id]
}

# Public subnet for the self-managed bastion and Packer golden-image builds.
# A public IP + IGW route table is required for inbound SSH; workload Micros
# stay in the private NAT-routed subnet.
resource "oci_core_subnet" "free_tier_public_subnet" {
  count             = var.existing_subnet_ocid == null ? 1 : 0
  compartment_id    = local.compartment_id
  vcn_id            = oci_core_vcn.free_tier_vcn[0].id
  cidr_block        = "10.0.2.0/24"
  display_name      = "free-tier-public-subnet"
  dns_label         = "public"
  route_table_id    = oci_core_route_table.free_tier_public_route_table[0].id
  security_list_ids = [oci_core_security_list.free_tier_security_list[0].id]
}

# Ampere A1 Instances (ARM-based, free tier)
# Node configuration is resolved in data.tf from var.ampere_nodes + tier defaults.
resource "oci_core_instance" "ampere_instance" {
  count               = length(local._ampere_nodes)
  availability_domain = var.availability_domain
  compartment_id      = local.compartment_id
  display_name        = local._ampere_nodes[count.index].name
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = local._ampere_nodes[count.index].ocpus
    memory_in_gbs = local._ampere_nodes[count.index].memory_gb
  }

  source_details {
    source_type             = "image"
    source_id               = local.ampere_image_id
    boot_volume_size_in_gbs = local._ampere_nodes[count.index].boot_vol_gb
  }

  create_vnic_details {
    subnet_id        = local.ampere_subnet_ids[count.index]
    assign_public_ip = false # public IPs are managed explicitly via oci_core_public_ip.ampere_instance[*]
    display_name     = "ampere-vnic-${count.index + 1}"
  }

  metadata = merge(
    # user_data: Talos MachineConfig fragments (null = omit for plain Ubuntu/bare Talos)
    local._ampere_user_data != null ? { user_data = base64encode(local._ampere_user_data) } : {},
    # ssh_authorized_keys: Ubuntu cloud-init only (Talos ignores this)
    var.talos_image_ocid == null && var.ssh_public_key != null ? { ssh_authorized_keys = var.ssh_public_key } : {},
  )

  lifecycle {
    replace_triggered_by = [terraform_data.omni_credentials]
    ignore_changes = [
      source_details[0].source_id, # image OCID changes on new OCI image releases
      availability_domain,         # may differ from var if instance was imported
      shape_config,                # OCPUs/memory set at launch; resize via OCI console
    ]
  }
}

# Tracks hashes of Omni machine config + Tailscale auth key.
# Any change to these bootstrap inputs triggers replacement of all Ampere instances,
# ensuring the new credentials are baked into user_data on the next boot.
resource "terraform_data" "omni_credentials" {
  input = {
    machine_config_hash = sha256(var.omni_machine_config != null ? var.omni_machine_config : "")
    ts_key_hash         = sha256(var.tailscale_auth_key != null ? var.tailscale_auth_key : "")
  }
}

# AMD E2.1.Micro Instances (x86-based, Always Free accounts only)
# Node configuration is resolved in data.tf from var.micro_nodes + tier defaults.
resource "oci_core_instance" "micro_instance" {
  count               = length(local._micro_nodes)
  availability_domain = var.micro_availability_domain
  compartment_id      = local.compartment_id
  display_name        = local._micro_nodes[count.index].name
  shape               = "VM.Standard.E2.1.Micro"

  source_details {
    source_type             = "image"
    source_id               = local.micro_image_id
    boot_volume_size_in_gbs = local._micro_nodes[count.index].boot_vol_gb
  }

  create_vnic_details {
    subnet_id              = local._micro_nodes[count.index].vpn_router && local.vpn_enabled ? oci_core_subnet.vpn_subnet[0].id : local.subnet_id
    assign_public_ip       = false # reserved public IP is attached separately to the public bastion
    display_name           = "micro-vnic-${count.index + 1}"
    private_ip             = local._micro_nodes[count.index].private_ip
    skip_source_dest_check = local._micro_nodes[count.index].vpn_router
  }

  metadata = merge(
    length(local._ssh_authorized_keys) > 0 ? { ssh_authorized_keys = join("\n", local._ssh_authorized_keys) } : {},
    { user_data = local._micro_user_data[count.index] },
    var.tailscale_auth_key != null ? { tailscale_auth_key = var.tailscale_auth_key } : {},
  )

  lifecycle {
    prevent_destroy = false # TEMP: lifted to recreate oci-micro-01 with operator key + working NAT egress; restored after
    ignore_changes = [
      # source_id intentionally NOT ignored so micro_golden_image_ocid bumps roll out (matches vpn_probe)
      availability_domain,
      shape_config,
    ]
  }
}

# Optional Load Balancer (free 10 Mbps tier)
# Set load_balancer = {} in tfvars to create the free LB.
# For Kubernetes: annotate Services with oci-load-balancer-shape: "10Mbps"
resource "oci_load_balancer_load_balancer" "free_tier_lb" {
  count          = var.load_balancer != null ? 1 : 0
  compartment_id = local.compartment_id
  display_name   = "free-tier-lb"
  shape          = var.load_balancer.shape

  shape_details {
    minimum_bandwidth_in_mbps = var.load_balancer.bandwidth_mbps
    maximum_bandwidth_in_mbps = var.load_balancer.bandwidth_mbps
  }

  subnet_ids = [local.subnet_id]
}

# Budget Alert (monitors for any paid usage)
resource "oci_budget_budget" "free_tier_budget" {
  count          = var.create_budget ? 1 : 0
  compartment_id = var.tenancy_ocid # budgets must be owned at tenancy (root) scope
  amount         = 1                # Minimum allowed budget amount (threshold set to $0.01 below)
  reset_period   = "MONTHLY"
  display_name   = "free-tier-budget-alert"
  description    = "Alert when any costs are incurred beyond free tier"

  # Cost invoice is tenancy-wide. Target root compartment so charges from
  # resources outside the managed workload compartment are not missed.
  target_type                           = "COMPARTMENT"
  targets                               = [var.tenancy_ocid]
  budget_processing_period_start_offset = 1
}

# Budget Alert Rule
resource "oci_budget_alert_rule" "free_tier_alert" {
  count          = var.create_budget ? 1 : 0
  budget_id      = oci_budget_budget.free_tier_budget[0].id
  display_name   = "free-tier-cost-alert"
  type           = "ACTUAL"
  threshold      = 1 # Alert at 1% of budget ($0.01)
  threshold_type = "PERCENTAGE"
  message        = "WARNING: Charges detected! You may have exceeded OCI free tier limits."
  recipients     = var.budget_alert_email
}

# Clean up failed launch artifacts on every Terraform apply. The helper only
# deletes boot volumes already in TERMINATED state; attached or AVAILABLE
# volumes are never eligible.
resource "terraform_data" "cleanup_stale_boot_volumes" {
  triggers_replace = timestamp()

  provisioner "local-exec" {
    command = "python3 ${path.module}/../../scripts/cleanup_stale_boot_volumes.py --tenancy-ocid ${var.tenancy_ocid} --profile ${var.oci_config_profile}"
  }
}

# Reserved IPs for all Ampere nodes — stable and explicitly managed.
resource "oci_core_public_ip" "ampere_instance" {
  count          = length(local._ampere_nodes)
  compartment_id = local.compartment_id
  lifetime       = "RESERVED"
  display_name   = "${local._ampere_nodes[count.index].name}-ip"
  private_ip_id  = data.oci_core_private_ips.ampere_private_ip[count.index].private_ips[0].id
}

# Reserved IP for K8s ingress controller — stable external endpoint
resource "oci_core_public_ip" "ingress" {
  count          = var.create_ingress_ip ? 1 : 0
  compartment_id = local.compartment_id
  lifetime       = "RESERVED"
  display_name   = "k8s-ingress-ip"
}

# Resolved by instance ID (via its VNIC), not subnet+address — a subnet+address
# match goes ambiguous under create_before_destroy, where the old (deposed) and
# new instance briefly share the same subnet.
data "oci_core_vnic_attachments" "ampere_instance" {
  count          = length(local._ampere_nodes)
  compartment_id = local.compartment_id
  instance_id    = oci_core_instance.ampere_instance[count.index].id
}

data "oci_core_private_ips" "ampere_private_ip" {
  count   = length(local._ampere_nodes)
  vnic_id = data.oci_core_vnic_attachments.ampere_instance[count.index].vnic_attachments[0].vnic_id
}

# ---------------------------------------------------------------------------
# Packer integration — auto-generate the Packer variable file from live
# Terraform values so the golden image build is always wired to the current
# network, compartment, and base image.
# ---------------------------------------------------------------------------

resource "terraform_data" "packer_vars_inputs" {
  count = var.write_packer_vars ? 1 : 0

  input = {
    compartment_ocid    = local.compartment_id
    availability_domain = var.micro_availability_domain
    subnet_ocid         = local.public_subnet_id
    base_image_ocid     = data.oci_core_images.micro_images.images[0].id
    access_cfg_file     = var.oci_config_profile
  }
}

resource "local_file" "packer_vars" {
  count = var.write_packer_vars ? 1 : 0

  filename = "${path.module}/../../packer/variables.auto.pkrvars.hcl"
  content = templatefile("${path.module}/templates/packer-vars.tmpl", {
    compartment_ocid    = local.compartment_id
    availability_domain = var.micro_availability_domain
    subnet_ocid         = local.public_subnet_id
    base_image_ocid     = data.oci_core_images.micro_images.images[0].id
    image_name          = "golden-micro"
    access_cfg_file     = var.oci_config_profile
    shape               = "VM.Standard.E2.1.Micro"
    ssh_username        = "ubuntu"
    enable_monitoring   = false
  })

  lifecycle {
    replace_triggered_by = [
      terraform_data.packer_vars_inputs[0],
    ]
  }
}

moved {
  from = oci_core_public_ip.micro_instance[0]
  to   = oci_core_public_ip.bastion[0]
}

moved {
  from = oci_core_public_ip.ingress
  to   = oci_core_public_ip.ingress[0]
}

moved {
  from = oci_core_public_ip.ampere_ssh[0]
  to   = oci_core_public_ip.ampere_instance[0]
}
