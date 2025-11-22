#!/bin/bash
set -euo pipefail

# Install Proxmox VE on Debian 12
# Official Proxmox installation on Debian

echo "Installing Proxmox VE..."

# Add Proxmox VE repository
echo "deb [arch=amd64] http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list

# Add Proxmox VE repository key
wget https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg

# Update package lists
apt-get update

# Install Proxmox VE kernel and packages
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    proxmox-ve \
    postfix \
    open-iscsi \
    ifupdown2

# Remove Debian kernel (keep Proxmox kernel only)
apt-get remove -y linux-image-amd64 'linux-image-6.1*' || true

# Update GRUB
update-grub

echo "✓ Proxmox VE installed"
