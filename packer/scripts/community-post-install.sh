#!/bin/bash
set -euo pipefail

# Proxmox post-install hardening (non-interactive)
#
# Replicates the key steps from community-scripts/ProxmoxVE post-pve-install.sh
# without interactive prompts. Safe to run in Packer builds.
# Source: https://github.com/community-scripts/ProxmoxVE/blob/main/tools/pve/post-pve-install.sh

echo "==> Running Proxmox community post-install hardening..."

# Disable command-not-found apt hook (fails on Ubuntu 22.04 ARM64)
rm -f /etc/apt/apt.conf.d/50command-not-found || true

# 1. Disable enterprise subscription repository (requires paid sub)
if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
  sed -i 's|^deb|#deb|' /etc/apt/sources.list.d/pve-enterprise.list
  echo "    Disabled pve-enterprise.list"
fi

# Disable enterprise repo in deb822 format (PVE 9.x)
if [ -f /etc/apt/sources.list.d/pve-enterprise.sources ]; then
  sed -i 's/^Enabled: yes/Enabled: no/' /etc/apt/sources.list.d/pve-enterprise.sources
fi

# 2. Verify PXVIRT no-sub repository is present (added by install-proxmox.sh)
# PXVIRT is the successor to the Proxmox-Port ARM64 project (formerly mirrors.apqa.cn)
if ! grep -rq "lierfang.com\|pxvirt" /etc/apt/sources.list.d/ 2>/dev/null; then
  echo "deb [arch=arm64 signed-by=/etc/apt/trusted.gpg.d/lierfang.gpg] https://mirrors.lierfang.com/pxcloud/pxvirt bookworm main" \
    > /etc/apt/sources.list.d/pve-install-repo.list
fi

# 3. Ceph packages — use Ubuntu's native Ceph packages (no separate ARM64 Ceph repo needed)
# Ubuntu 22.04 ships Ceph Quincy (17.x) which is compatible with Proxmox VE
echo "    Using Ubuntu native Ceph packages (no separate Ceph repo needed)"

# 4. Remove subscription nag from Proxmox web UI
# Patches proxmoxlib.js to suppress the no-subscription popup
PROXMOX_JS_PATH=$(find /usr/share/javascript/proxmox-widget-toolkit -name 'proxmoxlib.js' 2>/dev/null | head -1)
if [ -n "$PROXMOX_JS_PATH" ]; then
  cp "$PROXMOX_JS_PATH" "${PROXMOX_JS_PATH}.bak"
  # Suppress the "You do not have a valid subscription" dialog
  sed -i "s/Ext.Msg.show({/void({/g; s/data.status !== 'Active'/false/g" "$PROXMOX_JS_PATH"
  echo "    Subscription nag removed from $PROXMOX_JS_PATH"
fi

# Also patch mobile UI if present
MOBILE_JS=$(find /usr/share/pve-manager -name 'mobile.js' 2>/dev/null | head -1)
if [ -n "$MOBILE_JS" ]; then
  sed -i "s/Ext.Msg.show({/void({/g" "$MOBILE_JS"
fi

# 5. Full system upgrade
apt-get update || true
DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y

# 6. Reinstall proxmox-widget-toolkit to ensure consistent state post-patch
DEBIAN_FRONTEND=noninteractive apt-get install --reinstall -y proxmox-widget-toolkit 2>/dev/null || true

# Re-apply the nag patch (reinstall may have reverted it)
if [ -n "${PROXMOX_JS_PATH:-}" ] && [ -f "$PROXMOX_JS_PATH" ]; then
  sed -i "s/Ext.Msg.show({/void({/g; s/data.status !== 'Active'/false/g" "$PROXMOX_JS_PATH"
fi

echo "==> Proxmox community post-install complete"
