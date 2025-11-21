#!/usr/bin/env bash
set -euo pipefail

# Flux Repository Setup Automation
# Generates all required bootstrap manifests and secrets

FLUX_REPO_PATH="${1:-../oci-free-tier-flux}"

if [ ! -d "$FLUX_REPO_PATH" ]; then
    echo "ERROR: Flux repository not found at $FLUX_REPO_PATH"
    echo "Usage: $0 [flux-repo-path]"
    exit 1
fi

cd "$FLUX_REPO_PATH"

echo "===================================="
echo "Flux Repository Setup"
echo "===================================="
echo

# Generate Cilium manifest
generate_cilium_manifest() {
    echo "Generating Cilium CNI manifest..."
    
    if [ -f "bootstrap/cilium.yaml" ] && [ -s "bootstrap/cilium.yaml" ]; then
        echo "✓ Cilium manifest already exists"
        return
    fi
    
    # Check if Helm is installed
    if ! command -v helm &> /dev/null; then
        echo "ERROR: Helm not found. Run: devbox shell"
        exit 1
    fi
    
    # Create values file if it doesn't exist
    if [ ! -f "bootstrap/cilium-values.yaml" ]; then
        cat > bootstrap/cilium-values.yaml <<EOF
kubeProxyReplacement: true
k8sServiceHost: 127.0.0.1
k8sServicePort: 7445
ipam:
  mode: kubernetes
hubble:
  enabled: true
  relay:
    enabled: true
  ui:
    enabled: true
tunnel: vxlan
autoDirectNodeRoutes: true
EOF
    fi
    
    # Add Cilium repo and generate manifest
    helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
    helm repo update cilium
    
    helm template cilium cilium/cilium \
        --version 1.16.5 \
        --namespace kube-system \
        --values bootstrap/cilium-values.yaml \
        > bootstrap/cilium.yaml
    
    echo "✓ Generated bootstrap/cilium.yaml"
}

# Setup SOPS with Age
setup_sops_age() {
    echo
    echo "Setting up SOPS encryption..."
    
    AGE_KEY_FILE="age-key.txt"
    
    # Generate Age key if it doesn't exist
    if [ ! -f "$AGE_KEY_FILE" ]; then
        echo "Generating Age encryption key..."
        if ! command -v age-keygen &> /dev/null; then
            echo "ERROR: age not found. Run: devbox shell"
            exit 1
        fi
        
        age-keygen -o "$AGE_KEY_FILE"
        echo "✓ Generated $AGE_KEY_FILE"
        echo
        echo "IMPORTANT: Backup this file securely! It's needed to decrypt secrets."
    else
        echo "✓ Age key already exists at $AGE_KEY_FILE"
    fi
    
    # Extract public key
    AGE_PUBLIC_KEY=$(grep "# public key:" "$AGE_KEY_FILE" | awk '{print $4}')
    
    # Update .sops.yaml if it contains placeholder
    if grep -q "YOUR_AGE_PUBLIC_KEY_REPLACE_ME" .sops.yaml 2>/dev/null; then
        echo "Updating .sops.yaml with Age public key..."
        sed -i.bak "s/YOUR_AGE_PUBLIC_KEY_REPLACE_ME/$AGE_PUBLIC_KEY/g" .sops.yaml
        rm .sops.yaml.bak
        echo "✓ Updated .sops.yaml"
    else
        echo "✓ .sops.yaml already configured"
    fi
    
    echo
    echo "Your Age public key: $AGE_PUBLIC_KEY"
}

# Create encrypted Tailscale secret
create_tailscale_secret() {
    echo
    echo "Creating Tailscale OAuth secret..."
    
    SECRET_FILE="infrastructure/overlays/prod/tailscale-secret.enc.yaml"
    
    if [ -f "$SECRET_FILE" ] && ! grep -q "YOUR_ACTUAL_CLIENT_ID" "$SECRET_FILE"; then
        echo "✓ Tailscale secret already exists and encrypted"
        return
    fi
    
    echo
    echo "Get OAuth credentials from: https://login.tailscale.com/admin/settings/oauth"
    echo
    read -p "Enter Tailscale OAuth Client ID: " CLIENT_ID
    read -sp "Enter Tailscale OAuth Client Secret: " CLIENT_SECRET
    echo
    
    # Create temporary unencrypted secret
    cat > /tmp/tailscale-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: tailscale-oauth
  namespace: tailscale
stringData:
  client-id: "${CLIENT_ID}"
  client-secret: "${CLIENT_SECRET}"
EOF
    
    # Encrypt with SOPS
    if ! command -v sops &> /dev/null; then
        echo "ERROR: sops not found. Run: devbox shell"
        exit 1
    fi
    
    sops --encrypt /tmp/tailscale-secret.yaml > "$SECRET_FILE"
    rm /tmp/tailscale-secret.yaml
    
    echo "✓ Created encrypted secret at $SECRET_FILE"
}

# Commit changes
commit_changes() {
    echo
    echo "Committing changes to Git..."
    
    git add .
    
    if git diff --cached --quiet; then
        echo "✓ No changes to commit"
        return
    fi
    
    git commit -m "chore: automate Flux bootstrap setup

- Generate Cilium CNI manifest
- Configure SOPS with Age public key
- Add encrypted Tailscale OAuth secret"
    
    echo "✓ Changes committed"
    echo
    read -p "Push to GitHub? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git push
        echo "✓ Pushed to GitHub"
    fi
}

# Main execution
main() {
    generate_cilium_manifest
    setup_sops_age
    create_tailscale_secret
    commit_changes
    
    echo
    echo "===================================="
    echo "Setup Complete!"
    echo "===================================="
    echo
    echo "IMPORTANT: Store age-key.txt securely!"
    echo "This key will be injected into the cluster by OpenTofu."
    echo
    echo "Next steps:"
    echo "  1. Deploy OCI infrastructure"
    echo "  2. Talos will bootstrap with Flux automatically"
    echo "  3. Flux will deploy all infrastructure from this repo"
}

main "$@"
