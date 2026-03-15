# Test: Integer OCPU enforcement and E2.1.Micro availability
#
# Key facts:
#   - OCPUs are integer-only on ALL account types (min=1, step=1)
#   - E2.1.Micro is available on both Always Free and PAYG accounts
#
# The check.integer_ocpus block fires on fractional OCPUs.

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
}

# ---------------------------------------------------------------------------
# Integer OCPU enforcement
# ---------------------------------------------------------------------------

# 1.33 OCPUs → fractional, must fail check.integer_ocpus
run "integer_ocpu_enforced" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 1.33, memory_gb = 8 },
      { ocpus = 1.33, memory_gb = 8 },
      { ocpus = 1.33, memory_gb = 8 },
    ]
  }

  expect_failures = [check.integer_ocpus]
}

# 1.5 OCPUs → fractional, must fail
run "fractional_ocpu_1_5" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 1.5, memory_gb = 6 },
      { ocpus = 1.5, memory_gb = 6 },
    ]
  }

  expect_failures = [check.integer_ocpus]
}

# 0.5 OCPUs → fractional, must fail
run "fractional_ocpu_0_5" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 0.5, memory_gb = 6 },
    ]
  }

  expect_failures = [check.integer_ocpus]
}

# Mixed: some integer, some fractional → must fail
run "mixed_fractional_ocpus" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 2, memory_gb = 12 },   # integer — ok
      { ocpus = 1.33, memory_gb = 8 }, # fractional — fails
    ]
  }

  expect_failures = [check.integer_ocpus]
}

# Integer OCPUs → must pass
run "integer_ocpus_pass" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 2, memory_gb = 12 },
      { ocpus = 2, memory_gb = 12 },
    ]
  }

  assert {
    condition     = alltrue([for n in local._ampere_nodes : n.ocpus == floor(n.ocpus)])
    error_message = "Expected all OCPUs to be integers"
  }
}

# All valid integer values: 1, 2, 3, 4 per node
run "valid_ocpu_combinations" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 1, memory_gb = 6 },
      { ocpus = 1, memory_gb = 6 },
      { ocpus = 1, memory_gb = 6 },
      { ocpus = 1, memory_gb = 6 },
    ]
    micro_nodes = [] # suppress default micro to stay within storage budget
  }

  assert {
    condition     = local.total_ocpus == 4
    error_message = "Expected 4 total OCPUs"
  }
}

# ---------------------------------------------------------------------------
# E2.1.Micro — available on all account types
# ---------------------------------------------------------------------------

# micro_nodes=[{}] → valid, no check should fail
run "micro_passes" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 1, memory_gb = 6 },
    ]
    micro_nodes = [{}]
  }

  assert {
    condition     = length(local._micro_nodes) == 1
    error_message = "Expected 1 micro node on PAYG"
  }
}

# Two micro nodes → valid (up to 2 free instances)
run "micro_two_passes" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 2, memory_gb = 12 },
    ]
    micro_nodes = [{}, {}]
  }

  assert {
    condition     = length(local._micro_nodes) == 2
    error_message = "Expected 2 micro nodes on PAYG"
  }
}

# micro_nodes = [] → explicitly zero → must pass
run "empty_micro_list_passes" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 1, memory_gb = 6 },
    ]
    micro_nodes = []
  }

  assert {
    condition     = length(local._micro_nodes) == 0
    error_message = "Expected 0 micro nodes"
  }
}

# micro_nodes = null (default) → auto-1 → must pass
run "null_micro_defaults_to_one" {
  command = plan

  variables {
    ampere_nodes = [
      { ocpus = 1, memory_gb = 6 },
    ]
    # micro_nodes = null (omitted = default)
  }

  assert {
    condition     = length(local._micro_nodes) == 1
    error_message = "Expected micro_nodes to default to 1 on PAYG"
  }
}
