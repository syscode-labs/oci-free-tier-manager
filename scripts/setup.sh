#!/usr/bin/env bash
set -euo pipefail

# OCI Free Tier Manager - Automated Setup Script
# This script automates initial setup tasks

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "===================================="
echo "OCI Free Tier Manager - Setup"
echo "===================================="
echo

# Check if OCI CLI is configured
check_oci_cli() {
    echo "Checking OCI CLI configuration..."
    if ! command -v oci &> /dev/null; then
        echo "ERROR: OCI CLI not found. Install it first:"
        echo "  brew install oci-cli"
        echo "  OR: pip install oci-cli"
        exit 1
    fi
    
    if ! oci iam region list &> /dev/null; then
        echo "OCI CLI not configured. Running setup..."
        oci setup config
    else
        echo "✓ OCI CLI already configured"
    fi
}

# Generate SSH key if not exists
setup_ssh_key() {
    echo
    echo "Checking SSH key..."
    
    SSH_KEY="${HOME}/.ssh/oci_key"
    
    if [ -f "$SSH_KEY" ]; then
        echo "✓ SSH key already exists at $SSH_KEY"
    else
        echo "Generating new SSH key..."
        ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "oci-free-tier"
        echo "✓ SSH key generated at $SSH_KEY"
    fi
    
    echo
    echo "Your SSH public key:"
    cat "${SSH_KEY}.pub"
    echo
}

# Create terraform.tfvars from example
setup_terraform_vars() {
    echo "Setting up OpenTofu variables..."
    
    TFVARS_FILE="${PROJECT_ROOT}/tofu/oci/terraform.tfvars"
    EXAMPLE_FILE="${PROJECT_ROOT}/tofu/oci/terraform.tfvars.example"
    
    if [ -f "$TFVARS_FILE" ]; then
        echo "✓ terraform.tfvars already exists"
        read -p "Overwrite? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return
        fi
    fi
    
    # Get compartment OCID
    echo
    echo "Getting compartment OCID from OCI..."
    TENANCY_OCID=$(awk -F'=' '/^tenancy/ {print $2}' "${HOME}/.oci/config" | tr -d ' ')
    COMPARTMENT_OCID="${TENANCY_OCID}"  # Default to tenancy root
    
    # Get SSH public key
    SSH_PUB_KEY=$(cat "${HOME}/.ssh/oci_key.pub")
    
    # Prompt for email
    read -p "Enter email for budget alerts: " BUDGET_EMAIL
    
    # Create terraform.tfvars
    cat > "$TFVARS_FILE" <<EOF
# OCI Authentication (reads from ~/.oci/config automatically)
# Only override these if you need different credentials:
# tenancy_ocid     = ""
# user_ocid        = ""
# fingerprint      = ""
# private_key_path = ""

# Compartment (required)
compartment_ocid = "${COMPARTMENT_OCID}"

# Region
region = "uk-london-1"  # Change if desired

# SSH Key
ssh_public_key = "${SSH_PUB_KEY}"

# Budget Alert Email
budget_alert_email = "${BUDGET_EMAIL}"

# Recommended K8s Configuration (3 Ampere + 1 Micro, maxes free tier)
ampere_instance_count      = 3
ampere_ocpus_per_instance  = 1.33
ampere_memory_per_instance = 8
ampere_boot_volume_size    = 50

micro_instance_count    = 1
micro_boot_volume_size  = 50

# Additional storage (optional)
create_additional_volume = false
additional_volume_size   = 50
EOF
    
    echo "✓ Created $TFVARS_FILE"
    echo
    echo "Review and edit if needed:"
    echo "  vim $TFVARS_FILE"
}

# Main execution
main() {
    check_oci_cli
    setup_ssh_key
    setup_terraform_vars
    
    echo
    echo "===================================="
    echo "Setup Complete!"
    echo "===================================="
    echo
    echo "Next steps:"
    echo "  1. Review configuration: vim tofu/oci/terraform.tfvars"
    echo "  2. Check capacity: ./check_availability.py"
    echo "  3. Deploy: cd tofu/oci && tofu init && tofu apply"
}

main "$@"
