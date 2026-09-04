# OCI Free Tier Manager

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![CI](https://github.com/syscode-labs/oci-free-tier-manager/workflows/CI/badge.svg)](https://github.com/syscode-labs/oci-free-tier-manager/actions/workflows/ci.yml)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-1.11-844FBA?logo=terraform)](https://opentofu.org/)
[![OCI Free Tier](https://img.shields.io/badge/OCI-Always%20Free-F80000?logo=oracle)](https://www.oracle.com/cloud/free/)

OpenTofu infrastructure for OCI Always Free tier - provisions Ampere A1.Flex
(ARM64) by default, with E2.1.Micro instances opt-in via `micro_nodes`.

Supports two modes via the `omni_ready` toggle:

| Mode           | `omni_ready` | OS                    | Kubernetes                        |
|----------------|--------------|-----------------------|-----------------------------------|
| Default        | `false`      | Ubuntu (custom image) | Bring your own                    |
| Talos + Omni   | `true`       | Talos Linux           | Enrolled into Omni via SideroLink |

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
talos_image_ocid = "ocid1.image.oc1..."   # explicit immutable custom-image identity
omni_endpoint    = "omni.example.com:8090"
omni_join_token  = "..."                  # or pass via -var / TF_VAR_omni_join_token

# Optional K8s ingress reserved IP (default: disabled)
create_ingress_ip = true
```

### Deploy

```bash
cd tofu/oci
tofu init
tofu plan
tofu apply
```

### Coordinator release receiver

`.github/workflows/release-dispatch.yml` accepts only a complete, controller-originated
`talos-release-request`. It binds the approved source SHA, Talos version, build run,
OCI image OCID, installer reference, and manifest digest before it can dispatch
`deploy.yml`. The request must carry an explicit `oci_scope` whose targets are only
the two `oci_core_instance.ampere_instance` Talos addresses; Micro instances,
networking, and empty scopes are rejected. Replacements are disabled unless the
approved scope names the same exact Talos target.

The receiver reserves each `release_id` as a GitHub Deployment before dispatching,
so a duplicate delivery is reported as failure rather than repeating a replacement.
Coordinator deploys still use the existing plan/destructive-change gates and add a
live-inventory plus plan-wide Always Free capacity check. A coordinator result is
successful only after the configured authenticated private health endpoint confirms
the matching release ID/version, Omni and Talos health for exactly the scoped nodes,
and Kubernetes API/node readiness. If `OMNI_RELEASE_HEALTHCHECK_URL` or
`OMNI_RELEASE_HEALTHCHECK_TOKEN` is absent, the deployment fails closed instead of
claiming completion.

## Talos Mode

When `omni_ready = true`:

1. Nodes boot Talos Linux (custom OCI image from [oci-free-tier-images](https://github.com/syscode-labs/oci-free-tier-images))
2. `user_data` injects a Talos MachineConfig that joins Omni via SideroLink
3. Omni detects the nodes and provisions the cluster
4. Argo CD GitOps is managed by [syscode-homelab-gitops-apps](https://github.com/syscode-labs/syscode-homelab-gitops-apps)

## OCI Free Tier Resources

### Compute

- **Ampere A1**: 2 OCPUs + 12 GB RAM total (ARM64, flexible — split across up to 2 instances)
- **E2.1.Micro**: 2 instances × 1/8 OCPU + 1 GB RAM (AMD/x86, fixed shape — a
  separate Always Free pool, independent of the A1 allowance)

This module deploys the full Always Free allotment (two separate pools):

- `ampere_nodes`: 2 x A1.Flex (Talos nodes, 1 OCPU / 6 GB each) → uses all
  2 OCPUs / 12 GB of the A1 pool
- `micro_nodes`: 2 x E2.1.Micro (AMD/x86, fixed 1/8 OCPU + 1 GB each — a pool
  separate from A1) → Micro #1 (`oci-micro-01`) is the public-subnet knockd SSH
  bastion (reserved IP `141.147.87.29`); Micro #2 is the Tailscale subnet router
  in `oci-vpn-subnet` advertising REDACTED_PRIVATE_SUBNET (opt in via
  `enable_oci_vpn_probe=true`). The VPN router's egress path is the VPN-subnet
  NAT gateway route, NOT the bastion. No instance carries two VNICs.

This module deploys the full Always Free allotment:

- `ampere_nodes`: 2 x A1.Flex (Talos nodes) → uses all 2 OCPUs / 12 GB
- `micro_nodes`: 1 x E2.1.Micro (`oci-micro-01`); the bastion runs VPN probes
  through scoped DRG routes without requiring a second Micro instance

### Storage

- **Block volumes**: 200 GB total (includes all boot volumes — shared across Ampere *and* Micro instances)
- **Object storage**: 20 GB

Current footprint: 2×50 (Ampere) + 2×50 (Micro) = **200 GB used, at the hard limit**.

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
- 3x Ampere at 50 GB = 150 GB (default)
- 3x Ampere + 1x Micro at 50 GB = 200 GB (maxed; opt in with `micro_nodes = [{}]`)

## Related Repositories

- **[oci-free-tier-images](https://github.com/syscode-labs/oci-free-tier-images)** —
  Custom OS images (Talos, Debian) built for OCI import
- **[syscode-homelab-gitops-apps](https://github.com/syscode-labs/syscode-homelab-gitops-apps)** —
  Argo CD GitOps apps for the Talos cluster

## License

[MIT License](LICENSE)
