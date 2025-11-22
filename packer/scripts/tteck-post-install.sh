#!/bin/bash
set -euo pipefail

# Run tteck/Proxmox helper scripts
# Post-PVE-Install script: Disables enterprise repo, removes subscription nag

echo "Running Proxmox post-install optimizations..."

# Post-PVE-Install script (mandatory)
bash <(wget -qLO - https://github.com/tteck/Proxmox/raw/main/misc/post-pve-install.sh) <<EOF
y
EOF

# Install processor microcode (recommended for ARM/AMD)
bash <(wget -qLO - https://github.com/tteck/Proxmox/raw/main/misc/microcode.sh) <<EOF
y
EOF

# Kernel cleanup (optional, saves space)
bash <(wget -qLO - https://github.com/tteck/Proxmox/raw/main/misc/kernel-clean.sh) <<EOF
y
EOF

echo "✓ Proxmox post-install complete"
