#!/bin/bash
set -euo pipefail

# Install Proxmox VE on Debian 12 ARM64 (aarch64)
#
# Uses the unofficial ARM64 port maintained at mirrors.apqa.cn
# Official Proxmox packages are amd64-only; this port is community-maintained.
# See: https://github.com/jiangcuo/Proxmox-Port

echo "==> Installing Proxmox VE (ARM64 unofficial port) on Debian 12..."

# Fix /etc/hosts: Proxmox installer needs hostname to resolve to a non-loopback IP.
# On OCI the instance hostname resolves via DHCP; add an explicit entry.
HOSTNAME=$(hostname -s)
HOST_IP=$(hostname -I | awk '{print $1}')
if ! grep -q "^${HOST_IP}" /etc/hosts; then
  echo "${HOST_IP} ${HOSTNAME}.proxmox.local ${HOSTNAME}" >> /etc/hosts
fi

# Enable IP forwarding (required for Proxmox bridge and container networking).
# Overrides the restrictive sysctl set by the base image hardening script.
cat > /etc/sysctl.d/99-proxmox-forwarding.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl -p /etc/sysctl.d/99-proxmox-forwarding.conf

# Add the ARM64 Proxmox port repository
echo "deb [arch=arm64] https://mirrors.apqa.cn/proxmox/debian/pve bookworm port" \
  > /etc/apt/sources.list.d/pve-install-repo.list

# Import the repository GPG key
curl -fsSL https://mirrors.apqa.cn/proxmox/debian/proxmox-port-release.gpg \
  -o /etc/apt/trusted.gpg.d/proxmox-port-release.gpg

# Update package lists
apt-get update

# Install Proxmox VE kernel first (boot into it on first OCI instance launch)
DEBIAN_FRONTEND=noninteractive apt-get install -y pve-kernel-6.8

# Install Proxmox VE and dependencies
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  proxmox-ve \
  postfix \
  open-iscsi \
  chrony \
  ifupdown2

# Remove the Debian kernel to avoid GRUB conflicts
# Proxmox boot-tool manages kernels from this point forward
apt-get remove -y "linux-image-arm64" "linux-image-6.1*" || true
update-grub || proxmox-boot-tool refresh || true

# Configure chrony for time sync (Proxmox clusters are time-sensitive)
systemctl enable chrony
systemctl start chrony || true

echo "==> Proxmox VE (ARM64) installed successfully"
echo "==> NOTE: Instance must reboot into pve-kernel before Proxmox web UI is available"
