# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

This is an OCI (Oracle Cloud Infrastructure) Free Tier management toolkit that maximizes Always Free resources. The project consists of:
- **Python availability checker** (`check_availability.py`) - monitors when free tier compute instances become available
- **Terraform infrastructure** (`terraform/`) - provisions free tier resources with budget alerts
- **Documentation** - comprehensive guides on OCI Always Free resources

**Account Type:** This project works with both:
- **Always Free tier**: No credit card required, but Ampere instances often unavailable
- **PAYG (Pay-As-You-Go)**: Requires credit card, but Always Free resources remain free forever
  - Same free tier limits apply (4 OCPU Ampere, 2 Micro, 200GB storage, etc.)
  - Better Ampere A1 instance availability (much easier to provision)
  - Budget alerts ($0.01 threshold) protect against accidental charges
  - Recommended if you can't get Always Free tier capacity

**Important:** Always Free resources are identical in both account types - they never expire and cost $0. PAYG just gives better capacity availability.

## Essential Commands

### Availability Checker
```bash
# Run availability check (must have OCI CLI configured)
./check_availability.py

# Set up periodic monitoring (cron)
*/30 * * * * /path/to/check_availability.py >> /path/to/availability.log 2>&1
```

### Terraform Workflow
```bash
# Initialize (first time only)
cd terraform
terraform init

# Preview changes
terraform plan

# Deploy infrastructure
terraform apply

# Destroy all resources
terraform destroy

# Format and validate
terraform fmt
terraform validate

# View outputs
terraform output
terraform output -json > outputs.json
```

### Prerequisites Check
```bash
# Verify OCI CLI is configured
oci iam region list

# Verify Terraform is installed
terraform version
```

## Architecture

### Python Availability Checker (`check_availability.py`)
- Uses OCI CLI to query compute capacity reports
- Checks both Ampere A1 (ARM) and E2.1.Micro (AMD) instance availability
- Returns exit code 0 if capacity available, 1 otherwise
- Can be integrated into automation scripts for immediate deployment when capacity opens
- Reads tenancy ID from `~/.oci/config` (hardcoded path at line 149)

**Key functions:**
- `check_ampere_availability()` - queries VM.Standard.A1.Flex capacity
- `check_micro_availability()` - queries VM.Standard.E2.1.Micro capacity
- `get_availability_domains()` - lists all ADs in region

### Terraform Infrastructure (`terraform/`)

**File structure follows standard practices:**
- `main.tf` - primary resource definitions (VCN, compute, storage, budgets)
- `variables.tf` - input variable declarations with validation
- `data.tf` - data sources (availability domains, OS images)
- `outputs.tf` - output values (IPs, SSH commands)
- `terraform.tfvars.example` - example configuration (copy to `terraform.tfvars`)

**Resource architecture:**
1. **Networking layer** - VCN, subnet, internet gateway, route table, security list (SSH/HTTP/HTTPS/ICMP)
2. **Compute layer** - Ampere A1 instances (ARM64, flexible) and E2.1.Micro instances (x86, fixed)
3. **Storage layer** - boot volumes (min 47GB) and optional additional block volumes
4. **Budget layer** - budget alerts at $0.01 threshold to detect any charges

**Free tier limits enforced:**
- Ampere: max 4 OCPUs, 24GB RAM total (distributed across instances)
- Micro: max 2 instances, fixed shape (1/8 OCPU, 1GB RAM each)
- Storage: 200GB total including all boot volumes and block volumes

**Key design decisions:**
- Uses Ubuntu 22.04 for both Ampere and Micro instances
- All instances in availability domain [0] by default
- Public IPs auto-assigned for internet access (ephemeral, not reserved)
- Security list allows ingress on 22, 80, 443, and ICMP
- Lifecycle ignores image source changes to prevent unintended replacements
- Budget targets compartment-level costs

**Reserved IPs:** Free tier includes 2 reserved (static) public IPs, but current config uses ephemeral IPs. To create reserved IPs for bastion/ingress, add `oci_core_public_ip` resources and reference them in instance VNICs.

## OCI-Specific Context

