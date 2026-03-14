#!/usr/bin/env bash
set -euo pipefail

# Build a bootable Debian 12 ARM64 base disk image using debootstrap.
# Output: /tmp/debian-base-arm64.qcow2

DISK_IMG="/tmp/debian-base-arm64.raw"
DISK_SIZE="${DISK_SIZE:-20G}"
MOUNT_DIR="/mnt/debian-base-build"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"

echo "==> Building Debian 12 ARM64 base disk image"

qemu-img create -f raw "$DISK_IMG" "$DISK_SIZE"

parted -s "$DISK_IMG" \
  mklabel gpt \
  mkpart ESP fat32 1MiB 261MiB \
  set 1 esp on \
  mkpart primary ext4 261MiB 100%

modprobe loop 2>/dev/null || true
LOOP="$(losetup -fP --show "$DISK_IMG")"
sleep 2
EFI_DEV="${LOOP}p1"
ROOT_DEV="${LOOP}p2"

mkfs.fat -F32 "$EFI_DEV"
mkfs.ext4 -L debian-root -q "$ROOT_DEV"

mkdir -p "$MOUNT_DIR"
mount "$ROOT_DEV" "$MOUNT_DIR"
mkdir -p "$MOUNT_DIR/boot/efi"
mount "$EFI_DEV" "$MOUNT_DIR/boot/efi"

apt-get install -y debian-archive-keyring 2>/dev/null || true
debootstrap \
  --arch=arm64 \
  --include=debian-archive-keyring,ca-certificates,curl,sudo \
  bookworm "$MOUNT_DIR" "$DEBIAN_MIRROR"

mount --bind /dev "$MOUNT_DIR/dev"
mount --bind /dev/pts "$MOUNT_DIR/dev/pts"
mount --bind /proc "$MOUNT_DIR/proc"
mount --bind /sys "$MOUNT_DIR/sys"
mount --bind /run "$MOUNT_DIR/run"
cp /etc/resolv.conf "$MOUNT_DIR/etc/resolv.conf"

ROOT_UUID="$(blkid -s UUID -o value "$ROOT_DEV")"
EFI_UUID="$(blkid -s UUID -o value "$EFI_DEV")"

cat > "$MOUNT_DIR/etc/fstab" <<EOF
UUID=${ROOT_UUID} /          ext4 defaults,noatime 0 1
UUID=${EFI_UUID}  /boot/efi  vfat defaults          0 2
EOF

echo "debian-base" > "$MOUNT_DIR/etc/hostname"
cat > "$MOUNT_DIR/etc/hosts" <<'EOF'
127.0.0.1 localhost
127.0.1.1 debian-base.local debian-base
EOF

cat > "$MOUNT_DIR/etc/apt/sources.list" <<'EOF'
deb http://deb.debian.org/debian bookworm main contrib non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware
EOF

chroot "$MOUNT_DIR" /bin/bash -s <<'CHROOT'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y \
  openssh-server \
  cloud-init \
  ifupdown2 \
  chrony \
  grub-efi-arm64 \
  grub2-common \
  sudo \
  curl \
  wget

# Keep cloud-init compatible with OCI metadata and local NoCloud smoke.
cat > /etc/cloud/cloud.cfg.d/99-datasource.cfg <<'EOF'
datasource_list: [NoCloud, Oracle, None]
EOF

cat > /etc/cloud/cloud.cfg.d/99-default-user.cfg <<'EOF'
system_info:
  default_user:
    name: ubuntu
    lock_passwd: true
    gecos: Ubuntu
    groups: [adm, sudo]
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    shell: /bin/bash
EOF

useradd -m -s /bin/bash -G sudo ubuntu 2>/dev/null || true
echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu
chmod 0440 /etc/sudoers.d/ubuntu

cat > /etc/network/interfaces <<'EOF'
auto lo
iface lo inet loopback

allow-hotplug ens3
iface ens3 inet dhcp

allow-hotplug enp1s0
iface enp1s0 inet dhcp

allow-hotplug eth0
iface eth0 inet dhcp
EOF

cat > /etc/cloud/cloud.cfg.d/99-network-parity.cfg <<'EOF'
network:
  version: 2
  ethernets:
    all-en:
      match:
        name: "en*"
      dhcp4: true
      dhcp6: false
      optional: true
EOF

systemctl enable chrony cloud-init cloud-init-local cloud-config cloud-final 2>/dev/null || true
systemctl enable networking ssh 2>/dev/null || true

systemctl disable nftables ufw 2>/dev/null || true
systemctl mask nftables ufw 2>/dev/null || true

grub-install --target=arm64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck
update-grub
CHROOT

chroot "$MOUNT_DIR" /bin/bash -c "
  apt-get clean
  rm -rf /tmp/* /var/tmp/*
  truncate -s 0 /etc/machine-id
  rm -f /var/lib/dbus/machine-id
  cloud-init clean --logs 2>/dev/null || true
  history -c 2>/dev/null || true
"

umount "$MOUNT_DIR/run" || true
umount "$MOUNT_DIR/sys" || true
umount "$MOUNT_DIR/proc" || true
umount "$MOUNT_DIR/dev/pts" || true
umount "$MOUNT_DIR/dev" || true
umount "$MOUNT_DIR/boot/efi"
umount "$MOUNT_DIR"
losetup -d "$LOOP"

qemu-img convert -f raw -O qcow2 -c "$DISK_IMG" /tmp/debian-base-arm64.qcow2
rm -f "$DISK_IMG"

ls -lh /tmp/debian-base-arm64.qcow2
echo "==> Done: /tmp/debian-base-arm64.qcow2"
