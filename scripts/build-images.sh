#!/usr/bin/env bash
set -euo pipefail

# Build Packer images for OCI Ampere ARM64
# Usage: ./scripts/build-images.sh <vars-file>
# Example: ./scripts/build-images.sh packer/vars/proxmox-ampere.pkrvars.hcl

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PACKER_DIR="${REPO_ROOT}/packer"
VARS_FILE="${1:-${PACKER_DIR}/vars/proxmox-ampere.pkrvars.hcl}"

if [ ! -f "${VARS_FILE}" ]; then
  echo "ERROR: vars file not found: ${VARS_FILE}"
  echo "Copy the example and fill in your values:"
  echo "  cp ${VARS_FILE}.example ${VARS_FILE}"
  exit 1
fi

echo "==> Checking OCI session (syscode profile)..."
if ! oci session validate --profile syscode --local 2>/dev/null; then
  echo "ERROR: syscode session expired. Run:"
  echo "  oci session authenticate --profile syscode"
  exit 1
fi

echo "==> Initialising Packer plugins..."
cd "${PACKER_DIR}"
packer init oci-ampere-base.pkr.hcl
packer init proxmox-ampere.pkr.hcl

echo ""
echo "==> Stage 1: Building hardened base image..."
BASE_IMAGE_OCID=$(
  packer build \
    -var-file="${VARS_FILE}" \
    -machine-readable \
    oci-ampere-base.pkr.hcl \
  | tee /tmp/packer-base.log \
  | grep "artifact,0,id" \
  | cut -d',' -f6
)

if [ -z "${BASE_IMAGE_OCID}" ]; then
  echo "ERROR: Failed to get base image OCID. Check /tmp/packer-base.log"
  exit 1
fi

echo "    Base image OCID: ${BASE_IMAGE_OCID}"

echo ""
echo "==> Stage 2: Building Proxmox image on top of base..."
PROXMOX_IMAGE_OCID=$(
  packer build \
    -var-file="${VARS_FILE}" \
    -var "base_image_ocid=${BASE_IMAGE_OCID}" \
    -machine-readable \
    proxmox-ampere.pkr.hcl \
  | tee /tmp/packer-proxmox.log \
  | grep "artifact,0,id" \
  | cut -d',' -f6
)

if [ -z "${PROXMOX_IMAGE_OCID}" ]; then
  echo "ERROR: Failed to get Proxmox image OCID. Check /tmp/packer-proxmox.log"
  exit 1
fi

echo ""
echo "====================================================="
echo "Build complete!"
echo ""
echo "Base image OCID:    ${BASE_IMAGE_OCID}"
echo "Proxmox image OCID: ${PROXMOX_IMAGE_OCID}"
echo ""
echo "Next: Set proxmox_image_ocid in tofu/oci/terraform.tfvars:"
echo "  proxmox_image_ocid = \"${PROXMOX_IMAGE_OCID}\""
echo "====================================================="
