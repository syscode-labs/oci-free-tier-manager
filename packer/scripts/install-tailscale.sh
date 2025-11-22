#!/bin/bash
set -euo pipefail

# Install Tailscale
# Official installation script from Tailscale

echo "Installing Tailscale..."

# Add Tailscale's package signing key and repository
curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | \
    tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null

curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | \
    tee /etc/apt/sources.list.d/tailscale.list

# Install Tailscale
apt-get update
apt-get install -y tailscale

# Enable but don't start Tailscale (will be configured post-deployment)
systemctl enable tailscaled

echo "✓ Tailscale installed"
