# Quick Start Guide

Complete workflow for deploying OCI Free Tier infrastructure using Nix + Task + Dagger.

## Prerequisites

1. **Install Nix** (if using flake.nix):
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
   ```

2. **OR Install devbox** (if using devbox.json):
   ```bash
   curl -fsSL https://get.jetpack.io/devbox | bash
   ```

3. **Optional: Install direnv** (for automatic environment loading):
   ```bash
   # macOS
   brew install direnv
   
   # Add to ~/.zshrc or ~/.bashrc
   eval "$(direnv hook zsh)"  # or bash
   ```

## Development Environment

### Option A: Nix Flake
```bash
# Enter dev shell
nix develop

# OR use direnv (automatic)
direnv allow
cd .  # Re-enter directory to activate
```

### Option B: devbox
```bash
devbox shell
```

Both provide the same tools:
- opentofu, kubectl, helm, talosctl
- sops, age
- packer, dagger, go-task
- OCI CLI, linters, etc.

## Workflow

### 1. Initial Setup

```bash
# Configure OCI CLI, generate SSH keys, create tfvars
task setup

# Setup Flux repository
task setup:flux
```

### 2. Check Available Tasks

```bash
task --list
```

Output:
```
task: Available tasks for this project:
* build:images:         Build custom images with Dagger (base + Proxmox)
* build:upload:         Upload images to OCI Object Storage
* build:validate:       Validate built images meet size requirements
* check:availability:   Check OCI capacity availability
* clean:                Clean build artifacts
* deploy:all:           Full deployment (all phases)
* deploy:oci:           Deploy OCI infrastructure (Layer 1)
* deploy:oci:plan:      Plan OCI infrastructure changes
* deploy:proxmox:       Setup Proxmox cluster (Layer 2)
* deploy:proxmox:plan:  Plan Proxmox cluster changes
* deploy:talos:         Deploy Talos Kubernetes (Layer 3)
* deploy:talos:plan:    Plan Talos Kubernetes changes
* destroy:all:          Destroy all infrastructure (reverse order)
* fmt:                  Format all code
* lint:                 Run linters on all code
* setup:                Run initial setup (OCI CLI, SSH keys, tfvars)
* setup:flux:           Setup Flux repository (Cilium, SOPS, secrets)
* validate:             Run all validation checks
```

### 3. Check OCI Capacity

```bash
# Check if Ampere instances are available
task check:availability
```

### 4. Build Custom Images

```bash
# Build base + Proxmox images with Dagger
task build:images

# Validate sizes
task build:validate

# Upload to OCI Object Storage
task build:upload COMPARTMENT_ID=ocid1.compartment.oc1..xxxxx
```

### 5. Deploy Infrastructure

#### Option A: Deploy All at Once
```bash
task deploy:all
```

#### Option B: Deploy Layer by Layer
```bash
# Layer 1: OCI infrastructure
task deploy:oci

# Layer 2: Proxmox cluster
task deploy:proxmox

# Layer 3: Talos Kubernetes
task deploy:talos
```

### 6. Validate Deployment

```bash
# Run all validation checks
task validate

# Or validate individual phases
task validate:images
task validate:oci
task validate:proxmox
task validate:talos
task validate:cost  # Verify $0.00 billing
```

### 7. Access Your Cluster

After deployment completes:

```bash
# Get kubeconfig
cd tofu/talos
tofu output -raw kubeconfig > ~/.kube/config

# Verify cluster
kubectl get nodes
kubectl get pods -A

# Check Flux
flux get all
```

## Common Commands

### Development

```bash
# Format code
task fmt

# Run linters
task lint

# Clean artifacts
task clean
```

### Planning

```bash
# See what will change (without applying)
task deploy:oci:plan
task deploy:proxmox:plan
task deploy:talos:plan
```

### Destroy

```bash
# Destroy everything (prompts for confirmation)
task destroy:all

# Or destroy individual layers
task destroy:talos
task destroy:proxmox
task destroy:oci
```

## Dagger Commands (Direct)

You can also call Dagger functions directly:

```bash
# Build images
dagger call build-all-images

# Validate images
dagger call validate-images

# Upload to OCI
dagger call upload-to-oci \
  --bucket my-bucket \
  --compartment-id ocid1.compartment.oc1..xxxxx \
  --region uk-london-1
```

## Troubleshooting

### Dagger not found
```bash
# Ensure you're in dev environment
nix develop  # or: devbox shell

# Verify dagger is available
which dagger
```

### Task not found
```bash
# Ensure you're in dev environment
nix develop  # or: devbox shell

# Verify task is available
which task
```

### OCI CLI not configured
```bash
# Run setup
task setup

# Or configure manually
oci setup config
```

### Images too large
```bash
# Check sizes
task build:validate

# Artifacts should be < 20GB total
```

## CI/CD

The same workflow works in CI:

```yaml
# .github/workflows/deploy.yml
- uses: DeterminateSystems/nix-installer-action@v9
- uses: DeterminateSystems/magic-nix-cache-action@v2

- name: Build images
  run: nix develop --command task build:images

- name: Deploy
  run: nix develop --command task deploy:all
```

## Next Steps

1. Read [DEVELOPMENT.md](../DEVELOPMENT.md) for detailed dev setup
2. Read [ROADMAP.md](../ROADMAP.md) for implementation status
3. Check [WARP.md](../WARP.md) for architecture details

## Support

- GitHub Issues: https://github.com/syscode-labs/oci-free-tier-manager/issues
- Documentation: See `/docs` directory
