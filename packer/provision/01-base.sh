#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Layer 1: Base OS Configuration
# Ubuntu 24.04 Minimal with Oracle Cloud Infrastructure datasource

# Ensure Oracle datasource only (prevent cloud-init from trying other datasources).
# cloud-init >=24 on Ubuntu uses DataSourceOracle.py (module name = datasource
# name camelified); the datasource name "OCI" camelifies to "DataSourceOCI",
# which does not exist. Use the datasource name that resolves to DataSourceOracle.
mkdir -p /etc/cloud/cloud.cfg.d
cat > /etc/cloud/cloud.cfg.d/99-oci-datasource.cfg <<'EOF'
datasource_list: [Oracle]
datasource:
  Oracle:
    configure_secondary_nics: true
EOF

# Network: systemd-networkd DHCP on all en* interfaces
mkdir -p /etc/systemd/network
cat > /etc/systemd/network/10-dhcp.network <<'EOF'
[Match]
Name=en*

[Network]
DHCP=yes
EOF

# Mask firstboot (prevents boot hang on "Press any key to proceed")
ln -sf /dev/null /etc/systemd/system/systemd-firstboot.service

# Locale (no locales pkg needed)
cat > /etc/cloud/cloud.cfg.d/99-no-locale.cfg <<'EOF'
locale: "C.UTF-8"
EOF

# SSH config (cloud-init will also configure, but ensure baseline)
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-oci.conf <<'EOF'
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
EOF

# Hostname & timezone pre-set (prevents systemd-firstboot prompt)
echo "oci-micro" > /etc/hostname
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# Install sudo (needed for cloud-init user operations)
apt-get update -y
apt-get install -y sudo cloud-init

# Clean apt cache
apt-get clean
rm -rf /var/lib/apt/lists/*