### Ampere A1 Availability
Ampere instances are frequently out of capacity. The availability checker is designed to run repeatedly until capacity opens. Strategies:
- Run checker every 15-30 minutes via cron
- Try different regions by changing `region` variable
- Capacity tends to open during off-peak hours

### Storage Calculations
Example: 4 Ampere instances × 47GB boot = 188GB, leaving only 12GB for additional volumes.

### Terraform Variable Validation
All variables include validation blocks. Key validations:
- `ampere_instance_count`: 0-4
- `ampere_ocpus_per_instance`: 1-4 (total must be ≤4)
- `ampere_memory_per_instance`: 1-24 (total must be ≤24)
- `micro_instance_count`: 0-2
- Boot volumes: 47-200 GB minimum

## Common Patterns

### Optimal Instance Configurations

**IMPORTANT:** You cannot deploy 4 Ampere + 2 Micro due to storage limits. Each instance requires minimum 47GB boot volume:
- 4 Ampere + 2 Micro = 282GB total (exceeds 200GB limit)

**Maximum realistic configuration: 4 Ampere instances only** (188GB storage used)
```hcl
ampere_instance_count      = 4
ampere_ocpus_per_instance  = 1
ampere_memory_per_instance = 6
micro_instance_count       = 0
ampere_boot_volume_size    = 47
```

**Recommended for most workloads: 1 powerful Ampere + 2 Micro** (141GB storage used)
```hcl
ampere_instance_count      = 1
ampere_ocpus_per_instance  = 4
ampere_memory_per_instance = 24
micro_instance_count       = 2
ampere_boot_volume_size    = 47
micro_boot_volume_size     = 47
```
This gives you a powerful ARM server plus two x86 instances for utilities/monitoring.

**Balanced: 2 medium Ampere + 2 Micro** (188GB storage used)
```hcl
ampere_instance_count      = 2
ampere_ocpus_per_instance  = 2
ampere_memory_per_instance = 12
micro_instance_count       = 2
ampere_boot_volume_size    = 47
micro_boot_volume_size     = 47
```

**Recommended for K8s (3-node cluster + bastion): 3 Ampere + 1 Micro** (200GB storage, maxed)
```hcl
ampere_instance_count      = 3
ampere_ocpus_per_instance  = 1.33  # Total: 3.99 OCPUs (maxed)
ampere_memory_per_instance = 8     # Total: 24GB RAM (maxed)
micro_instance_count       = 1
ampere_boot_volume_size    = 50    # Total: 200GB storage (maxed)
micro_boot_volume_size     = 50
```

**Architecture reasoning:**
- **3 Ampere nodes**: Provides K8s quorum (3 nodes for etcd/control plane redundancy)
  - Each node runs Proxmox as hypervisor
  - Talos Linux VMs run on top of Proxmox for K8s cluster
  - Tailscale runs as LXC container in each Proxmox host for mesh networking
  - 1.33 OCPUs per node = ~4 OCPUs total (maxed free tier)
  - 8GB RAM per node = 24GB total (maxed free tier)
  - 50GB storage per node = 200GB total with bastion (maxed free tier)
- **1 Micro bastion**: Hardened minimal Linux distro for SSH access and management
  - Not part of K8s cluster (1GB RAM insufficient for K8s)
  - Acts as jump host to access internal cluster nodes
  - Runs Tailscale for secure mesh networking
  - Provides secure entry point into the infrastructure
  - **OS**: Same base as Ampere nodes (Debian 12 or Ubuntu 22.04) for consistency
  - Hardened via cloud-init/Ansible post-deployment
  - Region: **uk-london-1** (closest to UK) or eu-frankfurt-1

**Why common base image:**
- Proxmox requires Debian/Ubuntu (not compatible with DietPi or minimal distros)
- Using same OCI platform image (Debian 12 or Ubuntu 22.04) for all 4 nodes ensures:
  - Proxmox compatibility on Ampere nodes
  - Consistent tooling and package management
  - Simpler deployment (single image source)
- Differentiation via cloud-init: Proxmox install on Ampere, hardening on Micro

