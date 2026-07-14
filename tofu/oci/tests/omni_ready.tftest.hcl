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
  compartment_ocid    = "ocid1.compartment.test"
  tenancy_ocid        = "ocid1.tenancy.test"
  budget_alert_email  = "test@example.com"
  omni_ready          = true
  talos_image_ocid    = "ocid1.image.oc1.uk-london-1.talos-test"
  omni_machine_config = <<-EOT
    apiVersion: v1alpha1
    kind: SideroLinkConfig
    apiUrl: https://omni.example.ts.net:8090/?jointoken=test-join-token
    ---
    apiVersion: v1alpha1
    kind: EventSinkConfig
    endpoint: '[fdae:41e4:649b:9303::1]:8091'
    ---
    apiVersion: v1alpha1
    kind: KmsgLogConfig
    name: omni-kmsg
    url: tcp://[fdae:41e4:649b:9303::1]:8092
  EOT
  tailscale_auth_key  = "tskey-auth-test" # pragma: allowlist secret
  ampere_nodes = [
    { name = "oci-talos-cp-1", ocpus = 1, memory_gb = 6, boot_vol_gb = 50 },
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

# --- official omnictl machine-config shape is preserved ---
run "omni_ready_uses_official_machine_config" {
  command = plan

  assert {
    condition     = strcontains(base64decode(oci_core_instance.ampere_instance[0].metadata["user_data"]), "apiUrl: https://omni.example.ts.net:8090/?jointoken=test-join-token")
    error_message = "Expected official Omni SideroLinkConfig to be used directly."
  }

  assert {
    condition     = strcontains(base64decode(oci_core_instance.ampere_instance[0].metadata["user_data"]), "kind: EventSinkConfig")
    error_message = "Expected official Omni EventSinkConfig to be preserved."
  }

  assert {
    condition     = strcontains(base64decode(oci_core_instance.ampere_instance[0].metadata["user_data"]), "kind: KmsgLogConfig")
    error_message = "Expected official Omni KmsgLogConfig to be preserved."
  }
}

# --- Budget checks pass with 2 Ampere nodes (2 OCPUs / 12 GB) ---
run "omni_ready_2node_within_budget" {
  command = plan

  assert {
    condition     = local.total_ocpus == 2
    error_message = "Expected 2 total OCPUs, got ${local.total_ocpus}"
  }

  assert {
    condition     = local.total_ram_gb == 12
    error_message = "Expected 12 GB total RAM, got ${local.total_ram_gb}"
  }

  assert {
    condition     = local.total_storage_gb == 100
    error_message = "Expected 100 GB total storage, got ${local.total_storage_gb}"
  }
}

# --- bare Talos mode: Talos image, no Omni metadata ---
run "bare_talos_uses_talos_image_without_user_data" {
  command = plan

  variables {
    omni_ready          = false
    talos_image_ocid    = "ocid1.image.oc1.uk-london-1.talos-test"
    omni_machine_config = null
    tailscale_auth_key  = null # pragma: allowlist secret
  }

  assert {
    condition     = local.ampere_image_id == "ocid1.image.oc1.uk-london-1.talos-test"
    error_message = "Expected bare Talos mode to use Talos image OCID, got ${local.ampere_image_id}"
  }

  assert {
    condition     = !contains(keys(oci_core_instance.ampere_instance[0].metadata), "user_data")
    error_message = "Expected bare Talos mode to omit Omni user_data"
  }
}

# --- tailnet-only Talos mode: Tailscale config without Omni enrollment ---
run "bare_talos_with_tailscale_sets_extension_only" {
  command = plan

  variables {
    omni_ready          = false
    talos_image_ocid    = "ocid1.image.oc1.uk-london-1.talos-test"
    omni_machine_config = null
    tailscale_auth_key  = "tskey-auth-test" # pragma: allowlist secret
  }

  assert {
    condition     = can(base64decode(oci_core_instance.ampere_instance[0].metadata["user_data"]))
    error_message = "Expected tailnet-only Talos mode to set base64 user_data"
  }

  assert {
    condition     = strcontains(base64decode(oci_core_instance.ampere_instance[0].metadata["user_data"]), "kind: ExtensionServiceConfig")
    error_message = "Expected tailnet-only Talos mode to include Tailscale ExtensionServiceConfig"
  }

  assert {
    condition     = strcontains(base64decode(oci_core_instance.ampere_instance[0].metadata["user_data"]), "TS_AUTHKEY=tskey-auth-test")
    error_message = "Expected tailnet-only Talos mode to pass Tailscale auth key"
  }

  assert {
    condition     = !strcontains(base64decode(oci_core_instance.ampere_instance[0].metadata["user_data"]), "kind: SideroLinkConfig")
    error_message = "Expected tailnet-only Talos mode to omit Omni SideroLinkConfig"
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

# --- omni_ready = true without omni_machine_config fails prerequisite check ---
run "omni_ready_without_machine_config_fails" {
  command = plan

  variables {
    omni_machine_config = null
  }

  expect_failures = [
    check.omni_ready_requires_machine_config,
  ]
}

# --- omni_ready = true without tailscale_auth_key fails prerequisite check ---
run "omni_ready_without_tailscale_key_fails" {
  command = plan

  variables {
    tailscale_auth_key = null # pragma: allowlist secret
  }

  expect_failures = [
    check.omni_ready_requires_tailscale_key,
  ]
}

# --- per-node VPN subnet requires OCI VPN resources ---
run "vpn_subnet_without_oci_vpn_fails" {
  command = plan

  variables {
    ampere_nodes = [
      { name = "oci-talos-cp-1", ocpus = 1, memory_gb = 6, boot_vol_gb = 50, vpn_subnet = true },
      { name = "oci-talos-worker-1", ocpus = 1, memory_gb = 6, boot_vol_gb = 50 },
    ]
  }

  expect_failures = [
    check.ampere_vpn_subnet_requires_oci_vpn,
  ]
}
