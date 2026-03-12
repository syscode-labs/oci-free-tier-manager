#!/bin/bash
set -euo pipefail

# Install Proxmox VE on Debian 12 ARM64 (aarch64)
#
# Runs on real Debian 12 (inside QEMU during GitHub Actions CI build).
# Uses PXVIRT — the Proxmox ARM64 unofficial port (formerly mirrors.apqa.cn).
# See: https://github.com/jiangcuo/pxvirt

echo "==> Installing Proxmox VE (ARM64 PXVIRT port) on Debian 12..."

# Fix /etc/hosts: Proxmox installer needs hostname to resolve to a non-loopback IP.
PVE_HOSTNAME=$(hostname -s)
HOST_IP=$(hostname -I | awk '{print $1}')
if ! grep -q "^${HOST_IP}" /etc/hosts; then
  echo "${HOST_IP} ${PVE_HOSTNAME}.proxmox.local ${PVE_HOSTNAME}" >> /etc/hosts
fi

# Enable IP forwarding (required for Proxmox bridge and container networking)
cat > /etc/sysctl.d/99-proxmox-forwarding.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl -p /etc/sysctl.d/99-proxmox-forwarding.conf

# Add PXVIRT ARM64 repository (successor to Proxmox-Port / mirrors.apqa.cn)
curl -fsSL https://mirrors.lierfang.com/pxcloud/lierfang.gpg \
  -o /etc/apt/trusted.gpg.d/lierfang.gpg

echo "deb [arch=arm64 signed-by=/etc/apt/trusted.gpg.d/lierfang.gpg] https://mirrors.lierfang.com/pxcloud/pxvirt bookworm main" \
  > /etc/apt/sources.list.d/pve-install-repo.list

# Update package lists
apt-get update

# Install Proxmox VE kernel first (boots into it on OCI instance launch)
# PXVIRT provides pve-kernel-6.12-pve for ARM64
DEBIAN_FRONTEND=noninteractive apt-get install -y pve-kernel-6.12-pve

# Install Proxmox VE and dependencies
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  proxmox-ve \
  postfix \
  open-iscsi \
  chrony \
  ifupdown2

# Remove Debian kernel to avoid GRUB conflicts
# Proxmox boot-tool manages kernels from this point forward
DEBIAN_FRONTEND=noninteractive apt-get remove -y \
  "linux-image-arm64" \
  "linux-image-6.*" || true
update-grub || proxmox-boot-tool refresh || true

# Configure chrony for time sync (Proxmox clusters are time-sensitive)
systemctl enable chrony
systemctl start chrony || true

echo "==> Proxmox VE (ARM64 PXVIRT) installed successfully"
echo "==> NOTE: Instance will boot into pve-kernel on next launch"
