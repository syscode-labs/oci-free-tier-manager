mock_provider "cloudflare" {}

mock_provider "oci" {
  mock_data "oci_core_images" {
    defaults = {
      images = [{
        id                       = "ocid1.image.test.micro"
        display_name             = "Canonical-Ubuntu-24.04-Minimal-2026.01.01-0"
        operating_system         = "Canonical Ubuntu"
        operating_system_version = "24.04"
        time_created             = "2026-01-01T00:00:00.000Z"
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
      }]
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
  mock_resource "oci_core_public_ip" {
    defaults = { id = "ocid1.publicip.test", ip_address = "141.147.87.29" }
  }
  mock_data "oci_core_private_ips" {
    defaults = {
      private_ips = [{ id = "ocid1.privateip.test", ip_address = "10.0.1.10" }]
    }
  }
}

variables {
  cloudflare_zone_id             = "test-cloudflare-zone-id"
  compartment_ocid               = "ocid1.compartment.test"
  tenancy_ocid                   = "ocid1.tenancy.test"
  budget_alert_email             = "test@example.com"
  ssh_public_key                 = "ssh-ed25519 AAAATEST fixture"
  home_cpe_public_ip             = "203.0.113.10"
  cpe_local_identifier           = "192.0.2.10"
  omni_target_ip                 = "100.64.0.1"
  tailnet_dns_resolver           = "100.100.100.100"
  omni_search_domain             = "example.invalid"
  ddns_hostname                  = "home.example.invalid"
  cpe_recreate_fn_push_user_ocid = "ocid1.user.test"
  ampere_nodes                   = []
  micro_nodes                    = []
  create_budget                  = false
  create_bastion                 = true
  write_packer_vars              = false
}

run "cloudflare_bastion_record" {
  command = plan

  assert {
    condition     = cloudflare_dns_record.bastion[0].name == "bastion.syscode-lab.oci.syscode.uk"
    error_message = "Cloudflare must serve the existing bastion hostname."
  }

  assert {
    condition     = cloudflare_dns_record.bastion[0].content == "141.147.87.29"
    error_message = "Cloudflare must point the bastion hostname at its reserved public IP."
  }

  assert {
    condition     = cloudflare_dns_record.bastion[0].proxied == false
    error_message = "The SSH bastion record must remain DNS-only."
  }
}
