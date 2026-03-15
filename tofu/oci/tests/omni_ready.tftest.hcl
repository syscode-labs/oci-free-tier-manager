# Test: omni_ready = true mode
#
# Verifies that when omni_ready = true:
#   - The Talos image OCID is used for Ampere instances (not Ubuntu data source)
#   - user_data is set on Ampere instances (base64-encoded MachineConfig)
#   - All budget checks still pass
#   - Missing prerequisites trigger check failures

mock_provider "oci" {
  mock_data "oci_core_images" {
    defaults = {
      images = [
        {
          id                       = "ocid1.image.test.ubuntu"
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
  omni_ready         = true
  talos_image_ocid   = "ocid1.image.oc1.uk-london-1.talos-test"
  omni_endpoint      = "omni.example.ts.net:8090"
  omni_join_token    = "test-join-token"
  tailscale_auth_key = "tskey-auth-test" # pragma: allowlist secret
  ampere_nodes = [
    { name = "oci-talos-cp-1", ocpus = 1, memory_gb = 6, boot_vol_gb = 50 },
    { name = "oci-talos-cp-2", ocpus = 1, memory_gb = 6, boot_vol_gb = 50 },
    { name = "oci-talos-cp-3", ocpus = 1, memory_gb = 6, boot_vol_gb = 50 },
    { name = "oci-talos-worker-1", ocpus = 1, memory_gb = 6, boot_vol_gb = 50 },
  ]
  micro_nodes = []
}

# --- Talos image is used (not Ubuntu data source) ---
run "omni_ready_uses_talos_image" {
  command = plan

  assert {
    condition     = local.ampere_image_id == "ocid1.image.oc1.uk-london-1.talos-test"
    error_message = "Expected Talos image OCID, got ${local.ampere_image_id}"
  }
}

# --- user_data is set on Ampere instances ---
run "omni_ready_sets_user_data" {
  command = plan

  assert {
    condition     = oci_core_instance.ampere_instance[0].metadata["user_data"] != null
    error_message = "Expected user_data to be set on Ampere instance when omni_ready = true"
  }
}

# --- user_data is valid base64 ---
run "omni_ready_user_data_is_base64" {
  command = plan

  assert {
    condition     = can(base64decode(oci_core_instance.ampere_instance[0].metadata["user_data"]))
    error_message = "user_data must be valid base64"
  }
}

# --- Budget checks still pass with 4 Ampere nodes (4 OCPUs / 24 GB) ---
run "omni_ready_4node_within_budget" {
  command = plan

  assert {
    condition     = local.total_ocpus == 4
    error_message = "Expected 4 total OCPUs, got ${local.total_ocpus}"
  }

  assert {
    condition     = local.total_ram_gb == 24
    error_message = "Expected 24 GB total RAM, got ${local.total_ram_gb}"
  }

  assert {
    condition     = local.total_storage_gb == 200
    error_message = "Expected 200 GB total storage, got ${local.total_storage_gb}"
  }
}

# --- omni_ready = true without talos_image_ocid fails prerequisite check ---
run "omni_ready_without_image_fails" {
  command = plan

  variables {
    talos_image_ocid = null
  }

  expect_failures = [
    check.omni_ready_requires_talos_image,
  ]
}

# --- omni_ready = true without omni_endpoint fails prerequisite check ---
run "omni_ready_without_endpoint_fails" {
  command = plan

  variables {
    omni_endpoint = null
  }

  expect_failures = [
    check.omni_ready_requires_endpoint,
  ]
}
