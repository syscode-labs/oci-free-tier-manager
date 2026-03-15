#!/usr/bin/env bash
set -euo pipefail

# Local image smoke test for Unraid/KVM parity with OCI networking.
# - Uses NoCloud seed (same cloud-init path used by OCI metadata logic)
# - Uses user-mode NAT with localhost-only port forward (no world exposure)
# - Proves SSH reachability before OCI import

IMAGE_PATH="${1:-/tmp/proxmox-arm64.qcow2}"
SSH_PUB_KEY_PATH="${SSH_PUB_KEY_PATH:-$HOME/.ssh/oci_free_tier.pub}"
SSH_PRIV_KEY_PATH="${SSH_PRIV_KEY_PATH:-${SSH_PUB_KEY_PATH%.pub}}"
SSH_PORT="${SSH_PORT:-2222}"
SMOKE_USER="${SMOKE_USER:-ubuntu}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-420}"
VM_RAM_MB="${VM_RAM_MB:-4096}"
VM_CPUS="${VM_CPUS:-2}"
KEEP_WORKDIR_ON_FAIL="${KEEP_WORKDIR_ON_FAIL:-1}"
VM_ARCH="${VM_ARCH:-x86_64}"

if [[ ! -f "$IMAGE_PATH" ]]; then
  echo "image not found: $IMAGE_PATH" >&2
  exit 1
fi
if [[ ! -f "$SSH_PUB_KEY_PATH" ]]; then
  echo "ssh public key not found: $SSH_PUB_KEY_PATH" >&2
  exit 1
fi
if [[ ! -f "$SSH_PRIV_KEY_PATH" ]]; then
  echo "ssh private key not found: $SSH_PRIV_KEY_PATH" >&2
  exit 1
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing dependency: $1" >&2
    exit 1
  }
}

need_cmd qemu-img
need_cmd ssh
need_cmd nc

if [[ "$VM_ARCH" = "x86_64" ]]; then
  QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
  QEMU_MACHINE="${QEMU_MACHINE:-q35}"
  QEMU_CPU="${QEMU_CPU:-max}"
  EFI_ENV_PATH="${X86_64_EFI_CODE:-}"
  EFI_CANDIDATES=(
    "$EFI_ENV_PATH"
    "/usr/share/OVMF/OVMF_CODE.fd"
    "/usr/share/edk2/x64/OVMF_CODE.fd"
    "/opt/homebrew/share/qemu/edk2-x86_64-code.fd"
    "/usr/local/share/qemu/edk2-x86_64-code.fd"
  )
elif [[ "$VM_ARCH" = "arm64" || "$VM_ARCH" = "aarch64" ]]; then
  QEMU_BIN="${QEMU_BIN:-qemu-system-aarch64}"
  QEMU_MACHINE="${QEMU_MACHINE:-virt}"
  QEMU_CPU="${QEMU_CPU:-cortex-a72}"
  EFI_ENV_PATH="${AARCH64_EFI_CODE:-}"
  EFI_CANDIDATES=(
    "$EFI_ENV_PATH"
    "/usr/share/AAVMF/AAVMF_CODE.fd"
    "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
    "/usr/share/edk2/aarch64/QEMU_EFI.fd"
    "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
    "/usr/local/share/qemu/edk2-aarch64-code.fd"
  )
else
  echo "unsupported VM_ARCH: $VM_ARCH (expected x86_64 or arm64)" >&2
  exit 1
fi

need_cmd "$QEMU_BIN"

find_efi_code() {
  local candidates=("${EFI_CANDIDATES[@]}")
  for p in "${candidates[@]}"; do
    [[ -n "$p" && -f "$p" ]] && { echo "$p"; return 0; }
  done
  return 1
}

EFI_CODE="$(find_efi_code || true)"
if [[ -z "${EFI_CODE:-}" ]]; then
  echo "unable to find UEFI firmware for VM_ARCH=$VM_ARCH." >&2
  exit 1
fi

WORKDIR="$(mktemp -d /tmp/unraid-smoke.XXXXXX)"
OVERLAY="$WORKDIR/overlay.qcow2"
SEED_ISO="$WORKDIR/seed.iso"
EFI_VARS="$WORKDIR/efi-vars.fd"
SERIAL_LOG="$WORKDIR/serial.log"
QEMU_LOG="$WORKDIR/qemu.log"
PID_FILE="$WORKDIR/qemu.pid"
FAILED=0

