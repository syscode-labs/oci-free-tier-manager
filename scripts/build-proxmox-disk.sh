#!/usr/bin/env bash
set -euo pipefail

# Build a bootable Proxmox VE ARM64 disk image using debootstrap.
#
# Runs natively on a GitHub ubuntu-24.04-arm runner (or any ARM64 Linux host).
# No QEMU emulation needed — we debootstrap Debian 12, install Proxmox packages,
# set up GRUB for UEFI, configure cloud-init for OCI, then export as QCOW2.
#
# Output: /tmp/proxmox-arm64.qcow2

DISK_IMG="/tmp/proxmox-arm64.raw"
DISK_SIZE="${DISK_SIZE:-20G}"
MOUNT_DIR="/mnt/proxmox-build"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"

echo "==> Building Proxmox VE ARM64 disk image (debootstrap, no QEMU)"

# ── 1. Create raw disk image ─────────────────────────────────────────────────
echo "==> Creating ${DISK_SIZE} raw disk image..."
qemu-img create -f raw "$DISK_IMG" "$DISK_SIZE"

# ── 2. Partition: GPT, EFI (260MB) + root (rest) ────────────────────────────
echo "==> Partitioning..."
parted -s "$DISK_IMG" \
  mklabel gpt \
  mkpart ESP fat32 1MiB 261MiB \
  set 1 esp on \
  mkpart primary ext4 261MiB 100%

# ── 3. Loop-mount and format ─────────────────────────────────────────────────
echo "==> Formatting partitions..."
# Ensure loop module is loaded and partitions are probed
modprobe loop 2>/dev/null || true
LOOP=$(losetup -fP --show "$DISK_IMG")
# Wait for partition devices to appear
sleep 2
ls "${LOOP}p1" "${LOOP}p2" || { echo "Partition devices not found"; losetup -d "$LOOP"; exit 1; }
EFI_DEV="${LOOP}p1"
ROOT_DEV="${LOOP}p2"

mkfs.fat -F32 "$EFI_DEV"
mkfs.ext4 -L proxmox-root -q "$ROOT_DEV"

# ── 4. Mount ─────────────────────────────────────────────────────────────────
mkdir -p "$MOUNT_DIR"
mount "$ROOT_DEV" "$MOUNT_DIR"
mkdir -p "$MOUNT_DIR/boot/efi"
mount "$EFI_DEV" "$MOUNT_DIR/boot/efi"

# ── 5. Debootstrap Debian 12 ─────────────────────────────────────────────────
echo "==> Bootstrapping Debian 12 bookworm (native ARM64)..."
# Install debian-archive-keyring first so debootstrap can verify signatures
apt-get install -y debian-archive-keyring 2>/dev/null || true
debootstrap \
  --arch=arm64 \
  --include=debian-archive-keyring,ca-certificates,curl,sudo \
  bookworm "$MOUNT_DIR" "$DEBIAN_MIRROR"

# ── 6. Bind mounts for chroot ────────────────────────────────────────────────
mount --bind /dev     "$MOUNT_DIR/dev"
mount --bind /dev/pts "$MOUNT_DIR/dev/pts"
mount --bind /proc    "$MOUNT_DIR/proc"
mount --bind /sys     "$MOUNT_DIR/sys"
mount --bind /run     "$MOUNT_DIR/run"
cp /etc/resolv.conf   "$MOUNT_DIR/etc/resolv.conf"

# ── 7. Configure base system in chroot ───────────────────────────────────────
echo "==> Configuring base system..."

ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEV")
EFI_UUID=$(blkid -s UUID -o value "$EFI_DEV")

cat > "$MOUNT_DIR/etc/fstab" << EOF
UUID=${ROOT_UUID} /          ext4 defaults,noatime 0 1
UUID=${EFI_UUID}  /boot/efi  vfat defaults          0 2
EOF

echo "proxmox" > "$MOUNT_DIR/etc/hostname"
cat > "$MOUNT_DIR/etc/hosts" << 'EOF'
127.0.0.1 localhost
127.0.1.1 proxmox.proxmox.local proxmox
EOF

