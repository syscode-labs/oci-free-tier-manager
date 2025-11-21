# OCI Free Tier Manager

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Reproducible infrastructure for Oracle Cloud Infrastructure (OCI) Always Free tier with Kubernetes on Proxmox.

## Overview

Complete infrastructure-as-code toolkit for deploying a production-ready Kubernetes cluster on OCI's free tier using:
- **3 Ampere A1 nodes** (ARM64) running Proxmox VE with Ceph
- **1 Micro bastion** for secure access
- **Talos Linux** for immutable Kubernetes
- **Flux CD** for GitOps
- **Cost**: $0 (with $0.01 budget alert)

## Quick Start

```bash
# 1. Install devbox (one-time)
curl -fsSL https://get.jetpack.io/devbox | bash

# 2. Enter development environment
devbox shell  # Installs all tools automatically

# 3. Check OCI capacity
./check_availability.py

# 4. Deploy infrastructure (3 independent layers)
cd tofu/oci && tofu apply          # Layer 1: OCI instances
cd ../proxmox-cluster && tofu apply  # Layer 2: Proxmox + Ceph
cd ../talos && tofu apply            # Layer 3: Talos K8s
```

## Architecture

### Three-Layer OpenTofu Structure

**Layer 1: OCI Infrastructure** (`tofu/oci/`)
- Provisions bare metal compute instances
- Configures networking (VCN, subnets, security rules)
- Sets up budget alerts

**Layer 2: Proxmox Cluster** (`tofu/proxmox-cluster/`)
- Installs Proxmox VE via Ansible
- Forms 3-node cluster
- Configures Ceph for distributed storage

**Layer 3: Talos Kubernetes** (`tofu/talos/`)
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

- **[DEVELOPMENT.md](DEVELOPMENT.md)** - Development environment setup
- **[WARP.md](WARP.md)** - Architecture and planning
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
2. **Configure OCI CLI**:
   ```bash
   oci setup config
   ```
3. **Generate SSH Key**:
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/oci_key
   ```

## Deployment

### Step 1: Check Capacity

Ampere instances are often out of capacity:

```bash
./check_availability.py

# Or run periodically
*/30 * * * * /path/to/check_availability.py >> availability.log 2>&1
```

### Step 2: Deploy OCI Infrastructure

```bash
cd tofu/oci
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars  # Add OCI credentials

tofu init
tofu plan
tofu apply
```

**Outputs**: Instance IPs, SSH commands

**Intervention Point**: Verify instances running before continuing

### Step 3: Deploy Proxmox Cluster

```bash
cd ../proxmox-cluster
tofu init
tofu apply  # Installs Proxmox, forms cluster, configures Ceph
```

**Outputs**: Proxmox API endpoint, credentials

**Intervention Point**: Access Proxmox UI, verify cluster quorum

### Step 4: Deploy Talos Kubernetes

```bash
cd ../talos
tofu init
tofu apply  # Creates VMs, bootstraps K8s, deploys Flux
```

**Outputs**: Kubeconfig, cluster endpoints

**Intervention Point**: Check cluster before Flux takes over

### Step 5: Flux Deploys Infrastructure

Flux automatically deploys:
- Cilium CNI (kube-proxy-free)
- Tailscale Operator
- OCI Cloud Controller Manager
- NVIDIA Device Plugin (if GPU enabled)
- Grafana Alloy (monitoring)

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
devbox shell                    # Enter dev environment
devbox run fmt                  # Format all code
devbox run lint                 # Run all linters
pre-commit run --all-files      # Run pre-commit hooks

# Infrastructure
cd tofu/oci && tofu apply       # Deploy OCI layer
cd tofu/proxmox-cluster && tofu apply  # Deploy Proxmox layer
cd tofu/talos && tofu apply     # Deploy Talos layer

# Kubernetes
kubectl get nodes               # Check cluster
kubectl get pods -A             # Check all pods
flux get all                    # Check Flux resources
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
