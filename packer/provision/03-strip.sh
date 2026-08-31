#!/bin/bash
set -euo pipefail

# Layer 3: Strip & Optimize
# Cleans up apt, logs, caches, and trims free space for minimal image size

# Clean apt
apt-get autoremove -y --purge || true
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/cache/*

# Clean logs
find /var/log -type f -name '*.gz' -delete || true
find /var/log -type f -name '*.[0-9]' -delete || true
truncate -s 0 /var/log/wtmp /var/log/btmp /var/log/lastlog || true
journalctl --rotate || true
journalctl --vacuum-time=1s || true

# Clean caches
rm -rf /root/.cache/* /home/ubuntu/.cache/* /var/cache/*

# Cloud-init clean (removes instance-specific data)
cloud-init clean --logs || true

# TRIM free space (helps sparse image compression)
fstrim -av || true
