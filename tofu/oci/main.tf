/*
 * OCI Free Tier Infrastructure
 *
 * This Terraform configuration provisions resources within Oracle Cloud Infrastructure's
 * Always Free tier limits. It includes:
 * - VCN and networking components
 * - Ampere A1 compute instances (up to 4 OCPUs, 24GB RAM total)
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
  }
}

provider "oci" {
  region              = var.region
  config_file_profile = var.oci_config_profile
}

# Virtual Cloud Network
resource "oci_core_vcn" "free_tier_vcn" {
  count          = var.existing_subnet_ocid == null ? 1 : 0
  compartment_id = var.compartment_ocid
  display_name   = "free-tier-vcn"
  cidr_blocks    = ["10.0.0.0/16"]
  dns_label      = "freetier"
}

# Internet Gateway
resource "oci_core_internet_gateway" "free_tier_igw" {
  count          = var.existing_subnet_ocid == null ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.free_tier_vcn[0].id
  display_name   = "free-tier-igw"
  enabled        = true
}

# Route Table
resource "oci_core_route_table" "free_tier_route_table" {
  count          = var.existing_subnet_ocid == null ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.free_tier_vcn[0].id
  display_name   = "free-tier-route-table"

  route_rules {
    network_entity_id = oci_core_internet_gateway.free_tier_igw[0].id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }
}

# Security List
resource "oci_core_security_list" "free_tier_security_list" {
  count          = var.existing_subnet_ocid == null ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.free_tier_vcn[0].id
  display_name   = "free-tier-security-list"

  # Egress: Allow all outbound
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  # Ingress: SSH
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
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
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.free_tier_vcn[0].id
  cidr_block        = "10.0.1.0/24"
  display_name      = "free-tier-subnet"
  dns_label         = "subnet"
  route_table_id    = oci_core_route_table.free_tier_route_table[0].id
  security_list_ids = [oci_core_security_list.free_tier_security_list[0].id]
}

# Ampere A1 Instances (ARM-based, free tier)
# Node configuration is resolved in data.tf from var.ampere_nodes + tier defaults.
resource "oci_core_instance" "ampere_instance" {
  count               = length(local._ampere_nodes)
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_ocid
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
    subnet_id        = local.subnet_id
    assign_public_ip = false # public IPs are managed explicitly via oci_core_public_ip.ampere_instance[*]
    display_name     = "ampere-vnic-${count.index + 1}"
  }

  metadata = merge(
    # user_data: Talos MachineConfig for omni_ready mode (null = omit for Ubuntu)
    var.omni_ready ? { user_data = base64encode(local._ampere_user_data) } : {},
    # ssh_authorized_keys: Ubuntu cloud-init only (Talos ignores this)
    ! var.omni_ready && var.ssh_public_key != null ? { ssh_authorized_keys = var.ssh_public_key } : {},
  )

  lifecycle {
    ignore_changes = [
      source_details[0].source_id, # Ignore image updates after initial deploy
    ]
  }
}

# AMD E2.1.Micro Instances (x86-based, Always Free accounts only)
# Node configuration is resolved in data.tf from var.micro_nodes + tier defaults.
resource "oci_core_instance" "micro_instance" {
  count               = length(local._micro_nodes)
  availability_domain = var.micro_availability_domain
  compartment_id      = var.compartment_ocid
  display_name        = local._micro_nodes[count.index].name
  shape               = "VM.Standard.E2.1.Micro"

  source_details {
    source_type             = "image"
    source_id               = local.micro_image_id
    boot_volume_size_in_gbs = local._micro_nodes[count.index].boot_vol_gb
  }

  create_vnic_details {
    subnet_id        = local.subnet_id
    assign_public_ip = false # reserved IP assigned separately via oci_core_public_ip.bastion
    display_name     = "micro-vnic-${count.index + 1}"
  }

  metadata = var.ssh_public_key != null ? {
    ssh_authorized_keys = var.ssh_public_key
  } : {}

  lifecycle {
    ignore_changes = [
      source_details[0].source_id,
    ]
  }
}

# Optional Load Balancer (free 10 Mbps tier)
# Set load_balancer = {} in tfvars to create the free LB.
# For Kubernetes: annotate Services with oci-load-balancer-shape: "10Mbps"
resource "oci_load_balancer_load_balancer" "free_tier_lb" {
  count          = var.load_balancer != null ? 1 : 0
  compartment_id = var.compartment_ocid
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
  compartment_id = var.tenancy_ocid # budgets must be owned at tenancy (root) scope
  amount         = 1                # Minimum allowed budget amount (threshold set to $0.01 below)
  reset_period   = "MONTHLY"
  display_name   = "free-tier-budget-alert"
  description    = "Alert when any costs are incurred beyond free tier"

  target_type                           = "COMPARTMENT"
  targets                               = [var.compartment_ocid]
  budget_processing_period_start_offset = 1
}

# Budget Alert Rule
resource "oci_budget_alert_rule" "free_tier_alert" {
  budget_id      = oci_budget_budget.free_tier_budget.id
  display_name   = "free-tier-cost-alert"
  type           = "ACTUAL"
  threshold      = 1 # Alert at 1% of budget ($0.01)
  threshold_type = "PERCENTAGE"
  message        = "WARNING: Charges detected! You may have exceeded OCI free tier limits."
  recipients     = var.budget_alert_email
}

# Reserved IPs for all Ampere nodes — stable and explicitly managed.
resource "oci_core_public_ip" "ampere_instance" {
  count          = length(local._ampere_nodes)
  compartment_id = var.compartment_ocid
  lifetime       = "RESERVED"
  display_name   = "${local._ampere_nodes[count.index].name}-ip"
  private_ip_id  = data.oci_core_private_ips.ampere_private_ip[count.index].private_ips[0].id
}

# Reserved IPs for all Micro nodes — stable and explicitly managed.
resource "oci_core_public_ip" "micro_instance" {
  count          = length(local._micro_nodes)
  compartment_id = var.compartment_ocid
  lifetime       = "RESERVED"
  display_name   = "${local._micro_nodes[count.index].name}-ip"
  private_ip_id  = data.oci_core_private_ips.micro_private_ip[count.index].private_ips[0].id
}

# Reserved IP for K8s ingress controller — stable external endpoint
resource "oci_core_public_ip" "ingress" {
  compartment_id = var.compartment_ocid
  lifetime       = "RESERVED"
  display_name   = "k8s-ingress-ip"
}

data "oci_core_private_ips" "micro_private_ip" {
  count      = length(local._micro_nodes)
  subnet_id  = local.subnet_id
  ip_address = oci_core_instance.micro_instance[count.index].private_ip
}

data "oci_core_private_ips" "ampere_private_ip" {
  count      = length(local._ampere_nodes)
  subnet_id  = local.subnet_id
  ip_address = oci_core_instance.ampere_instance[count.index].private_ip
}

moved {
  from = oci_core_public_ip.bastion[0]
  to   = oci_core_public_ip.micro_instance[0]
}

moved {
  from = oci_core_public_ip.ampere_ssh[0]
  to   = oci_core_public_ip.ampere_instance[0]
}