cat > "$MOUNT_DIR/etc/apt/sources.list" << 'EOF'
deb http://deb.debian.org/debian bookworm main contrib non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware
EOF

# ── 8. Install Proxmox VE in chroot ──────────────────────────────────────────
echo "==> Installing Proxmox VE (PXVIRT ARM64 port)..."
chroot "$MOUNT_DIR" /bin/bash -s << 'CHROOT'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq

# Add PXVIRT ARM64 repository (successor to mirrors.apqa.cn)
curl -fsSL https://mirrors.lierfang.com/pxcloud/lierfang.gpg \
  -o /etc/apt/trusted.gpg.d/lierfang.gpg
echo "deb [arch=arm64 signed-by=/etc/apt/trusted.gpg.d/lierfang.gpg] https://mirrors.lierfang.com/pxcloud/pxvirt bookworm main" \
  > /etc/apt/sources.list.d/pve-install-repo.list

apt-get update -qq

# Install PVE kernel + Proxmox VE
apt-get install -y pve-kernel-6.12-pve
apt-get install -y \
  proxmox-ve \
  postfix \
  open-iscsi \
  chrony \
  ifupdown2 \
  cloud-init \
  sudo \
  curl \
  wget

# Remove Debian kernel (Proxmox boot-tool manages kernels)
apt-get remove -y "linux-image-arm64" "linux-image-6.*" 2>/dev/null || true

# Enable IP forwarding
cat > /etc/sysctl.d/99-proxmox.conf << 'SYSCTL'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
SYSCTL

# Configure cloud-init for OCI (Oracle datasource)
cat > /etc/cloud/cloud.cfg.d/99-oracle.cfg << 'CLOUDINIT'
datasource_list: [Oracle, None]
CLOUDINIT

# Create debian user (used for Packer SSH during later builds)
useradd -m -s /bin/bash -G sudo debian 2>/dev/null || true
echo "debian ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/debian

# Disable Proxmox subscription nag
PROXMOX_JS=$(find /usr/share/javascript/proxmox-widget-toolkit -name 'proxmoxlib.js' 2>/dev/null | head -1)
if [ -n "$PROXMOX_JS" ]; then
  sed -i "s/Ext.Msg.show({/void({/g; s/data.status !== 'Active'/false/g" "$PROXMOX_JS"
fi

systemctl enable chrony cloud-init cloud-init-local cloud-config cloud-final 2>/dev/null || true

echo "==> Proxmox VE installed"
CHROOT

# ── 9. Install GRUB (ARM64 UEFI) ─────────────────────────────────────────────
echo "==> Installing GRUB ARM64 UEFI..."
chroot "$MOUNT_DIR" /bin/bash -s << CHROOT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get install -y grub-efi-arm64 grub2-common
grub-install --target=arm64-efi --efi-directory=/boot/efi --bootloader-id=proxmox --recheck
update-grub
CHROOT

# ── 10. Cleanup chroot ───────────────────────────────────────────────────────
echo "==> Cleaning up..."
chroot "$MOUNT_DIR" /bin/bash -c "
  apt-get clean
  rm -rf /tmp/* /var/tmp/*
  truncate -s 0 /etc/machine-id
  rm -f /var/lib/dbus/machine-id
  cloud-init clean --logs 2>/dev/null || true
  history -c 2>/dev/null || true
"

# ── 11. Unmount ──────────────────────────────────────────────────────────────
echo "==> Unmounting..."
umount "$MOUNT_DIR/run"   || true
umount "$MOUNT_DIR/sys"   || true
umount "$MOUNT_DIR/proc"  || true
umount "$MOUNT_DIR/dev/pts" || true
umount "$MOUNT_DIR/dev"   || true
umount "$MOUNT_DIR/boot/efi"
umount "$MOUNT_DIR"
losetup -d "$LOOP"

# ── 12. Convert to QCOW2 ────────────────────────────────────────────────────
echo "==> Converting to QCOW2..."
qemu-img convert -f raw -O qcow2 -c "$DISK_IMG" /tmp/proxmox-arm64.qcow2
rm -f "$DISK_IMG"

ls -lh /tmp/proxmox-arm64.qcow2
echo "==> Done: /tmp/proxmox-arm64.qcow2"