**Networking architecture:**
- **Tailscale mesh**: All nodes (bastion + 3 Ampere) connected via Tailscale for secure internal communication
- **Proxmox Tailscale deployment**: Tailscale runs as LXC containers on Proxmox hosts (not directly on host OS)
- **Public access**: Only bastion and ingress controller have public IPs

**IP allocation strategy (2 reserved IPs):**
1. **Reserved IP #1 → Micro bastion**: Static IP for consistent SSH access
2. **Reserved IP #2 → K8s ingress**: Assigned to ingress controller VM running on one of the Ampere nodes
   - Ingress controller runs as VM inside Proxmox on an Ampere node
   - Provides external access to K8s services
   - Static IP ensures DNS records remain valid
3. **Ephemeral IPs → Remaining Ampere nodes**: Used for initial setup and OCI management access

### Automated Deployment on Availability
```bash
if ./check_availability.py; then
    cd terraform && terraform apply -auto-approve
fi
```

### SSH Access
After deployment, get SSH commands:
```bash
terraform output ssh_connection_commands
```

## Important Constraints

### Free Tier Limits (Never Exceed These)

1. **Compute:**
   - Ampere A1: 4 OCPUs + 24GB RAM total (flexible)
   - E2.1.Micro: 2 instances max (fixed: 1/8 OCPU, 1GB RAM each)

2. **Storage:**
   - Block volumes: 200GB total (includes ALL boot volumes + block volumes)
   - Object Storage: 20GB total (for custom images)
   - Archive Storage: 10GB total

3. **Networking:**
   - 2 VCNs max
   - 1 Load Balancer (10 Mbps) - **not currently used**
   - 2 reserved public IPs
   - 10 TB/month outbound transfer

4. **Other Services (not currently used, available for future):**
   - 2 Autonomous Databases (20GB each, 1 OCPU each)
   - NoSQL: 133M reads/writes per month, 25GB per table (3 tables max)
   - Logging: 10GB/month
   - Monitoring: 500M ingestion datapoints, 1B retrieval

### Safety Checks

**Before deploying:**
- Verify Terraform plan shows only Always Free resources
- Check total storage: `(ampere_count × ampere_boot_size) + (micro_count × micro_boot_size) ≤ 200GB`
- Check total OCPUs: `ampere_count × ampere_ocpus ≤ 4`
- Check total RAM: `ampere_count × ampere_memory ≤ 24GB`

**After Packer builds:**
- Verify Object Storage usage: `base-hardened.qcow2 + proxmox-ampere.qcow2 ≤ 20GB`
- Check with: `oci os object list --bucket-name <bucket> --query 'data[]."size"' | jq 'add'`

**Budget alert (CRITICAL for PAYG):**
- Set at $0.01 to catch any charges immediately
- Requires valid email in `budget_alert_email` variable
- Budget creation requires tenancy administrator privileges

**OCI CLI authentication:**
- Python script requires OCI CLI configured: `oci setup config`
- Config file expected at `~/.oci/config`
- Terraform requires API key credentials in `terraform.tfvars`

## Custom Image Building with Packer

### Layered Image Strategy

Build images in layers for consistency and reusability:

**Layer 1: Base Image (Debian hardened + SSH + Tailscale)**
```bash
packer build base-hardened.pkr.hcl
```
- Start from Debian 12 netinstall or minimal
- Harden: minimal packages, SSH config, firewall rules, security updates
- Pre-install: Tailscale, essential tools
- Output: `base-hardened.qcow2`

**Layer 2a: Bastion Image (use base as-is)**
- Deploy base image directly to Micro instance
- No additional layers needed

**Layer 2b: Proxmox Image (base + Proxmox)**
```bash
packer build -var 'source_image=base-hardened.qcow2' proxmox.pkr.hcl
```
- Start from base hardened image
- Install Proxmox VE via official script
- Configure for Talos/LXC containers
- Output: `proxmox-ampere.qcow2`

**Deployment Workflow:**
1. Build `base-hardened.qcow2` with Packer
2. Build `proxmox-ampere.qcow2` from base with Packer
3. Upload both to OCI Object Storage (free tier: 20GB)
4. Create custom images via OCI CLI
5. Reference OCIDs in Terraform:
   - Micro bastion: base-hardened image
   - Ampere nodes: proxmox-ampere image

