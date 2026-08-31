#!/usr/bin/env bash
set -euo pipefail

# Helper: send the knock sequence to the bastion and then SSH into it.
#
# Usage:
#   ./scripts/bastion-ssh.sh <bastion-public-ip> [ssh-args...]
#
# Example:
#   ./scripts/bastion-ssh.sh 203.0.113.10
#   ./scripts/bastion-ssh.sh 203.0.113.10 -i ~/.ssh/id_rsa

BASTION_IP="${1:-}"
if [[ -z "$BASTION_IP" ]]; then
  echo "Usage: $0 <bastion-public-ip> [ssh-args...]"
  exit 1
fi
shift

# Knock sequence must match var.bastion_knock_ports (default: 7000, 8000, 9000, 1234).
KNOCK_PORTS=(7000 8000 9000)
FINAL_PORT=1234
KNOCK_PAUSE=5

echo "[+] Knocking ${BASTION_IP} ..."
if command -v knock >/dev/null 2>&1; then
  # Use knock client if available; 500ms between ports.
  knock -d 500 "$BASTION_IP" "${KNOCK_PORTS[@]}" "$FINAL_PORT" || true
else
  # Fallback: nc may not work on all platforms; prefer knock client.
  for p in "${KNOCK_PORTS[@]}"; do
    nc -z -w1 "$BASTION_IP" "$p" 2>/dev/null || true
  done
  sleep "$KNOCK_PAUSE"
  nc -z -w1 "$BASTION_IP" "$FINAL_PORT" 2>/dev/null || true
fi

echo "[+] Connecting to ubuntu@${BASTION_IP} ..."
exec ssh ubuntu@"$BASTION_IP" "$@"
