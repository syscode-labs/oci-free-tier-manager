# Test: Partial override behaviour on Always Free accounts
#
# Verifies that omitted node fields fall back to the defaults,
# and that users can mix custom and default values freely.

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
  mock_resource "oci_load_balancer_load_balancer" {
    defaults = { id = "ocid1.lb.test" }
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

# --- Empty {} per node uses defaults ---
run "empty_objects_use_defaults" {
  command = plan

  variables {
    ampere_nodes = [{}, {}]
  }

  assert {
    condition     = local._ampere_nodes[0].ocpus == 1
    error_message = "Expected 1 OCPU (default) for empty node, got ${local._ampere_nodes[0].ocpus}"
  }

  assert {
    condition     = local._ampere_nodes[0].memory_gb == 6
    error_message = "Expected 6 GB RAM (default) for empty node"
  }

  assert {
    condition     = local._ampere_nodes[0].boot_vol_gb == 50
    error_message = "Expected 50 GB boot volume (default) for empty node"
  }
}

# --- Override only name; other fields use defaults ---
run "override_name_only" {
  command = plan

  variables {
    ampere_nodes = [
      { name = "k8s-cp" },
      { name = "k8s-w1" },
    ]
    micro_nodes = [] # suppress micro to simplify test
  }

  assert {
    condition     = local._ampere_nodes[0].name == "k8s-cp"
    error_message = "Expected node name 'k8s-cp'"
  }

  assert {
    condition     = local._ampere_nodes[0].ocpus == 1
    error_message = "Expected default 1 OCPU when only name is overridden"
  }

  assert {
    condition     = local._ampere_nodes[1].name == "k8s-w1"
    error_message = "Expected node name 'k8s-w1'"
  }
}

# --- Override only boot volume; OCPUs/RAM use defaults ---
run "override_boot_vol_only" {
  command = plan

  variables {
    ampere_nodes = [{ boot_vol_gb = 100 }]
    micro_nodes  = []
  }

  assert {
    condition     = local._ampere_nodes[0].boot_vol_gb == 100
    error_message = "Expected overridden boot_vol_gb of 100"
  }

  assert {
    condition     = local._ampere_nodes[0].ocpus == 1
    error_message = "Expected default 1 OCPU when only boot_vol_gb overridden"
  }

  assert {
    condition     = local._ampere_nodes[0].memory_gb == 6
    error_message = "Expected default 6 GB RAM when only boot_vol_gb overridden"
  }
}

# --- Mixed node sizes within budget ---
run "mixed_sizes_within_budget" {
  command = plan

  variables {
    ampere_nodes = [
      { name = "k8s-cp", ocpus = 1, memory_gb = 6, boot_vol_gb = 60 },
      { name = "k8s-w1", ocpus = 1, memory_gb = 6, boot_vol_gb = 60 },
    ]
    micro_nodes = []
  }

  assert {
    condition     = local.total_ocpus == 2
    error_message = "Expected 2 total OCPUs"
  }

  assert {
    condition     = local.total_ram_gb == 12
    error_message = "Expected 12 GB total RAM"
  }

  assert {
    condition     = local.total_storage_gb == 120
    error_message = "Expected 120 GB total storage (2 × 60 GB)"
  }
}

# --- Micro node with custom boot volume ---
run "micro_custom_boot_vol" {
  command = plan

  variables {
    ampere_nodes = [{ ocpus = 1, memory_gb = 8 }]
    micro_nodes  = [{ name = "bastion", boot_vol_gb = 50 }]
  }

  assert {
    condition     = local._micro_nodes[0].boot_vol_gb == 50
    error_message = "Expected micro boot_vol_gb of 50"
  }

  assert {
    condition     = local._micro_nodes[0].name == "bastion"
    error_message = "Expected micro name 'bastion'"
  }
}

# --- Micro node with empty {} uses defaults ---
run "micro_empty_object_uses_defaults" {
  command = plan

  variables {
    ampere_nodes = [{ ocpus = 1, memory_gb = 8 }]
    micro_nodes  = [{}]
  }

  assert {
    condition     = local._micro_nodes[0].boot_vol_gb == 50
    error_message = "Expected default 50 GB boot volume for empty micro node"
  }

  assert {
    condition     = local._micro_nodes[0].name == "micro-instance-1"
    error_message = "Expected auto-generated name 'micro-instance-1'"
  }
}

# --- micro_nodes = [] explicitly → 0 nodes ---
run "explicit_empty_micro" {
  command = plan

  variables {
    ampere_nodes = [{}, {}]
    micro_nodes  = []
  }

  assert {
    condition     = length(local._micro_nodes) == 0
    error_message = "Expected 0 micro nodes when micro_nodes = []"
  }
}

# --- Two micro nodes (max = 2 free instances) ---
run "two_micro_nodes" {
  command = plan

  variables {
    ampere_nodes = [{ ocpus = 1, memory_gb = 8, boot_vol_gb = 50 }]
    micro_nodes  = [{ name = "bastion-1" }, { name = "bastion-2" }]
  }

  assert {
    condition     = length(local._micro_nodes) == 2
    error_message = "Expected 2 micro nodes"
  }

  assert {
    condition     = local._micro_nodes[1].name == "bastion-2"
    error_message = "Expected name 'bastion-2' for second micro node"
  }
}

# --- Load balancer created when load_balancer = {} ---
run "load_balancer_created" {
  command = plan

  variables {
    ampere_nodes  = [{ ocpus = 1, memory_gb = 6 }]
    micro_nodes   = []
    load_balancer = {}
  }

  assert {
    condition     = length(oci_load_balancer_load_balancer.free_tier_lb) == 1
    error_message = "Expected 1 LB when load_balancer = {}"
  }

  assert {
    condition     = var.load_balancer.bandwidth_mbps == 10
    error_message = "Expected default bandwidth_mbps of 10"
  }
}

# --- Load balancer NOT created when load_balancer = null ---
run "load_balancer_not_created" {
  command = plan

  variables {
    ampere_nodes  = [{ ocpus = 1, memory_gb = 6 }]
    micro_nodes   = []
    load_balancer = null
  }

  assert {
    condition     = length(oci_load_balancer_load_balancer.free_tier_lb) == 0
    error_message = "Expected 0 LBs when load_balancer = null"
  }
}

# --- Load balancer with explicit bandwidth ---
run "load_balancer_explicit_10mbps" {
  command = plan

  variables {
    ampere_nodes = [{ ocpus = 1, memory_gb = 6 }]
    micro_nodes  = []
    load_balancer = {
      shape          = "flexible"
      bandwidth_mbps = 10
    }
  }

  assert {
    condition     = var.load_balancer.bandwidth_mbps == 10
    error_message = "Expected bandwidth_mbps == 10"
  }

  assert {
    condition     = var.load_balancer.shape == "flexible"
    error_message = "Expected shape == 'flexible'"
  }
}

# --- Ingress reserved IP created only when explicitly enabled ---
run "ingress_ip_created_when_enabled" {
  command = plan

  variables {
    ampere_nodes      = [{ ocpus = 1, memory_gb = 6 }]
    micro_nodes       = []
    create_ingress_ip = true
  }

  assert {
    condition     = length(oci_core_public_ip.ingress) == 1
    error_message = "Expected 1 ingress reserved IP when create_ingress_ip = true"
  }
}