cleanup() {
  if [[ -f "$PID_FILE" ]]; then
    kill "$(cat "$PID_FILE")" >/dev/null 2>&1 || true
  fi
  if [[ "$FAILED" -eq 1 && "$KEEP_WORKDIR_ON_FAIL" = "1" ]]; then
    echo "preserving debug artifacts at: $WORKDIR"
  else
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT

qemu-img create -f qcow2 -F qcow2 -b "$IMAGE_PATH" "$OVERLAY" >/dev/null

SSH_KEY_CONTENT="$(cat "$SSH_PUB_KEY_PATH")"
cat > "$WORKDIR/user-data" <<EOF
#cloud-config
users:
  - default
  - name: ${SMOKE_USER}
    groups: [adm, sudo]
    shell: /bin/bash
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    lock_passwd: true
    ssh_authorized_keys:
      - ${SSH_KEY_CONTENT}
ssh_pwauth: false
disable_root: true
EOF

cat > "$WORKDIR/meta-data" <<EOF
instance-id: iid-unraid-smoke
local-hostname: unraid-smoke
EOF

cat > "$WORKDIR/network-config" <<'EOF'
version: 2
ethernets:
  all-en:
    match:
      name: "en*"
    dhcp4: true
    dhcp6: false
    optional: true
EOF

if command -v cloud-localds >/dev/null 2>&1; then
  cloud-localds \
    --network-config="$WORKDIR/network-config" \
    "$SEED_ISO" \
    "$WORKDIR/user-data" \
    "$WORKDIR/meta-data"
else
  need_cmd mkisofs
  mkisofs \
    -output "$SEED_ISO" \
    -volid cidata \
    -joliet \
    -rock \
    -graft-points \
    "user-data=$WORKDIR/user-data" \
    "meta-data=$WORKDIR/meta-data" \
    "network-config=$WORKDIR/network-config" \
    >/dev/null 2>&1
fi

cp "$EFI_CODE" "$EFI_VARS"

ACCEL_ARGS=()
if [[ "$(uname -s)" = "Darwin" ]]; then
  if "$QEMU_BIN" -accel help 2>/dev/null | rg -q '^hvf$'; then
    ACCEL_ARGS=(-accel hvf)
  fi
fi

"$QEMU_BIN" \
  -name unraid-smoke \
  -machine "$QEMU_MACHINE" \
  -cpu "$QEMU_CPU" \
  -smp "$VM_CPUS" \
  -m "$VM_RAM_MB" \
  "${ACCEL_ARGS[@]}" \
  -nographic \
  -serial "file:$SERIAL_LOG" \
  -drive if=pflash,format=raw,readonly=on,file="$EFI_CODE" \
  -drive if=pflash,format=raw,file="$EFI_VARS" \
  -drive if=virtio,format=qcow2,file="$OVERLAY" \
  -drive if=virtio,format=raw,file="$SEED_ISO" \
  -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22" \
  -device virtio-net-pci,netdev=net0 \
  >"$QEMU_LOG" 2>&1 &
echo $! > "$PID_FILE"

echo "smoke vm started (pid $(cat "$PID_FILE"))"
echo "waiting for ssh on 127.0.0.1:${SSH_PORT} ..."

START_TS="$(date +%s)"
while true; do
  NOW_TS="$(date +%s)"
  if (( NOW_TS - START_TS > TIMEOUT_SECONDS )); then
    echo "timed out waiting for ssh"
    FAILED=1
    echo "qemu log tail:"
    tail -n 120 "$QEMU_LOG" || true
    echo "serial tail:"
    tail -n 120 "$SERIAL_LOG" || true
    exit 1
  fi

  if nc -z 127.0.0.1 "$SSH_PORT" >/dev/null 2>&1; then
    if ssh \
      -p "$SSH_PORT" \
      -i "$SSH_PRIV_KEY_PATH" \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=5 \
      "${SMOKE_USER}@127.0.0.1" \
      'echo ssh_ok && ip -o -4 addr show | head -n 3'; then
      echo "local smoke test passed"
      exit 0
    fi
  fi

  sleep 5
done
