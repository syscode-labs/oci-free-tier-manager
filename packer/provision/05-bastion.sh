#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Layer 5: Self-managed bastion components
# Installs knockd for port-knock SSH access. The per-instance sequence and
# firewall rules are finalized by cloud-init; here we only bake the package
# and a baseline config that cloud-init can override.

apt-get update -y
apt-get install -y knockd

# Baseline knockd config. Cloud-init replaces /etc/knockd.conf with the
# operator-defined sequence and UFW commands. The defaults here are intentionally
# non-functional so SSH stays closed until cloud-init runs.
cat > /etc/knockd.conf <<'EOF'
[options]
  logfile = /var/log/knockd.log
  interface = eth0

[openSSH]
  sequence    = 7000:tcp,8000:tcp,9000:tcp,1234:tcp
  seq_timeout = 60
  tcpflags    = syn
  start_command      = /sbin/ufw allow from %IP% to any port 22 proto tcp
  cmd_timeout        = 60
  stop_command       = /sbin/ufw delete allow from %IP% to any port 22 proto tcp
EOF

# knockd is enabled by cloud-init after the correct interface and sequence are
# known. Keep it disabled in the image so it doesn't try to bind prematurely.
systemctl disable knockd || true

# Ensure UFW is present (02-hardened.sh installs it, but be explicit here)
apt-get install -y ufw

apt-get clean
