#!/usr/bin/env bash
set -euo pipefail

# run-goss.sh <goss_yaml_path>
# Downloads the appropriate goss binary for the current architecture and runs validation.

if [ $# -ne 1 ]; then
  echo "Usage: $0 <goss.yaml>"
  exit 1
fi

GOSS_YAML="$1"

arch="$(uname -m)"
case "$arch" in
  x86_64) goss_arch="amd64" ;;
  aarch64) goss_arch="arm64" ;;
  arm64) goss_arch="arm64" ;;
  *) echo "Unsupported architecture: $arch" && exit 1 ;;
esac

GOSS_BIN="/usr/local/bin/goss"
curl -fsSL -o "$GOSS_BIN" "https://github.com/goss-org/goss/releases/download/v0.4.6/goss-linux-${goss_arch}"
chmod +x "$GOSS_BIN"

echo "Running goss validation..."
GOSS_FILE="$GOSS_YAML" "$GOSS_BIN" validate --format tap
