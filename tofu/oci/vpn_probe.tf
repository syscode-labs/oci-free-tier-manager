/*
 * Temporary data-plane probe for the OCI -> OpenWrt -> Omni VPN path.
 *
 * Disabled by default. Use targeted workflow dispatch with
 * enable_oci_vpn_probe=true to create it, then targeted destroy to remove it.
 * The instance has no public IP and prints probe output to OCI console history.
 *
 * This version uses Ubuntu 24.04 Minimal, hardens the system, sets up NFS export,
 * and optionally pivots to NixOS via nixos-anywhere.
 */

locals {
  vpn_probe_enabled = local.vpn_enabled && var.enable_oci_vpn_probe

  _vpn_probe_cloud_init = <<-EOT
    #cloud-config
    # vim: set ft=yaml:
    
    # ── System hardening ──────────────────────────────────────────────
    # Remove snapd (not needed, saves RAM/disk)
    package_update: true
    package_upgrade: true
    packages:
      - nfs-kernel-server
      - curl
      - gnupg
      - ca-certificates
      - iptables-persistent
      - fail2ban
      - auditd
      - logrotate
      - unattended-upgrades
    package_reboot_if_required: true

    # Remove unnecessary packages
    apt:
      purge:
        - snapd
        - lxd
        - lxd-client
        - popularity-contest
        - command-not-found
        - friendly-recovery

    # ── SSH hardening ─────────────────────────────────────────────────
    ssh_pwauth: false
    ssh_deletekeys: true
    ssh_genkeytypes: ["ed25519", "rsa"]
    disable_root: true

    # ── Users ─────────────────────────────────────────────────────────
    users:
      - name: ubuntu
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/bash
        lock_passwd: true
        # SSH key injected via OCI metadata ssh_authorized_keys field

    # ── Kernel params / sysctl hardening ──────────────────────────────
    write_files:
      # sysctl hardening
      - path: /etc/sysctl.d/99-hardening.conf
        permissions: "0644"
        content: |
          # Network hardening
          net.ipv4.conf.all.accept_redirects = 0
          net.ipv4.conf.default.accept_redirects = 0
          net.ipv4.conf.all.secure_redirects = 0
          net.ipv4.conf.default.secure_redirects = 0
          net.ipv4.conf.all.send_redirects = 0
          net.ipv4.conf.all.accept_source_route = 0
          net.ipv4.conf.default.accept_source_route = 0
          net.ipv4.conf.all.log_martians = 1
          net.ipv4.conf.default.log_martians = 1
          net.ipv4.icmp_echo_ignore_broadcasts = 1
          net.ipv4.icmp_ignore_bogus_error_responses = 1
          net.ipv4.tcp_syncookies = 1
          net.ipv4.tcp_max_syn_backlog = 2048
          net.ipv4.tcp_synack_retries = 2
          net.ipv4.tcp_syn_retries = 5
          net.ipv6.conf.all.accept_redirects = 0
          net.ipv6.conf.default.accept_redirects = 0
          net.ipv6.conf.all.accept_source_route = 0
          net.ipv6.conf.default.accept_source_route = 0
          
          # Kernel hardening
          kernel.kptr_restrict = 2
          kernel.dmesg_restrict = 1
          kernel.yama.ptrace_scope = 1
          vm.mmap_min_addr = 65536
          fs.suid_dumpable = 0
          
          # Memory protection
          vm.unprivileged_userfaultfd = 0

      # Unattended upgrades config
      - path: /etc/apt/apt.conf.d/50unattended-upgrades
        permissions: "0644"
        content: |
          Unattended-Upgrade::Allowed-Origins {
            "$${distro_id}:$${distro_codename}";
            "$${distro_id}:$${distro_codename}-security";
            "$${distro_id}ESMApps:$${distro_codename}-apps-security";
            "$${distro_id}ESM:$${distro_codename}-infra-security";
          };
          Unattended-Upgrade::AutoFixInterruptedDpkg "true";
          Unattended-Upgrade::MinimalSteps "true";
          Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
          Unattended-Upgrade::Remove-Unused-Dependencies "true";
          Unattended-Upgrade::Automatic-Reboot "true";
          Unattended-Upgrade::Automatic-Reboot-Time "04:00";

      - path: /etc/apt/apt.conf.d/20auto-upgrades
        permissions: "0644"
        content: |
          APT::Periodic::Update-Package-Lists "1";
          APT::Periodic::Download-Upgradeable-Packages "1";
          APT::Periodic::AutocleanInterval "7";
          APT::Periodic::Unattended-Upgrade "1";

      # Fail2ban config
      - path: /etc/fail2ban/jail.local
        permissions: "0644"
        content: |
          [DEFAULT]
          bantime = 3600
          findtime = 600
          maxretry = 3
          backend = systemd
          
          [sshd]
          enabled = true
          port = ssh
          filter = sshd
          logpath = %(sshd_log)s
          maxretry = 3

      # NFS exports
      - path: /etc/exports
        permissions: "0644"
        content: |
          /export REDACTED_PRIVATE_SUBNET(rw,sync,no_subtree_check,no_root_squash)
          /export 10.0.0.0/8(rw,sync,no_subtree_check,no_root_squash)

      # NFS kernel server config
      - path: /etc/default/nfs-kernel-server
        permissions: "0644"
        content: |
          RPCNFSDCOUNT=4
          RPCNFSDPRIORITY=0
          RPCMOUNTDOPTS="--manage-gids"
          NEED_SVCGSSD="no"

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

    # ── Boot cmd (runs early) ─────────────────────────────────────────
    bootcmd:
      # Apply sysctl immediately
      - [ sysctl, --system ]
      # Disable snapd socket
      - [ systemctl, disable, --now, snapd.socket ]
      - [ systemctl, mask, snapd.socket ]

    # ── Runcmd (runs late, after packages) ────────────────────────────
    runcmd:
      # Create export directory
      - [ mkdir, -p, /export ]
      - [ chmod, 777, /export ]
      - [ chown, nobody:nogroup, /export ]
      
      # Enable and start services
      - [ systemctl, daemon-reload ]
      - [ systemctl, enable, --now, nfs-server ]
      - [ systemctl, enable, --now, create-nfs-export.service ]
      - [ systemctl, enable, --now, fail2ban ]
      - [ systemctl, enable, --now, auditd ]
      - [ systemctl, enable, --now, unattended-upgrades ]
      
      # Configure firewall (UFW)
      - [ ufw, --force, enable ]
      - [ ufw, default, deny, incoming ]
      - [ ufw, default, allow, outgoing ]
      - [ ufw, allow, from, REDACTED_PRIVATE_SUBNET, to, any, port, 22, proto, tcp ]  # SSH from VPN subnet
      - [ ufw, allow, from, REDACTED_PRIVATE_SUBNET, to, any, port, 2049, proto, tcp ] # NFS from VPN subnet
      - [ ufw, allow, from, REDACTED_PRIVATE_SUBNET, to, any, port, 2049, proto, udp ] # NFS from VPN subnet
      - [ ufw, allow, from, REDACTED_PRIVATE_SUBNET, to, any, port, 111, proto, tcp ]  # rpcbind
      - [ ufw, allow, from, REDACTED_PRIVATE_SUBNET, to, any, port, 111, proto, udp ]  # rpcbind
      - [ ufw, allow, from, REDACTED-OMNI-TARGET-IP, to, any ]  # Omni
      
      # Run original probe test
      - [ /usr/local/bin/oci-vpn-probe.sh ]
      
      # Log completion
      - [ bash, -c, 'echo "OCI_VPN_PROBE_HARDENED_COMPLETE $(date -Is)" >> /var/log/oci-vpn-probe.log' ]

    # ── Final message ─────────────────────────────────────────────────
    final_message: |
      OCI VPN Probe (Ubuntu 24.04 Minimal) hardened and ready.
      NFS export available at /export (REDACTED_PRIVATE_SUBNET + 10.0.0.0/8)
      SSH hardened (key-only, fail2ban, UFW)
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
    source_id               = local.micro_image_id
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