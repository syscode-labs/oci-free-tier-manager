# OCI Free Tier Manager

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![CodeQL](https://github.com/syscode-labs/oci-free-tier-manager/workflows/CodeQL/badge.svg)](https://github.com/syscode-labs/oci-free-tier-manager/actions/workflows/codeql.yml)
[![CI](https://github.com/syscode-labs/oci-free-tier-manager/workflows/CI/badge.svg)](https://github.com/syscode-labs/oci-free-tier-manager/actions/workflows/ci.yml)
[![tfsec](https://img.shields.io/badge/tfsec-enabled-blue?logo=terraform)](https://aquasecurity.github.io/tfsec/)
[![Checkov](https://img.shields.io/badge/checkov-enabled-blue?logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZmlsbD0iI2ZmZiIgZD0iTTEyIDJDNi40OCAyIDIgNi40OCAyIDEyczQuNDggMTAgMTAgMTAgMTAtNC40OCAxMC0xMFMxNy41MiAyIDEyIDJ6bTAgMThjLTQuNDEgMC04LTMuNTktOC04czMuNTktOCA4LTggOCAzLjU5IDggOC0zLjU5IDgtOCA4em0tMS0xM2gtMnY2aDJ6bTAgOGgtMnYyaDJ6Ii8+PC9zdmc+)](https://www.checkov.io/)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-1.8-844FBA?logo=terraform)](https://opentofu.org/)
[![Nix](https://img.shields.io/badge/Nix-Devbox-5277C3?logo=nixos)](https://www.jetpack.io/devbox)
[![Task](https://img.shields.io/badge/Task-Automation-29BEB0?logo=task)](https://taskfile.dev/)
[![OCI Free Tier](https://img.shields.io/badge/OCI-Always%20Free-F80000?logo=oracle)](https://www.oracle.com/cloud/free/)

Reproducible infrastructure for Oracle Cloud Infrastructure (OCI) Always Free tier with Kubernetes on Proxmox.

## Overview

Complete infrastructure-as-code toolkit for deploying a production-ready Kubernetes cluster on OCI's free tier using:
- **3 Ampere A1 nodes** (ARM64) running Proxmox VE with Ceph
- **1 Micro bastion** for secure access
- **Talos Linux** for immutable Kubernetes
- **Flux CD** for GitOps
- **Cost**: $0 (with $0.01 budget alert)

## Quick Start

**Status**: Layer 1 (OCI infrastructure) is implemented. Layers 2-3 (Proxmox, Talos) are planned.

```bash
# 1. Install devbox (one-time)
curl -fsSL https://get.jetpack.io/devbox | bash

# 2. Enter development environment
devbox shell  # Installs: task, dagger, opentofu, kubectl, sops, etc.

# 3. Run automated setup (OCI CLI + SSH keys + tfvars)
task setup

# 4. Setup Flux repository (Cilium + SOPS + secrets)
task setup:flux

# 5. Build custom images with Dagger (one-time)
task build:images      # Builds base-hardened + proxmox-ampere
task build:validate    # Validates images < 20GB
task build:upload      # Uploads to OCI (auto-fetches compartment from config)

# 6. Check OCI capacity
./check_availability.py

# 7. Deploy infrastructure
task deploy:oci        # Layer 1: OCI instances ✅ Implemented
task deploy:proxmox    # Layer 2: Proxmox + Ceph 🚧 Planned
task deploy:talos      # Layer 3: Talos K8s 🚧 Planned
```

## Architecture

### Three-Layer OpenTofu Structure

**Layer 1: OCI Infrastructure** (`tofu/oci/`) ✅ **Implemented**
- Provisions bare metal compute instances
- Configures networking (VCN, subnets, security rules)
- Sets up budget alerts

**Layer 2: Proxmox Cluster** (`tofu/proxmox-cluster/`) 🚧 **Planned**
- Forms 3-node Proxmox cluster (pre-installed via Packer)
- Configures Ceph for distributed storage
- Deploys Tailscale as LXC containers

**Layer 3: Talos Kubernetes** (`tofu/talos/`) 🚧 **Planned**
- Deploys Talos VMs on Proxmox
- Bootstraps Kubernetes cluster
- Injects Flux CD for GitOps

## Features

- ✅ **Reproducible**: Nix-based dev environment ([devbox](https://www.jetpack.io/devbox))
- ✅ **Automated**: Pre-commit hooks for linting
- ✅ **Modular**: 3 independent infrastructure layers
- ✅ **GitOps**: Flux CD with SOPS-encrypted secrets
- ✅ **Secure**: Tailscale mesh networking
- ✅ **Observable**: Grafana Cloud integration
- ✅ **Free**: $0 cost with budget monitoring

## Documentation

- **[ARCHITECTURE-DIAGRAMS.md](docs/ARCHITECTURE-DIAGRAMS.md)** - Visual architecture diagrams
- **[DEVELOPMENT.md](DEVELOPMENT.md)** - Development environment setup
- **[WARP.md](WARP.md)** - Complete architecture reference
- **[FREE_TIER_RESOURCES.md](FREE_TIER_RESOURCES.md)** - Complete OCI free tier list
- **[Flux Repository](https://github.com/syscode-labs/oci-free-tier-flux)** - Kubernetes manifests

## Prerequisites

### Development Environment

Use devbox for reproducible tooling:

```bash
devbox shell  # Automatically installs:
# - opentofu, kubectl, helm
# - sops, age (secrets)
# - pre-commit, linters
# - python, jq, yq, gh
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for details.

### OCI Account

1. **Create OCI Account** (PAYG recommended for Ampere availability)
2. **Run automated setup** (configures OCI CLI, generates SSH keys, creates tfvars):
   ```bash
   ./scripts/setup.sh
   ```

## Deployment

### Step 0: Build Custom Images (One-Time)

Build images using Dagger:

```bash
# Build both images (base-hardened + proxmox-ampere)
task build:images

# Validate images meet size requirements (< 20GB total)
task build:validate

# Upload to OCI Object Storage and create custom images
task build:upload  # Auto-fetches compartment ID from OCI config
```

**What this does:**
- Dagger builds `base-hardened.qcow2` (Debian + SSH + Tailscale)
- Dagger builds `proxmox-ampere.qcow2` (base + Proxmox VE + Ceph)
- Validates total size < 20GB (OCI Object Storage free tier limit)
- Uploads to OCI Object Storage
- Creates custom compute images

**Note**: Image OCIDs are automatically referenced in `tofu/oci/data.tf`.

### CI image builds

Packer images are also built in CI via `.github/workflows/packer.yml` on changes under `packer/**`. Configure these repository secrets:
- `PACKER_SSH_PUBLIC_KEY`: SSH public key injected into built images (`root` authorized_keys)
- `TAILSCALE_AUTH_KEY` (optional): Stored in `/etc/default/tailscaled` for first-boot join

Each run publishes `packer/output-base/*.qcow2`, `packer/output-proxmox/*.qcow2`, and a generated `artifacts/IMAGE_BUILD_REPORT.md` as workflow artifacts.

### Step 1: Check Capacity

Ampere instances are often out of capacity:

```bash
./check_availability.py

# Or run periodically
*/30 * * * * /path/to/check_availability.py >> availability.log 2>&1
```

### Step 2: Deploy OCI Infrastructure

```bash
# Review plan
task deploy:oci:plan

# Deploy infrastructure
task deploy:oci  # Deploys 3 Ampere (proxmox-ampere) + 1 Micro (base-hardened)
```

**What this does:**
- Initializes OpenTofu
- Creates VCN, subnet, security lists
- Deploys 3 Ampere A1 instances with Proxmox pre-installed
- Deploys 1 Micro bastion with base hardened image
- Sets up budget alert ($0.01 threshold)

**Outputs**: Instance IPs, SSH commands

**Intervention Point**: Verify instances running, Proxmox UI accessible (https://<ampere-ip>:8006)

### Step 3: Manual Configuration (Coming Soon)

**Layers 2-3 automation is planned.** For now, manually:

1. **SSH into Ampere instances** (use outputs from Step 2)
2. **Form Proxmox cluster** - Follow [WARP.md#proxmox-cluster](WARP.md#proxmox-cluster)
3. **Configure Ceph** - Follow [PLAN.md#configure-ceph](PLAN.md#phase-3-proxmox-cluster-and-ceph)
4. **Deploy Talos VMs** - Follow [WARP.md#talos-kubernetes](WARP.md#talos-kubernetes)
5. **Bootstrap K8s + Flux** - Follow [WARP.md#gitops-with-flux-and-sops](WARP.md#gitops-with-flux-and-sops)

See [PLAN.md](PLAN.md) for complete manual deployment steps.

## OCI Free Tier Resources

### Compute
- **Ampere A1**: 4 OCPUs + 24GB RAM (ARM64, flexible)
- **E2.1.Micro**: 2 instances × 1/8 OCPU + 1GB RAM (AMD, fixed)

### Storage
- **Block volumes**: 200GB total (includes all boot volumes)
- **Object storage**: 20GB
- **Archive storage**: 10GB

### Networking
- **VCNs**: 2
- **Load balancer**: 1 (10 Mbps)
- **Reserved IPs**: 2
- **Egress**: 10TB/month

See [FREE_TIER_RESOURCES.md](FREE_TIER_RESOURCES.md) for complete list.

## Configuration Examples

### Maximum Ampere (188GB storage)

```hcl
ampere_instance_count      = 4
ampere_ocpus_per_instance  = 1
ampere_memory_per_instance = 6
micro_instance_count       = 0
```

### Balanced (3 Ampere + 1 Micro, 200GB storage)

```hcl
ampere_instance_count      = 3
ampere_ocpus_per_instance  = 1.33
ampere_memory_per_instance = 8
micro_instance_count       = 1
ampere_boot_volume_size    = 50
micro_boot_volume_size     = 50
```

## Common Commands

```bash
# Development
devbox shell                 # Enter dev environment
task --list                  # List all available tasks

# Setup
task setup                   # Initial setup (OCI CLI, SSH, tfvars)
task setup:flux              # Setup Flux repository

# Build
task build:images            # Build custom images with Dagger
task build:validate          # Validate image sizes
task build:upload            # Upload to OCI (auto-detects compartment)

# Deploy
task deploy:oci              # Deploy OCI infrastructure (Layer 1)
task deploy:oci:plan         # Preview OCI changes
task deploy:proxmox          # Deploy Proxmox cluster (Layer 2, planned)
task deploy:talos            # Deploy Talos K8s (Layer 3, planned)

# Destroy
task destroy:oci             # Destroy OCI infrastructure

# Kubernetes (after K8s is deployed)
kubectl get nodes            # Check cluster
kubectl get pods -A          # Check all pods
flux get all                 # Check Flux resources
```

## Troubleshooting

### "Out of capacity" for Ampere

Normal - Ampere instances are very popular:
- Run availability checker frequently
- Try different regions (`uk-london-1`, `eu-frankfurt-1`, `us-ashburn-1`)
- Try off-peak hours (late night/early morning)

### Storage limit exceeded

200GB includes all boot volumes:
- 4 Ampere × 47GB = 188GB (leaves 12GB)
- 3 Ampere + 1 Micro × 50GB = 200GB (maxed)

Plan carefully!

### Pre-commit hooks failing

```bash
pre-commit autoupdate
pre-commit install --install-hooks
```

## Contributing

Contributions welcome! Please:
1. Use conventional commits
2. Run `devbox run lint` before committing
3. Update documentation as needed

## Related Repositories

- **[syscode-labs/oci-free-tier-flux](https://github.com/syscode-labs/oci-free-tier-flux)** - Kubernetes GitOps manifests

## License

[MIT License](LICENSE)

## Resources

- [OCI Free Tier Documentation](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
- [OpenTofu Documentation](https://opentofu.org/)
- [Talos Linux Documentation](https://www.talos.dev/)
- [Flux CD Documentation](https://fluxcd.io/)
- [Devbox Documentation](https://www.jetpack.io/devbox/docs/)
