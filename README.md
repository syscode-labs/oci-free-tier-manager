# OCI Free Tier Manager

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![CI](https://github.com/syscode-labs/oci-free-tier-manager/workflows/CI/badge.svg)](https://github.com/syscode-labs/oci-free-tier-manager/actions/workflows/ci.yml)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-1.11-844FBA?logo=terraform)](https://opentofu.org/)
[![OCI Free Tier](https://img.shields.io/badge/OCI-Always%20Free-F80000?logo=oracle)](https://www.oracle.com/cloud/free/)

OpenTofu infrastructure for OCI Always Free tier — provisions 4× Ampere A1.Flex (ARM64) + 1× Micro instance.

Supports two modes via the `omni_ready` toggle:

| Mode | `omni_ready` | OS | Kubernetes |
|------|--------------|----|------------|
| Default | `false` | Ubuntu (custom image) | Bring your own |
| Talos + Omni | `true` | Talos Linux | Enrolled into Omni via SideroLink |

## Structure

```text
tofu/oci/       OpenTofu module — instances, networking, budget
scripts/        Helper scripts (state backend, capacity check)
```

## Quick Start

### Prerequisites

- OCI account (PAYG recommended for Ampere availability)
- OCI CLI configured (`~/.oci/config`)
- OpenTofu ≥ 1.8

### Configure

```bash
cp tofu/oci/terraform.tfvars.example tofu/oci/terraform.tfvars
# Edit terraform.tfvars — set compartment OCID, SSH key, image OCIDs
```

Key variables:

```hcl
# Default (Ubuntu)
omni_ready = false

# Talos + Omni enrollment
omni_ready       = true
talos_image_ocid = "ocid1.image.oc1..."   # auto-fetched from oci-talos-gitops-apps in CI
omni_endpoint    = "omni.example.com:8090"
omni_join_token  = "..."                  # or pass via -var / TF_VAR_omni_join_token
```

### Deploy

```bash
cd tofu/oci
tofu init
tofu plan
tofu apply
```

## Talos Mode

When `omni_ready = true`:

1. Nodes boot Talos Linux (custom OCI image from [oci-free-tier-images](https://github.com/syscode-labs/oci-free-tier-images))
2. `user_data` injects a Talos MachineConfig that joins Omni via SideroLink
3. Omni detects the nodes and provisions the cluster
4. Argo CD GitOps is managed by [oci-talos-gitops-apps](https://github.com/syscode-labs/oci-talos-gitops-apps)

## OCI Free Tier Resources

### Compute

- **Ampere A1**: 4 OCPUs + 24 GB RAM total (ARM64, flexible — split across up to 4 instances)
- **E2.1.Micro**: 2 instances × 1/8 OCPU + 1 GB RAM (AMD)

### Storage

- **Block volumes**: 200 GB total (includes all boot volumes)
- **Object storage**: 20 GB

### Networking

- **VCNs**: 2
- **Load balancer**: 1 (10 Mbps)
- **Egress**: 10 TB/month

## Troubleshooting

### "Out of capacity" for Ampere

Normal — Ampere instances are highly contested. The CI deploy workflow retries
automatically. For manual deployments:

- Re-run `tofu apply` — OCI eventually allocates capacity
- Try a different availability domain within the same region
- Try off-peak hours

### Storage limit exceeded

200 GB includes all boot volumes. Example allocations:

- 4× Ampere at 47 GB = 188 GB (leaves 12 GB)
- 3× Ampere + 1× Micro at 50 GB = 200 GB (maxed)

## Related Repositories

- **[oci-free-tier-images](https://github.com/syscode-labs/oci-free-tier-images)** —
  Custom OS images (Talos, Debian) built for OCI import
- **[oci-talos-gitops-apps](https://github.com/syscode-labs/oci-talos-gitops-apps)** —
  Argo CD GitOps apps for the Talos cluster

## License

[MIT License](LICENSE)
