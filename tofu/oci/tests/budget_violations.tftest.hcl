# Test: Budget violation detection
#
# Verifies that check blocks fire when free-tier limits are exceeded:
#   - Total OCPUs > 4
#   - Total RAM > 24 GB
#   - Total storage > 200 GB
#   - Boot volume < 47 GB (OCI minimum)

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
  omni_ready         = false
}

# ---------------------------------------------------------------------------
# OCPU violations
# ---------------------------------------------------------------------------

# 5 nodes × 1 OCPU = 5 total → exceeds limit of 4
# Also exceeds storage (5 × 50 GB = 250 GB), so both checks fire.
run "ocpu_budget_5_nodes_1_each" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 1, memory_gb = 4 },
      { ocpus = 1, memory_gb = 4 },
      { ocpus = 1, memory_gb = 4 },
      { ocpus = 1, memory_gb = 4 },
      { ocpus = 1, memory_gb = 4 },
    ]
  }

  expect_failures = [check.ocpu_budget, check.storage_budget]
}

# 2 nodes × 3 OCPUs = 6 total → exceeds limit of 4
run "ocpu_budget_2_nodes_3_each" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 3, memory_gb = 8 },
      { ocpus = 3, memory_gb = 8 },
    ]
  }

  expect_failures = [check.ocpu_budget]
}

# 1 node × 5 OCPUs → exceeds limit of 4
run "ocpu_budget_single_node_5_ocpus" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 5, memory_gb = 20 },
    ]
  }

  expect_failures = [check.ocpu_budget]
}

# Exactly 4 OCPUs → must NOT trigger the check
run "ocpu_budget_exactly_4_passes" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 2, memory_gb = 8 },
      { ocpus = 2, memory_gb = 8 },
    ]
  }

  assert {
    condition     = local.total_ocpus == 4
    error_message = "Expected total_ocpus == 4"
  }
}

# ---------------------------------------------------------------------------
# RAM violations
# ---------------------------------------------------------------------------

# 3 nodes × 9 GB = 27 GB → exceeds limit of 24 GB
run "ram_budget_3_nodes_9gb_each" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 1, memory_gb = 9 },
      { ocpus = 1, memory_gb = 9 },
      { ocpus = 1, memory_gb = 9 },
    ]
  }

  expect_failures = [check.ram_budget]
}

# 2 nodes × 13 GB = 26 GB → exceeds limit of 24 GB
run "ram_budget_2_nodes_13gb_each" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 2, memory_gb = 13 },
      { ocpus = 2, memory_gb = 13 },
    ]
  }

  expect_failures = [check.ram_budget]
}

# 1 node × 25 GB → exceeds limit of 24 GB
run "ram_budget_single_node_25gb" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 4, memory_gb = 25 },
    ]
  }

  expect_failures = [check.ram_budget]
}

# Exactly 24 GB → must NOT trigger the check
run "ram_budget_exactly_24gb_passes" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 2, memory_gb = 12 },
      { ocpus = 2, memory_gb = 12 },
    ]
  }

  assert {
    condition     = local.total_ram_gb == 24
    error_message = "Expected total_ram_gb == 24"
  }
}

# ---------------------------------------------------------------------------
# Storage violations
# ---------------------------------------------------------------------------

# 4 nodes × 51 GB = 204 GB → exceeds 200 GB
run "storage_budget_4_nodes_51gb_each" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 1, memory_gb = 6, boot_vol_gb = 51 },
      { ocpus = 1, memory_gb = 6, boot_vol_gb = 51 },
      { ocpus = 1, memory_gb = 6, boot_vol_gb = 51 },
      { ocpus = 1, memory_gb = 6, boot_vol_gb = 51 },
    ]
  }

  expect_failures = [check.storage_budget]
}

# 3 nodes × 68 GB = 204 GB → exceeds 200 GB
run "storage_budget_3_nodes_68gb_each" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 1, memory_gb = 8, boot_vol_gb = 68 },
      { ocpus = 1, memory_gb = 8, boot_vol_gb = 68 },
      { ocpus = 1, memory_gb = 8, boot_vol_gb = 68 },
    ]
  }

  expect_failures = [check.storage_budget]
}

# 1 node × 201 GB → exceeds 200 GB
run "storage_budget_single_node_201gb" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 4, memory_gb = 24, boot_vol_gb = 201 },
    ]
  }

  expect_failures = [check.storage_budget]
}

# Exactly 200 GB → must NOT trigger the check
run "storage_budget_exactly_200gb_passes" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 1, memory_gb = 6, boot_vol_gb = 50 },
      { ocpus = 1, memory_gb = 6, boot_vol_gb = 50 },
      { ocpus = 1, memory_gb = 6, boot_vol_gb = 50 },
      { ocpus = 1, memory_gb = 6, boot_vol_gb = 50 },
    ]
    micro_nodes = [] # suppress default micro to keep total at exactly 200 GB
  }

  assert {
    condition     = local.total_storage_gb == 200
    error_message = "Expected total_storage_gb == 200"
  }
}

# ---------------------------------------------------------------------------
# Boot volume minimum size violations
# ---------------------------------------------------------------------------

# boot_vol_gb = 46 → below OCI minimum of 47 GB
run "ampere_boot_vol_below_minimum" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 1, memory_gb = 6, boot_vol_gb = 46 },
    ]
  }

  expect_failures = [check.ampere_min_boot_vol]
}

# boot_vol_gb = 47 → exactly at minimum, must pass
run "ampere_boot_vol_at_minimum_passes" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 1, memory_gb = 6, boot_vol_gb = 47 },
    ]
  }

  assert {
    condition     = local._ampere_nodes[0].boot_vol_gb == 47
    error_message = "Expected boot_vol_gb == 47"
  }
}
