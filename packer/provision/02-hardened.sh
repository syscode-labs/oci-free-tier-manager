#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Layer 2: Common Hardening
# Installs and configures security packages, sysctl, fail2ban, auditd, UFW, NFS, unattended-upgrades

# Remove unnecessary packages (saves RAM/disk on Micro); lxd-client,
# popularity-contest and command-not-found are gone in 24.04
apt-get purge -y snapd lxd || true
apt-get autoremove -y --purge || true

# Install hardening packages
apt-get update -y
apt-get install -y \
  nfs-kernel-server \
  fail2ban \
  auditd \
  ufw \
  logrotate \
  unattended-upgrades \
  ca-certificates \
  curl \
  gnupg

# sysctl hardening
cat > /etc/sysctl.d/99-hardening.conf <<'EOF'
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
vm.unprivileged_userfaultfd = 0
EOF

# Apply sysctl immediately
sysctl --system

# unattended-upgrades (security updates only)
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
  "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

# fail2ban configuration
cat > /etc/fail2ban/jail.local <<'EOF'
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
EOF

# SSH hardening (also applied via cloud-config, but ensure baseline)
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# UFW default rules (instance-specific rules added via cloud-init)
ufw --force enable
ufw default deny incoming
ufw default allow outgoing

# Enable services
systemctl enable fail2ban
systemctl enable auditd
systemctl enable unattended-upgrades
systemctl enable nfs-server

# NFS exports template (instance-specific exports added via cloud-init)
cat > /etc/exports <<'EOF'
# Per-instance exports added via cloud-init
EOF

# NFS kernel server config
cat > /etc/default/nfs-kernel-server <<'EOF'
RPCNFSDCOUNT=4
RPCNFSDPRIORITY=0
RPCMOUNTDOPTS="--manage-gids"
NEED_SVCGSSD="no"
EOF
