#!/bin/bash
set -euo pipefail

# Base System Hardening Script
# Applies security hardening to Debian base image

echo "Hardening base system..."

# Install essential security packages
apt-get install -y \
    iptables \
    iptables-persistent \
    fail2ban \
    ufw \
    aide \
    rkhunter \
    lynis

# Disable unnecessary services
systemctl disable bluetooth.service || true
systemctl disable cups.service || true
systemctl disable avahi-daemon.service || true

# Configure automatic security updates
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

# Kernel hardening (sysctl)
cat > /etc/sysctl.d/99-security.conf <<EOF
# IP Forwarding (disable unless needed)
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Syncookies
net.ipv4.tcp_syncookies = 1

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0

# Ignore source-routed packets
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Log Martians
net.ipv4.conf.all.log_martians = 1

# Ignore ICMP ping requests
net.ipv4.icmp_echo_ignore_all = 0

# Disable IPv6 (optional)
# net.ipv6.conf.all.disable_ipv6 = 1
EOF

sysctl -p /etc/sysctl.d/99-security.conf

# Configure fail2ban for SSH
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
EOF

systemctl enable fail2ban

# Set proper file permissions
chmod 700 /root
chmod 600 /etc/ssh/ssh_host_*_key

# Remove unnecessary packages
apt-get autoremove -y
apt-get autoclean -y

# Configure log rotation
cat > /etc/logrotate.d/rsyslog <<EOF
/var/log/syslog
/var/log/mail.info
/var/log/mail.warn
/var/log/mail.err
/var/log/mail.log
/var/log/daemon.log
/var/log/kern.log
/var/log/auth.log
/var/log/user.log
/var/log/lpr.log
/var/log/cron.log
/var/log/debug
/var/log/messages
{
    rotate 4
    weekly
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
}
EOF

echo "✓ Base system hardened"
