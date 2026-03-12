#!/bin/bash
set -euo pipefail

# Install Proxmox VE via debootstrap on Ubuntu 24.04 ARM64
#
# OCI only provides Ubuntu ARM64 images. Proxmox requires Debian 12 libraries.
# This script: installs Debian 12 (bookworm) via debootstrap, installs Proxmox
# inside the chroot, then configures GRUB so the instance boots into Debian+Proxmox.

echo "==> Installing Proxmox VE via debootstrap (Debian 12 bookworm) on Ubuntu 24.04..."

# Wait for cloud-init to release apt lock
while fuser /var/lib/apt/lists/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
  echo "    Waiting for apt lock..."
  sleep 5
done

# Disable command-not-found hook (fails on Ubuntu 24.04 ARM64)
rm -f /etc/apt/apt.conf.d/50command-not-found || true

# Install debootstrap and required tools
apt-get update || true
DEBIAN_FRONTEND=noninteractive apt-get install -y debootstrap schroot

# Fix /etc/hosts for Proxmox installer
PVE_HOSTNAME=$(hostname -s)
HOST_IP=$(hostname -I | awk '{print $1}')
if ! grep -q "^${HOST_IP}" /etc/hosts; then
  echo "${HOST_IP} ${PVE_HOSTNAME}.proxmox.local ${PVE_HOSTNAME}" >> /etc/hosts
fi

# Bootstrap Debian 12 into /mnt/debian
echo "==> Bootstrapping Debian 12 bookworm..."
debootstrap --arch=arm64 bookworm /mnt/debian http://deb.debian.org/debian

# Mount required filesystems for chroot
mount --bind /dev     /mnt/debian/dev
mount --bind /dev/pts /mnt/debian/dev/pts
mount --bind /proc    /mnt/debian/proc
mount --bind /sys     /mnt/debian/sys
mount --bind /run     /mnt/debian/run

# Configure the Debian chroot
echo "==> Configuring Debian 12 chroot..."
cat > /mnt/debian/etc/apt/sources.list << 'EOF'
deb http://deb.debian.org/debian bookworm main contrib non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware
EOF

# Copy host network config into chroot
cp /etc/resolv.conf /mnt/debian/etc/resolv.conf

# Set hostname
echo "proxmox" > /mnt/debian/etc/hostname
cat > /mnt/debian/etc/hosts << 'EOF'
127.0.0.1 localhost
127.0.1.1 proxmox.proxmox.local proxmox
EOF

# Configure fstab
cat > /mnt/debian/etc/fstab << 'EOF'
# OCI root — UUID populated at first boot by cloud-init
/dev/sda1  /     ext4  defaults,noatime  0 1
/dev/sda15 /boot/efi  vfat  defaults  0 2
EOF

# Install Proxmox VE in the chroot
echo "==> Installing Proxmox VE in Debian 12 chroot..."
chroot /mnt/debian /bin/bash -c "
set -euo pipefail

# Add PXVIRT ARM64 repo (PXVIRT = Proxmox-Port successor at mirrors.lierfang.com)
curl -fsSL https://mirrors.lierfang.com/pxcloud/lierfang.gpg \
  -o /etc/apt/trusted.gpg.d/lierfang.gpg

echo 'deb [arch=arm64 signed-by=/etc/apt/trusted.gpg.d/lierfang.gpg] https://mirrors.lierfang.com/pxcloud/pxvirt bookworm main' \
  > /etc/apt/sources.list.d/pve-install-repo.list

apt-get update

# Install PVE kernel first
DEBIAN_FRONTEND=noninteractive apt-get install -y pve-kernel-6.12-pve

# Install Proxmox VE
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  proxmox-ve \
  postfix \
  open-iscsi \
  chrony \
  ifupdown2 \
  cloud-init

# Enable IP forwarding
cat > /etc/sysctl.d/99-proxmox-forwarding.conf << 'SYSCTL'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
SYSCTL

# Configure chrony
systemctl enable chrony || true

echo '==> Proxmox VE installed in chroot'
"

# Install GRUB inside chroot and configure it to be the default boot
echo "==> Configuring bootloader..."
chroot /mnt/debian /bin/bash -c "
DEBIAN_FRONTEND=noninteractive apt-get install -y grub-efi-arm64 grub2-common || true
update-grub || true
grub-install --target=arm64-efi --efi-directory=/boot/efi --bootloader-id=proxmox --recheck || true
"

# Copy SSH authorized keys into the Debian chroot
mkdir -p /mnt/debian/root/.ssh
cp /home/ubuntu/.ssh/authorized_keys /mnt/debian/root/.ssh/authorized_keys 2>/dev/null || true
chmod 700 /mnt/debian/root/.ssh
chmod 600 /mnt/debian/root/.ssh/authorized_keys

# Configure SSH to allow root login in the Debian chroot
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /mnt/debian/etc/ssh/sshd_config 2>/dev/null || true

# Unmount filesystems (best-effort)
umount /mnt/debian/run   || true
umount /mnt/debian/sys   || true
umount /mnt/debian/proc  || true
umount /mnt/debian/dev/pts || true
umount /mnt/debian/dev   || true

echo "==> Proxmox VE (via debootstrap) complete."
echo "==> NOTE: Instance will boot into Debian 12 + Proxmox on next start."
