/*
 * VPN subnet probe - instance on golden Micro image.
 *
 * Disabled by default. Use targeted workflow dispatch with
 * enable_oci_vpn_probe=true to create it, then targeted destroy to remove it.
 * Creates a Micro instance in VPN subnet with NFS export and optional NixOS
 * pivot capability. Uses the pre-baked golden image (base OS + hardening);
 * cloud-init handles Layer 3 instance-specific config only.
 */

locals {
  vpn_probe_enabled = local.vpn_enabled && var.enable_oci_vpn_probe

  # Prefer pre-baked golden image (Layer 1+2: base OS + common hardening).
  # Falls back to latest Ubuntu 24.04 Minimal + full cloud-init if not set.
  vpn_probe_image_id = var.vpn_probe_golden_image_ocid != null ? var.vpn_probe_golden_image_ocid : local.micro_image_id

  # Layer 3 only: instance-specific config. Golden image provides base OS,
  # sysctl hardening, SSH hardening, fail2ban, auditd, UFW defaults,
  # nfs-kernel-server, and unattended-upgrades.
  _vpn_probe_cloud_init = <<-EOT
    #cloud-config
    # vim: set ft=yaml:

    # ── Users / SSH key injection (via OCI metadata) ─────────────────
    ssh_pwauth: false
    users:
      - name: ubuntu
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/bash
        lock_passwd: true

    # ── Instance-specific files ──────────────────────────────────────
    write_files:
      # NFS exports for this instance
      - path: /etc/exports
        permissions: "0644"
        content: |
          /export REDACTED_PRIVATE_SUBNET(rw,sync,no_subtree_check,no_root_squash)
          /export 10.0.0.0/8(rw,sync,no_subtree_check,no_root_squash)

      # Systemd service for creating export directory
      - path: /etc/systemd/system/create-nfs-export.service
        permissions: "0644"
        content: |
          [Unit]
          Description=Create NFS export directory
          Before=nfs-server.service
          Requires=nfs-server.service

          [Service]
          Type=oneshot
          ExecStart=/bin/mkdir -p /export
          ExecStart=/bin/chmod 777 /export
          ExecStart=/bin/chown nobody:nogroup /export
          RemainAfterExit=yes

          [Install]
          WantedBy=multi-user.target

      # NixOS anywhere installer script (for optional pivot)
      - path: /usr/local/bin/nixos-pivot.sh
        permissions: "0755"
        content: |
          #!/bin/bash
          set -euo pipefail

          # Usage: nixos-pivot.sh <flake-url> [target-host]
          # Example: nixos-pivot.sh github:myorg/nixos-config#oci-micro

          FLAKE_URL="$${1:-}"
          TARGET_HOST="$${2:-localhost}"

          if [[ -z "$${FLAKE_URL}" ]]; then
            echo "Usage: $0 <flake-url> [target-host]"
            echo "Example: $0 github:myorg/nixos-config#oci-micro"
            exit 1
          fi

          echo "Installing nixos-anywhere dependencies..."
          apt-get update && apt-get install -y --no-install-recommends \
            curl gnupg ca-certificates

          echo "Installing nix..."
          curl -L https://nixos.org/nix/install | sh -s -- --daemon
          source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

          echo "Installing nixos-anywhere..."
          nix profile install nixpkgs#nixos-anywhere

          echo "Pivoting to NixOS with flake: $${FLAKE_URL}"
          nixos-anywhere --flake "$${FLAKE_URL}" --target-host "root@$${TARGET_HOST}" \
            --extra-files /etc/ssh/ssh_host_ed25519_key=/etc/ssh/ssh_host_ed25519_key \
            --extra-files /etc/ssh/ssh_host_ed25519_key.pub=/etc/ssh/ssh_host_ed25519_key.pub \
            --extra-files /etc/ssh/ssh_host_rsa_key=/etc/ssh/ssh_host_rsa_key \
            --extra-files /etc/ssh/ssh_host_rsa_key.pub=/etc/ssh/ssh_host_rsa_key.pub \
            --generate-hardware-config nixos-generate-config \
            --ssh-option "UserKnownHostsFile=/dev/null" \
            --ssh-option "StrictHostKeyChecking=no"

          echo "NixOS pivot complete. Rebooting..."
          reboot

      # Probe test script (original functionality)
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
          getent hosts omni.REDACTED_TAILNET_DOMAIN
          echo "DNS_STATUS:$?"

          echo "# tcp 8090"
          timeout 15 bash -c 'cat < /dev/null > /dev/tcp/REDACTED-OMNI-TARGET-IP/8090'
          echo "TCP_8090_STATUS:$?"

          echo "# tls 8090"
          timeout 20 openssl s_client \
            -connect omni.REDACTED_TAILNET_DOMAIN:8090 \
            -servername omni.REDACTED_TAILNET_DOMAIN \
            -verify_return_error < /dev/null
          echo "TLS_8090_STATUS:$?"

          echo "# udp 50180 send"
          timeout 5 bash -c 'printf "oci-vpn-probe" > /dev/udp/REDACTED-OMNI-TARGET-IP/50180'
          echo "UDP_50180_SEND_STATUS:$?"

          echo "OCI_VPN_PROBE_END $(date -Is)"

    # ── Runcmd (instance setup; packages/hardening already baked) ───
    runcmd:
      # Create export directory
      - [ mkdir, -p, /export ]
      - [ chmod, 777, /export ]
      - [ chown, nobody:nogroup, /export ]

      # Enable and start NFS
      - [ systemctl, daemon-reload ]
      - [ systemctl, enable, --now, create-nfs-export.service ]
      - [ systemctl, enable, --now, nfs-server ]
      - [ exportfs, -ra ]

      # Instance-specific firewall rules (defaults baked into image)
      - [ ufw, allow, from, REDACTED_PRIVATE_SUBNET, to, any, port, 22, proto, tcp ]  # SSH from VPN subnet
      - [ ufw, allow, from, REDACTED_PRIVATE_SUBNET, to, any, port, 2049, proto, tcp ] # NFS from VPN subnet
      - [ ufw, allow, from, REDACTED_PRIVATE_SUBNET, to, any, port, 2049, proto, udp ] # NFS from VPN subnet
      - [ ufw, allow, from, REDACTED_PRIVATE_SUBNET, to, any, port, 111, proto, tcp ]  # rpcbind
      - [ ufw, allow, from, REDACTED_PRIVATE_SUBNET, to, any, port, 111, proto, udp ]  # rpcbind
      - [ ufw, allow, from, REDACTED-OMNI-TARGET-IP, to, any ]  # Omni

      # Run probe test
      - [ /usr/local/bin/oci-vpn-probe.sh ]

      # Log completion
      - [ bash, -c, 'echo "OCI_VPN_PROBE_GOLDEN_COMPLETE $(date -Is)" >> /var/log/oci-vpn-probe.log' ]

    # ── Final message ─────────────────────────────────────────────────
    final_message: |
      OCI VPN Probe (golden image) ready.
      NFS export available at /export (REDACTED_PRIVATE_SUBNET + 10.0.0.0/8)
      Run /usr/local/bin/nixos-pivot.sh <flake-url> to pivot to NixOS.
      Probe test results in /var/log/oci-vpn-probe.log
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
    source_id               = local.vpn_probe_image_id
    boot_volume_size_in_gbs = 50
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.vpn_subnet[0].id
    assign_public_ip = false
    display_name     = "oci-vpn-probe-vnic"
  }

  metadata = {
    user_data           = base64encode(local._vpn_probe_cloud_init)
    ssh_authorized_keys = var.ssh_public_key != null ? var.ssh_public_key : ""
  }
}
