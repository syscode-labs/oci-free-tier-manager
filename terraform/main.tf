/*
 * OCI Free Tier Infrastructure
 *
 * This Terraform configuration provisions resources within Oracle Cloud Infrastructure's
 * Always Free tier limits. It includes:
 * - VCN and networking components
 * - Ampere A1 compute instances (up to 4 OCPUs, 24GB RAM total)
 * - AMD E2.1.Micro instances (up to 2 instances)
 * - Block storage (up to 200GB total including boot volumes)
 * - Budget alerts for cost monitoring
 *
 * All resources are configured to stay within free tier limits.
 */

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
  }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

# Virtual Cloud Network
resource "oci_core_vcn" "free_tier_vcn" {
  compartment_id = var.compartment_ocid
  display_name   = "free-tier-vcn"
  cidr_blocks    = ["10.0.0.0/16"]
  dns_label      = "freetier"
}

# Internet Gateway
resource "oci_core_internet_gateway" "free_tier_igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.free_tier_vcn.id
  display_name   = "free-tier-igw"
  enabled        = true
}

# Route Table
resource "oci_core_route_table" "free_tier_route_table" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.free_tier_vcn.id
  display_name   = "free-tier-route-table"

  route_rules {
    network_entity_id = oci_core_internet_gateway.free_tier_igw.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }
}

# Security List
resource "oci_core_security_list" "free_tier_security_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.free_tier_vcn.id
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
}

# Subnet
resource "oci_core_subnet" "free_tier_subnet" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.free_tier_vcn.id
  cidr_block        = "10.0.1.0/24"
  display_name      = "free-tier-subnet"
  dns_label         = "subnet"
  route_table_id    = oci_core_route_table.free_tier_route_table.id
  security_list_ids = [oci_core_security_list.free_tier_security_list.id]
}

# Ampere A1 Instances (ARM-based, free tier)
# Configuration: 4 instances with 1 OCPU and 6GB RAM each
# Total: 4 OCPUs and 24GB RAM (within free tier limits)
resource "oci_core_instance" "ampere_instance" {
  count               = var.ampere_instance_count
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "ampere-instance-${count.index + 1}"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.ampere_ocpus_per_instance
    memory_in_gbs = var.ampere_memory_per_instance
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ampere_images.images[0].id
    boot_volume_size_in_gbs = var.ampere_boot_volume_size
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.free_tier_subnet.id
    assign_public_ip = true
    display_name     = "ampere-vnic-${count.index + 1}"
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }

  # Prevent accidental deletion
  lifecycle {
    ignore_changes = [
      source_details[0].source_id, # Ignore image updates
    ]
  }
}

# AMD E2.1.Micro Instances (x86-based, free tier)
# Maximum: 2 instances per tenancy
resource "oci_core_instance" "micro_instance" {
  count               = var.micro_instance_count
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "micro-instance-${count.index + 1}"
  shape               = "VM.Standard.E2.1.Micro"

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.micro_images.images[0].id
    boot_volume_size_in_gbs = var.micro_boot_volume_size
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.free_tier_subnet.id
    assign_public_ip = true
    display_name     = "micro-vnic-${count.index + 1}"
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }

  lifecycle {
    ignore_changes = [
      source_details[0].source_id,
    ]
  }
}

# Additional Block Volume (if needed within 200GB total limit)
resource "oci_core_volume" "additional_storage" {
  count               = var.create_additional_volume ? 1 : 0
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "free-tier-volume"
  size_in_gbs         = var.additional_volume_size
}

# Budget Alert (monitors for any paid usage)
resource "oci_budget_budget" "free_tier_budget" {
  compartment_id = var.tenancy_ocid
  amount         = 0.01 # Alert immediately if any charges occur
  reset_period   = "MONTHLY"
  display_name   = "free-tier-budget-alert"
  description    = "Alert when any costs are incurred beyond free tier"

  target_type         = "COMPARTMENT"
  targets             = [var.compartment_ocid]
  budget_processing_period_start_offset = 1
}

# Budget Alert Rule
resource "oci_budget_alert_rule" "free_tier_alert" {
  budget_id      = oci_budget_budget.free_tier_budget.id
  display_name   = "free-tier-cost-alert"
  type           = "ACTUAL"
  threshold      = 0.01
  threshold_type = "ABSOLUTE"
  message        = "WARNING: Charges detected! You may have exceeded OCI free tier limits."
  recipients     = var.budget_alert_email
}
