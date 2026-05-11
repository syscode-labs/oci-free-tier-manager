# Test: Default configuration
#
# Verifies the out-of-the-box defaults when no node variables are set:
#   3 x A1.Flex (1 OCPU / 8 GB / 50 GB)
#   Total: 3 OCPUs, 24 GB RAM, 150 GB storage
#
# All budget checks must pass.

mock_provider "oci" {
  mock_data "oci_core_images" {
    defaults = {
      images = [
        {
          id                       = "ocid1.image.test.ampere.ubuntu2204"
          display_name             = "Canonical-Ubuntu-22.04-aarch64-2024.01.01-0"
          operating_system         = "Canonical Ubuntu"
          operating_system_version = "22.04"
          time_created             = "2024-01-01T00:00:00.000Z"
          state                    = "AVAILABLE"
          create_image_allowed     = true
          compartment_id           = ""
          base_image_id            = ""
          billable_size_in_gbs     = ""
          instance_id              = ""
          launch_mode              = ""
          listing_type             = ""
          size_in_mbs              = ""
          agent_features           = []
          defined_tags             = {}
          freeform_tags            = {}
          image_source_details     = []
          launch_options           = []
        }
      ]
    }
  }

  mock_resource "oci_core_vcn" {
    defaults = { id = "ocid1.vcn.test" }
  }
  mock_resource "oci_core_internet_gateway" {
    defaults = { id = "ocid1.igw.test" }
  }
  mock_resource "oci_core_route_table" {
    defaults = { id = "ocid1.rt.test" }
  }
  mock_resource "oci_core_security_list" {
    defaults = { id = "ocid1.sl.test" }
  }
  mock_resource "oci_core_subnet" {
    defaults = { id = "ocid1.subnet.test" }
  }
  mock_resource "oci_core_instance" {
    defaults = {
      id         = "ocid1.instance.test"
      public_ip  = "1.2.3.4"
      private_ip = "10.0.1.10"
    }
  }
  mock_resource "oci_budget_budget" {
    defaults = { id = "ocid1.budget.test" }
  }
  mock_resource "oci_budget_alert_rule" {
    defaults = { id = "ocid1.alertrule.test" }
  }
  mock_resource "oci_core_public_ip" {
    defaults = { id = "ocid1.publicip.test", ip_address = "10.20.30.40" }
  }
  mock_data "oci_core_private_ips" {
    defaults = {
      private_ips = [{ id = "ocid1.privateip.test", ip_address = "10.0.1.10" }]
    }
  }
}

variables {
  compartment_ocid   = "ocid1.compartment.test"
  tenancy_ocid       = "ocid1.tenancy.test"
  budget_alert_email = "test@example.com"
  omni_ready         = false
  # null → use tier defaults (overrides any terraform.tfvars values)
  ampere_nodes = null
  micro_nodes  = null
}

# --- Default node counts: 3 Ampere + 0 Micro ---
run "default_node_counts" {
  command = plan

  assert {
    condition     = length(local._ampere_nodes) == 3
    error_message = "Expected 3 Ampere nodes by default, got ${length(local._ampere_nodes)}"
  }

  assert {
    condition     = length(local._micro_nodes) == 0
    error_message = "Expected 0 Micro nodes by default, got ${length(local._micro_nodes)}"
  }
}

# --- Default OCPU is 1 (integer) ---
run "default_ocpus" {
  command = plan

  assert {
    condition     = local._ampere_nodes[0].ocpus == 1
    error_message = "Expected 1 OCPU per node (integer default), got ${local._ampere_nodes[0].ocpus}"
  }

  assert {
    condition     = alltrue([for n in local._ampere_nodes : n.ocpus == floor(n.ocpus)])
    error_message = "All default OCPUs must be integers"
  }
}

# --- Default RAM is 8 GB per node ---
run "default_ram" {
  command = plan

  assert {
    condition     = local._ampere_nodes[0].memory_gb == 8
    error_message = "Expected 8 GB RAM per node, got ${local._ampere_nodes[0].memory_gb}"
  }
}

# --- Totals: 3 OCPUs, 24 GB RAM, 200 GB storage ---
run "default_totals" {
  command = plan

  assert {
    condition     = local.total_ocpus == 3
    error_message = "Expected total OCPUs of 3, got ${local.total_ocpus}"
  }

  assert {
    condition     = local.total_ram_gb == 24
    error_message = "Expected total RAM of 24 GB, got ${local.total_ram_gb}"
  }

  assert {
    condition     = local.total_storage_gb == 150
    error_message = "Expected total storage of 150 GB (3 x 50 GB, no default micro), got ${local.total_storage_gb}"
  }
}

# --- Budget checks must all pass ---
run "default_within_budget" {
  command = plan

  assert {
    condition     = local.total_ocpus <= 4
    error_message = "Total OCPUs ${local.total_ocpus} exceeds 4"
  }

  assert {
    condition     = local.total_ram_gb <= 24
    error_message = "Total RAM ${local.total_ram_gb} GB exceeds 24 GB"
  }

  assert {
    condition     = local.total_storage_gb <= 200
    error_message = "Total storage ${local.total_storage_gb} GB exceeds 200 GB"
  }
}

# --- Auto-generated names ---
run "default_names" {
  command = plan

  assert {
    condition     = local._ampere_nodes[0].name == "ampere-instance-1"
    error_message = "Expected name 'ampere-instance-1', got '${local._ampere_nodes[0].name}'"
  }
}

# --- Resource count: 3 Ampere instances + 0 Micro instances planned ---
run "default_resource_counts" {
  command = plan

  assert {
    condition     = length(oci_core_instance.ampere_instance) == 3
    error_message = "Expected 3 Ampere instances, got ${length(oci_core_instance.ampere_instance)}"
  }

  assert {
    condition     = length(oci_core_instance.micro_instance) == 0
    error_message = "Expected 0 micro instances, got ${length(oci_core_instance.micro_instance)}"
  }
}

# --- Micro instance always receives cloud-init user_data ---
run "micro_has_user_data" {
  command = plan

  variables {
    micro_nodes = [{}]
  }

  assert {
    condition     = oci_core_instance.micro_instance[0].metadata["user_data"] != null
    error_message = "Expected user_data to be set on micro instance"
  }
}

# --- Micro user_data is valid base64 ---
run "micro_user_data_is_base64" {
  command = plan

  variables {
    micro_nodes = [{}]
  }

  assert {
    condition     = can(base64decode(oci_core_instance.micro_instance[0].metadata["user_data"]))
    error_message = "Micro user_data must be valid base64"
  }
}

# --- Micro user_data decodes to a cloud-config document ---
run "micro_user_data_is_cloud_config" {
  command = plan

  variables {
    micro_nodes = [{}]
  }

  assert {
    condition     = startswith(base64decode(oci_core_instance.micro_instance[0].metadata["user_data"]), "#cloud-config")
    error_message = "Micro user_data must decode to a #cloud-config document"
  }
}