**Benefits:**
- Common hardened base for all nodes
- Proxmox compatibility guaranteed
- Fully reproducible and automated
- Can rebuild either layer independently

## Monitoring Stack Deployment

**Final deployment step:** Deploy Grafana Cloud agents to K8s cluster

**Architecture:** Use **Grafana Cloud Free Tier** with local agents only (no self-hosted Grafana/Loki/Prometheus)

### Stack Components

**Grafana Cloud (hosted, free tier):**
- Grafana dashboards and visualization
- Loki for log storage (50GB/month free)
- Prometheus/Mimir for metrics (10k series free)
- Traces storage (50GB/month free)

**Local agents (deployed on Talos K8s):**
1. **Grafana Alloy**: Unified observability agent (DaemonSet)
   - Collects logs, metrics, and traces
   - Replaces separate Promtail + Prometheus agents
2. **Grafana Agent** (alternative): If specific integrations needed

### Architecture

**Data flow:**
- Alloy agents (DaemonSet on K8s) → collect from:
  - Proxmox hosts (via Proxmox API)
  - Talos nodes (node metrics, logs)
  - K8s cluster (kube-state-metrics, pod logs)
  - Tailscale mesh status
  - OCI resources (via OCI API)
- Alloy → remote write to Grafana Cloud:
  - Logs → Grafana Loki (cloud)
  - Metrics → Grafana Prometheus/Mimir (cloud)
  - Traces → Grafana Tempo (cloud)

**Visualization:**
- Grafana Cloud dashboards for:
  - Proxmox host metrics (CPU, RAM, storage, VMs)
  - Talos/K8s cluster health
  - Application logs
  - Network/Tailscale connectivity

### Deployment Approach

**Prerequisites:**
1. Create Grafana Cloud account (free tier)
2. Get Grafana Cloud credentials:
   - Prometheus remote write endpoint + API key
   - Loki endpoint + API key
   - Tempo endpoint + API key (optional)

**Deploy Grafana Alloy (recommended):**
```bash
# Add Grafana Helm repo
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Create namespace
kubectl create namespace monitoring

# Deploy Alloy with Grafana Cloud config
helm install alloy grafana/alloy \
  --namespace monitoring \
  --set config.remoteWrite.url=<GRAFANA_CLOUD_PROMETHEUS_URL> \
  --set config.remoteWrite.username=<GRAFANA_CLOUD_USER> \
  --set config.remoteWrite.password=<GRAFANA_CLOUD_API_KEY> \
  --set config.loki.url=<GRAFANA_CLOUD_LOKI_URL>
```

**Alternative: Deploy Grafana Agent:**
```bash
helm install grafana-agent grafana/grafana-agent \
  --namespace monitoring \
  --values grafana-agent-values.yaml
```

**Grafana Cloud Free Tier Limits:**
- **Metrics**: 10,000 series (Prometheus/Mimir)
- **Logs**: 50GB/month ingestion (Loki)
- **Traces**: 50GB/month ingestion (Tempo)
- **Users**: 3 users
- **Retention**: 14 days (metrics), 14 days (logs)

**Constraints:**
- Stay within Grafana Cloud free tier limits (monitor usage in Grafana Cloud UI)
- Only agents run on K8s cluster (minimal resource usage)
- No local storage needed for metrics/logs (stored in Grafana Cloud)
- Configure sampling/filtering in Alloy to stay within limits

**Cost:** $0 - Grafana Cloud free tier + lightweight agents on OCI free tier K8s cluster

## File Modification Guidelines

### When modifying Terraform files:
- Keep file header comments describing purpose
- Store locals in separate `locals.tf` if complexity warrants (not currently needed)
- Create separate data files for complex data resources (current `data.tf` is appropriately sized)
- Avoid heredocs for policies - use data policy documents instead
- Follow conventional commits when committing changes

### When modifying Python script:
- Maintain docstrings for all functions
- Keep timestamp logging format consistent
- Exit code 0 = capacity available, 1 = not available (critical for scripting)
- Update hardcoded path (`/Users/giovanni/.oci/config`) to use environment variable or parameter for portability
