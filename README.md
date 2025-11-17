# OCI Free Tier Manager

A comprehensive toolkit for maximizing Oracle Cloud Infrastructure (OCI) Always Free tier resources.

## Table of Contents

- [Overview](#overview)
- [OCI Always Free Resources](#oci-always-free-resources)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Availability Checker](#availability-checker)
- [Terraform Configuration](#terraform-configuration)
- [Budget Alerts](#budget-alerts)
- [Important Considerations](#important-considerations)

## Overview

This project provides:

1. **Availability Checker**: Python script to monitor when free tier compute instances become available
2. **Terraform Configurations**: Infrastructure-as-Code to provision free tier resources with budget alerts
3. **Packer Image Building**: Custom images for Proxmox hypervisor and hardened bastion
4. **Kubernetes Deployment**: 3-node K8s cluster on Proxmox with Talos Linux
5. **Monitoring Stack**: Grafana Cloud integration with Alloy agents
6. **Documentation**: Complete list of all OCI Always Free resources

## Deployment Architecture

This project deploys a complete Kubernetes infrastructure on OCI's Always Free tier:

**Infrastructure**: 3 Ampere A1 nodes (ARM64) + 1 E2.1.Micro bastion (x86)
- Region: uk-london-1 (closest to UK)
- Total resources: 4 OCPUs, 24GB RAM, 200GB storage (all maxed)
- Account type: PAYG recommended (better Ampere availability, $0.01 budget alert)

**Hypervisor Layer**: Proxmox VE cluster on 3 Ampere nodes
- Proxmox cluster with 3-node quorum for high availability
- Ceph distributed storage for VM live migration
- Tailscale mesh networking via LXC containers

**Kubernetes Layer**: Talos Linux VMs on Proxmox
- 3-node K8s cluster with etcd quorum
- Runs on Ceph-backed storage
- Ingress controller with reserved public IP

**Bastion**: Hardened Debian minimal on Micro instance
- SSH jump host with reserved public IP
- Tailscale for secure mesh networking
- Hardened via cloud-init/Ansible

**Monitoring**: Grafana Cloud free tier
- Alloy agents on K8s cluster
- Monitors: Proxmox, Ceph, K8s, Tailscale, OCI resources
- 10k metrics, 50GB logs/month (free tier)

## OCI Always Free Resources

Based on official Oracle documentation (verified November 2024), the following resources are **always free**:

### Compute

- **Ampere A1 Compute** (ARM-based)
  - 4 OCPUs and 24 GB of memory total
  - Can be split across up to 4 instances
  - Examples:
    - 4 instances with 1 OCPU and 6 GB RAM each
    - 2 instances with 2 OCPUs and 12 GB RAM each
    - 1 instance with 4 OCPUs and 24 GB RAM

- **VM.Standard.E2.1.Micro** (AMD-based, x86)
  - 2 instances maximum
  - 1/8 OCPU and 1 GB RAM per instance
  - Can only be created in one availability domain

### Storage

- **Block Volume**: 200 GB total combined storage
  - Includes boot volumes and block volumes
  - Minimum boot volume size: 47 GB per instance
  - 5 volume backups included

- **Object Storage**: 
  - 20 GB total storage
  - 50,000 API requests per month

- **Archive Storage**: 
  - 10 GB total storage

### Networking

- **VCN (Virtual Cloud Network)**: 2 VCNs
- **Load Balancer**: 1 Load Balancer (10 Mbps)
- **Public IPv4 Address**: 2 reserved public IPs
- **Outbound Data Transfer**: 10 TB per month

### Databases

- **Autonomous Database**: 2 databases
  - 20 GB storage per database
  - 1 OCPU per database
  - Autonomous Transaction Processing or Autonomous Data Warehouse

- **NoSQL Database**: 
  - 133 million reads per month
  - 133 million writes per month
  - 25 GB storage per table (up to 3 tables)

### Additional Services

- **Email Delivery**: 1,000 emails sent per month (3,000 emails per day)
- **Notifications**: 1 million notification options per month
- **Monitoring**: 500 million ingestion datapoints, 1 billion retrieval datapoints
- **Logging**: 10 GB per month
- **Resource Manager**: Managed Terraform
- **Service Connector Hub**: 2 service connectors
- **Vault**: 20 key versions, 150 secrets
- **VPN Connect**: 50 IPSec connections
- **Bastion**: 5 OCI Bastion instances
- **GoldenGate Stream Analytics**: 1 OCPU

## Deployment Phases

The deployment follows a sequential, multi-phase approach:

### Phase 1: Image Building with Packer

Build custom images using a layered approach:

**Base Image** (`base-hardened.qcow2`):
- Debian 12 minimal installation
- Hardened SSH configuration and firewall
- Pre-installed Tailscale for mesh networking
- Used by: Micro bastion (as-is)

**Proxmox Image** (`proxmox-ampere.qcow2`):
- Built from base-hardened image
- Proxmox VE hypervisor installed
- Ceph packages pre-installed (ceph-mon, ceph-osd, ceph-mgr)
- Configured for Talos VMs and LXC containers
- Used by: 3 Ampere nodes

**Image Storage**: Both images uploaded to OCI Object Storage (within 20GB free tier limit)

### Phase 2: Infrastructure Provisioning with Terraform

Deploy OCI infrastructure:

**Compute Instances**:
- 3 Ampere nodes: 1.33 OCPU, 8GB RAM, 50GB storage each
- 1 Micro bastion: 1GB RAM, 50GB storage
- Total: 200GB storage (maxed), 4 OCPUs (maxed), 24GB RAM (maxed)

**Networking**:
- VCN with public subnet, internet gateway, security lists
- 2 reserved public IPs (bastion + K8s ingress)
- Ephemeral IPs for Ampere nodes (setup/management)
- Tailscale mesh connecting all nodes

**Budget Alert**: $0.01 threshold to catch any accidental charges

### Phase 3: Proxmox Cluster and Ceph Setup

Configure Proxmox cluster for high availability:

**Proxmox Cluster**:
- Form 3-node Proxmox cluster
- Verify cluster quorum (requires 3 nodes minimum)
- Deploy Tailscale as LXC containers on each node

**Ceph Distributed Storage**:
- Initialize Ceph monitors on all 3 nodes
- Create Ceph OSDs from available storage
- Configure Ceph pool for VM storage
- Verify VM live migration capability

**Critical**: This phase must complete before deploying Talos VMs. Ceph provides the distributed storage needed for VM migration.

### Phase 4: Talos Kubernetes Deployment

Deploy Kubernetes cluster:

**Talos Linux VMs**:
- Deploy Talos VMs on Proxmox cluster
- VMs stored on Ceph distributed storage
- Bootstrap 3-node K8s cluster
- K8s etcd quorum (separate from Proxmox quorum)

**Ingress Configuration**:
- Deploy K8s ingress controller
- Assign reserved public IP #2 to ingress
- Configure DNS for external access

### Phase 5: Monitoring Stack

Deploy observability:

**Grafana Cloud Setup**:
- Create Grafana Cloud free tier account
- Get API keys for Prometheus, Loki, Tempo

**Alloy Agent Deployment**:
- Deploy Alloy as DaemonSet on K8s cluster
- Configure remote write to Grafana Cloud
- Collect metrics from: Proxmox, Ceph, K8s, Tailscale, OCI
- Collect logs from all nodes and pods

**Dashboards**:
- Proxmox host metrics (CPU, RAM, storage, VMs)
- Ceph cluster health and performance
- K8s cluster and workload metrics
- Application logs via Loki
- Network connectivity and Tailscale status

## Project Structure

```
oci-free-tier-manager/
├── README.md                      # This file
├── WARP.md                        # AI agent guidance
├── FREE_TIER_RESOURCES.md         # Detailed list of all free resources
├── check_availability.py          # Script to check instance availability
├── terraform/
│   ├── main.tf                    # Main Terraform configuration
│   ├── variables.tf               # Input variables
│   ├── outputs.tf                 # Output values
│   ├── data.tf                    # Data sources
│   └── terraform.tfvars.example   # Example configuration
├── packer/                        # (To be created)
│   ├── base-hardened.pkr.hcl     # Base image with SSH + Tailscale
│   └── proxmox-ampere.pkr.hcl    # Proxmox + Ceph image
└── .gitignore                     # Git ignore file
```

## Prerequisites

### For Availability Checker

1. **Python 3.7+**
2. **OCI CLI**:
   ```bash
   pip install oci-cli
   ```
3. **OCI Configuration**:
   ```bash
   oci setup config
   ```

### For Terraform

1. **Terraform 1.0+**
   - macOS: `brew install terraform`
   - Linux: Download from [terraform.io](https://www.terraform.io/downloads)

2. **OCI Provider Configuration**:
   - Tenancy OCID
   - User OCID
   - API key fingerprint
   - Private key file

3. **SSH Key Pair**:
   ```bash
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/oci_key
   ```

## Quick Start

### 1. Clone and Setup

```bash
cd oci-free-tier-manager
```

### 2. Configure OCI CLI

```bash
oci setup config
```

This will prompt you for:
- User OCID
- Tenancy OCID
- Region
- Generate API key (if needed)

### 3. Check Availability

```bash
./check_availability.py
```

Run this periodically to monitor when free tier capacity becomes available. You can set up a cron job:

```bash
# Check every 30 minutes
*/30 * * * * /path/to/check_availability.py >> /path/to/availability.log 2>&1
```

### 4. Deploy with Terraform

```bash
cd terraform

# Copy and edit configuration
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars  # Add your OCI credentials and preferences

# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Deploy resources
terraform apply
```

## Availability Checker

The `check_availability.py` script monitors OCI compute instance availability in real-time.

### Features

- Checks Ampere A1 (ARM) availability across all availability domains
- Checks E2.1.Micro (AMD) availability
- Returns exit code 0 if capacity available, 1 otherwise
- Logs all activity with timestamps

### Usage

```bash
# Basic check
./check_availability.py

# Use in scripts
if ./check_availability.py; then
    echo "Capacity available! Deploy now."
    cd terraform && terraform apply -auto-approve
fi
```

### Example Output

```
[2024-11-13 20:58:22] ============================================================
[2024-11-13 20:58:22] OCI Free Tier Availability Checker
[2024-11-13 20:58:22] ============================================================
[2024-11-13 20:58:22] Using compartment: ocid1.tenancy.oc1..xxx
[2024-11-13 20:58:23] Fetching availability domains...
[2024-11-13 20:58:24] Found 3 availability domains
[2024-11-13 20:58:24] 
[2024-11-13 20:58:24] Checking availability domain: ABC-AD-1
[2024-11-13 20:58:25] Checking Ampere A1 availability in ABC-AD-1...
[2024-11-13 20:58:26] Ampere A1 status: AVAILABLE
[2024-11-13 20:58:26] ✓ Ampere A1 instances are AVAILABLE!
```

## Terraform Configuration

### Default Configuration

The default `terraform.tfvars.example` creates:

- 4x Ampere A1 instances (1 OCPU, 6 GB RAM each)
- 2x E2.1.Micro instances (AMD)
- VCN with public subnet
- Internet gateway and route table
- Security rules (SSH, HTTP, HTTPS, ICMP)
- Budget alert ($0.01 threshold)

### Customization Examples

#### Single Large Ampere Instance

```hcl
ampere_instance_count      = 1
ampere_ocpus_per_instance  = 4
ampere_memory_per_instance = 24
ampere_boot_volume_size    = 200
```

#### Ampere Only (No Micro Instances)

```hcl
ampere_instance_count = 4
micro_instance_count  = 0
```

#### With Additional Block Storage

```hcl
ampere_boot_volume_size  = 47   # Minimum size
create_additional_volume = true
additional_volume_size   = 50   # Extra storage
```

**Important**: Total storage (all boot volumes + block volumes) must be ≤ 200 GB.

### Outputs

After deployment, Terraform provides:

```bash
terraform output

# Example output:
ampere_instance_public_ips = [
  "xxx.xxx.xxx.xxx",
  "yyy.yyy.yyy.yyy",
]

ssh_connection_commands = [
  "ssh ubuntu@xxx.xxx.xxx.xxx",
  "ssh ubuntu@yyy.yyy.yyy.yyy",
]
```

## Budget Alerts

The Terraform configuration includes automatic budget monitoring:

- **Threshold**: $0.01
- **Alert Type**: Immediate notification on any charges
- **Purpose**: Detect if you accidentally exceed free tier limits

### How It Works

1. Budget monitors all resources in your compartment
2. If any cost > $0.01 is detected, you receive an email alert
3. You can then investigate and stop paid resources

### Customization

Edit `main.tf` to adjust:

```hcl
resource "oci_budget_budget" "free_tier_budget" {
  amount = 1.00  # Change threshold amount
  reset_period = "MONTHLY"
  # ... other settings
}
```

## Important Considerations

### Ampere A1 Availability

Ampere A1 instances are extremely popular and often **out of capacity**. Strategies:

1. **Run the availability checker frequently** (every 15-30 minutes)
2. **Try different regions** (change `region` variable)
3. **Try different availability domains**
4. **Be persistent** - capacity opens up regularly, especially late night/early morning

### Storage Limits

The 200 GB limit includes **all storage**:

- Example with 4 Ampere instances (47 GB boot each) = 188 GB
- Leaves only 12 GB for additional block volumes

Plan your storage allocation carefully!

### Instance Shapes

- **Ampere A1**: Flexible shape - you choose OCPU/memory within limits
- **E2.1.Micro**: Fixed shape - cannot customize

### Network Egress

While the free tier includes 10 TB/month outbound transfer, monitor your usage if running bandwidth-heavy applications.

### Region Selection

Some regions may have better Ampere availability. Popular regions to try:

- us-ashburn-1 (US East)
- us-phoenix-1 (US West)
- eu-frankfurt-1 (Europe)
- ap-melbourne-1 (Australia)
- uk-london-1 (UK)

## Common Commands

```bash
# Check availability
./check_availability.py

# Terraform commands
cd terraform
terraform init
terraform plan
terraform apply
terraform destroy  # Remove all resources

# Get outputs
terraform output
terraform output -json > outputs.json

# SSH to instance
terraform output ssh_connection_commands
ssh ubuntu@<ip-address>

# Validate Terraform configs
terraform fmt
terraform validate
```

## Troubleshooting

### "Out of capacity" Error

This is normal for Ampere instances. Solutions:
- Run availability checker in a loop
- Try different times of day
- Try different regions
- Consider using E2.1.Micro instances instead

### "Invalid Parameter" for Budget

Ensure:
- Budget amount is set correctly
- Email address is valid
- You have permission to create budgets (requires tenancy administrator)

### SSH Connection Issues

- Verify security list allows port 22
- Confirm SSH public key was added correctly
- Wait 1-2 minutes after instance creation
- Check instance is in "RUNNING" state

## Resources

- [OCI Free Tier Documentation](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
- [OCI Terraform Provider](https://registry.terraform.io/providers/oracle/oci/latest/docs)
- [OCI CLI Documentation](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/cliconcepts.htm)
- [OCI Forums](https://community.oracle.com/customerconnect/categories/oci)

## License

MIT License - Feel free to use and modify as needed.

## Contributing

Contributions welcome! Please open an issue or submit a pull request.
