/*
 * Temporary data-plane probe for the OCI -> OpenWrt -> Omni VPN path.
 *
 * Disabled by default. Use targeted workflow dispatch with
 * enable_oci_vpn_probe=true to create it, then targeted destroy to remove it.
 * The instance has no public IP and prints probe output to OCI console history.
 */

locals {
  vpn_probe_enabled = local.vpn_enabled && var.enable_oci_vpn_probe

  _vpn_probe_cloud_init = <<-EOT
    #cloud-config
    output:
      all: "| tee -a /var/log/cloud-init-output.log /dev/console"
    write_files:
      - path: /usr/local/bin/oci-vpn-probe.sh
        permissions: "0755"
        content: |
          #!/usr/bin/env bash
          set +e
          exec > >(tee -a /var/log/oci-vpn-probe.log /dev/console) 2>&1

          echo "OCI_VPN_PROBE_START $(date -Is)"
          echo "# addresses"
          ip -4 addr show
          echo "# routes"
          ip route
          echo "# resolv.conf"
          cat /etc/resolv.conf

          echo "# dns"
          getent hosts omni.wind-bearded.ts.net
          echo "DNS_STATUS:$?"

          echo "# tcp 443"
          timeout 15 bash -c 'cat < /dev/null > /dev/tcp/100.72.134.50/443'
          echo "TCP_443_STATUS:$?"

          echo "# tls 443"
          timeout 20 openssl s_client \
            -connect omni.wind-bearded.ts.net:443 \
            -servername omni.wind-bearded.ts.net \
            -verify_return_error < /dev/null
          echo "TLS_443_STATUS:$?"

          echo "# udp 50180 send"
          timeout 5 bash -c 'printf "oci-vpn-probe" > /dev/udp/100.72.134.50/50180'
          echo "UDP_50180_SEND_STATUS:$?"

          echo "OCI_VPN_PROBE_END $(date -Is)"
    runcmd:
      - [ /usr/local/bin/oci-vpn-probe.sh ]
  EOT
}

resource "oci_core_instance" "vpn_probe" {
  count               = local.vpn_probe_enabled ? 1 : 0
  availability_domain = var.micro_availability_domain
  compartment_id      = local.compartment_id
  display_name        = "oci-vpn-probe"
  shape               = "VM.Standard.E2.1.Micro"

  source_details {
    source_type             = "image"
    source_id               = local.micro_image_id
    boot_volume_size_in_gbs = 50
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.vpn_subnet[0].id
    assign_public_ip = false
    display_name     = "oci-vpn-probe-vnic"
  }

  metadata = {
    user_data = base64encode(local._vpn_probe_cloud_init)
  }
}
