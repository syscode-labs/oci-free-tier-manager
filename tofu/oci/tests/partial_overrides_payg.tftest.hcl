# Test: Partial override behaviour on PAYG accounts
#
# Verifies that omitted node fields fall back to the defaults
# (1 OCPU / 8 GB / 50 GB — same for all account types), and that
# overrides work correctly. Also verifies E2.1.Micro works on PAYG.

mock_provider "oci" {
  mock_data "oci_core_images" {
    defaults = {
      images = [
        {
          id                       = "ocid1.image.test.ampere"
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

  mock_resource "oci_core_vcn" { defaults = { id = "ocid1.vcn.test" } }
  mock_resource "oci_core_internet_gateway" { defaults = { id = "ocid1.igw.test" } }
  mock_resource "oci_core_route_table" { defaults = { id = "ocid1.rt.test" } }
  mock_resource "oci_core_security_list" { defaults = { id = "ocid1.sl.test" } }
  mock_resource "oci_core_subnet" { defaults = { id = "ocid1.subnet.test" } }
  mock_resource "oci_core_instance" {
    defaults = { id = "ocid1.instance.test", public_ip = "1.2.3.4", private_ip = "10.0.1.10" }
  }
  mock_resource "oci_budget_budget" { defaults = { id = "ocid1.budget.test" } }
  mock_resource "oci_budget_alert_rule" { defaults = { id = "ocid1.alertrule.test" } }
  mock_resource "oci_core_public_ip" {
    defaults = { id = "ocid1.publicip.test", ip_address = "1.2.3.4" }
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
}

# --- Empty {} per node uses defaults (1 OCPU / 8 GB) ---
run "empty_objects_use_defaults" {
  command = plan

  variables {
    ampere_nodes = [{}, {}, {}]
  }

  assert {
    condition     = local._ampere_nodes[0].ocpus == 1
    error_message = "Expected default 1 OCPU for empty node"
  }

  assert {
    condition     = local._ampere_nodes[0].memory_gb == 8
    error_message = "Expected default 8 GB RAM for empty node"
  }

  assert {
    condition     = alltrue([for n in local._ampere_nodes : n.ocpus == floor(n.ocpus)])
    error_message = "All defaults must be integer OCPUs"
  }
}

# --- Override just name; other fields remain defaults ---
run "payg_override_name_keeps_defaults" {
  command = plan

  variables {
    ampere_nodes = [
      { name = "node-a" },
      { name = "node-b" },
    ]
  }

  assert {
    condition     = local._ampere_nodes[0].name == "node-a"
    error_message = "Expected name 'node-a'"
  }

  assert {
    condition     = local._ampere_nodes[0].ocpus == 1
    error_message = "Expected default 1 OCPU when only name overridden"
  }

  assert {
    condition     = local._ampere_nodes[0].memory_gb == 8
    error_message = "Expected default 8 GB RAM when only name overridden"
  }
}

# --- PAYG: 2 nodes × 2 OCPU / 12 GB — valid custom configuration ---
run "payg_two_nodes_2ocpu_12gb" {
  command = plan

  variables {
    ampere_nodes = [
      { name = "k8s-cp", ocpus = 2, memory_gb = 12, boot_vol_gb = 100 },
      { name = "k8s-w1", ocpus = 2, memory_gb = 12, boot_vol_gb = 100 },
    ]
    micro_nodes = [] # suppress default micro to keep storage at 200 GB
  }

  assert {
    condition     = local.total_ocpus == 4
    error_message = "Expected 4 total OCPUs"
  }

  assert {
    condition     = local.total_ram_gb == 24
    error_message = "Expected 24 GB total RAM"
  }

  assert {
    condition     = local.total_storage_gb == 200
    error_message = "Expected 200 GB total storage (2 × 100 GB)"
  }
}

# --- PAYG: 1 node × 4 OCPUs / 24 GB (single beefy node) ---
run "payg_single_large_node" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 4, memory_gb = 24, boot_vol_gb = 100 },
    ]
  }

  assert {
    condition     = local.total_ocpus == 4
    error_message = "Expected 4 OCPUs"
  }

  assert {
    condition     = local.total_ram_gb == 24
    error_message = "Expected 24 GB RAM"
  }
}

# --- PAYG: Override only boot volume ---
run "payg_override_boot_vol_only" {
  command = plan

  variables {
    ampere_nodes = [
      { boot_vol_gb = 100 },
      { boot_vol_gb = 100 },
    ]
    micro_nodes = [] # suppress default micro to keep storage at 200 GB
  }

  assert {
    condition     = local._ampere_nodes[0].boot_vol_gb == 100
    error_message = "Expected overridden boot_vol_gb of 100"
  }

  assert {
    condition     = local._ampere_nodes[0].ocpus == 1
    error_message = "Expected default OCPUs when only boot_vol_gb overridden"
  }

  assert {
    condition     = local.total_storage_gb == 200
    error_message = "Expected 200 GB total storage (2 × 100 GB)"
  }
}

# --- PAYG: auto-generated names when none provided ---
run "payg_auto_generated_names" {
  command = plan

  variables {
    ampere_nodes = [{}, {}]
  }

  assert {
    condition     = local._ampere_nodes[0].name == "ampere-instance-1"
    error_message = "Expected auto-generated name 'ampere-instance-1'"
  }

  assert {
    condition     = local._ampere_nodes[1].name == "ampere-instance-2"
    error_message = "Expected auto-generated name 'ampere-instance-2'"
  }
}

# --- PAYG: micro_nodes=[{}] is valid (E2.1.Micro available on PAYG) ---
run "micro_on_payg_works" {
  command = plan

  variables {
    ampere_nodes = [{ ocpus = 1, memory_gb = 6 }]
    micro_nodes  = [{}]
  }

  assert {
    condition     = length(local._micro_nodes) == 1
    error_message = "Expected 1 micro node on PAYG"
  }

  assert {
    condition     = local._micro_nodes[0].boot_vol_gb == 50
    error_message = "Expected default 50 GB boot volume for micro node"
  }
}
