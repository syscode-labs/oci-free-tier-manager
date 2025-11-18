# Kubernetes Networking Architecture

## Overview

Architecture for Talos K8s cluster on Proxmox VMs running on OCI Ampere instances.

## Cloud Controller Manager Strategy

### Option 1: OCI Cloud Controller Manager (RECOMMENDED)

**Why:** Even though K8s runs in Talos VMs on Proxmox, the underlying infrastructure is OCI.

**Capabilities:**
- Manage OCI Load Balancer resources
- Assign reserved public IPs to services via annotation
- Integrate with OCI VCN security lists
- Node lifecycle management

**Installation:**
- Deploy as DaemonSet in kube-system
- Requires OCI API credentials
- Can manage the 2 reserved OCI public IPs

**Limitations:**
- OCI free tier includes only 1 Load Balancer (10 Mbps)
- Load Balancer creation uses this quota
- Alternative: Use annotations to attach reserved IPs directly

### Option 2: Cilium L2 + Manual IP Assignment (FALLBACK)

If OCI CCM doesn't work with nested VM architecture:
- Cilium L2 announcement for internal IPs
- Manual 1:1 NAT on Proxmox hosts for public access
- Tailscale for mesh networking

## Selected Architecture: Hybrid Approach

### Components

1. **OCI Cloud Controller Manager**
   - Manages OCI reserved public IPs
   - Assigns IPs via service annotations
   - No Load Balancer creation (saves free tier quota)

2. **Cilium CNI (kube-proxy-free)**
   - L2 announcement for internal cluster IPs
   - Dual IP pool: Tailscale + OCI public

3. **Tailscale Operator**
   - Exposes services to Tailscale mesh
   - Service discovery via MagicDNS
   - Zero-trust internal access

4. **Dual-stack VMs**
   - Public: OCI subnet IP (ephemeral for Ampere nodes)
   - Private: Proxmox bridge (10.0.0.0/24)
   - Tailscale: Mesh network (100.64.0.0/10)

## Network Topology

```
Internet
    |
    v
[OCI Reserved IP #1] --> Bastion (Micro instance)
    |
    +--[Tailscale Mesh]
    |
[OCI Reserved IP #2] --> Proxmox Host (1:1 NAT) --> K8s Service
    |
    v
Proxmox Hosts (3x Ampere, ephemeral public IPs)
    |
    +--[vmbr0: 10.0.0.0/24]--+
    |                         |
    v                         v
Talos VMs             Tailscale LXC
(K8s nodes)           (mesh gateway)
```

## IP Allocation

| Resource | IP Type | CIDR/Address | Purpose |
|----------|---------|--------------|---------|
| Bastion | OCI Reserved #1 | x.x.x.1 | SSH jump host |
| K8s Public LB | OCI Reserved #2 | x.x.x.2 | Public service access |
| Proxmox vmbr0 | Private | 10.0.0.0/24 | VM internal network |
| Talos VMs | Dual-stack | Public ephemeral + 10.0.0.x | K8s nodes |
| K8s Pods | Private | 10.244.0.0/16 | Pod CIDR |
| K8s Services | Private | 10.96.0.0/12 | Service CIDR |
| Tailscale | Mesh | 100.64.x.x | Internal mesh |

## Service Exposure Patterns

### Pattern 1: Public Internet Service (1-2 services max)
```yaml
apiVersion: v1
kind: Service
metadata:
  name: public-web
  annotations:
    oci.oraclecloud.com/load-balancer-type: "none"
    oci.oraclecloud.com/reserved-public-ip: "x.x.x.2"  # Reserved IP #2
spec:
  type: LoadBalancer
  # Gets OCI reserved IP via CCM annotation
```

### Pattern 2: Tailscale Internal Service (unlimited)
```yaml
apiVersion: v1
kind: Service
metadata:
  name: internal-api
  labels:
    tailscale.com/expose: "true"
spec:
  type: ClusterIP
  # Exposed via Tailscale operator
```

### Pattern 3: Cluster-Internal Only
```yaml
apiVersion: v1
kind: Service
metadata:
  name: database
spec:
  type: ClusterIP
  # No external access
```

## Firewall Architecture

### Layer 1: OCI Security Lists (Proxmox Hosts)
```
Ingress:
- SSH (22) from bastion only
- HTTPS (443) from 0.0.0.0/0 (reserved IP #2 services)
- ICMP from 0.0.0.0/0
- Tailscale (41641/udp) from 0.0.0.0/0

Egress:
- All allowed
```

### Layer 2: Proxmox Host Firewall
```bash
# Enable Proxmox firewall per-VM
# Deny all by default, allow specific ports
```

### Layer 3: Talos VM Firewall (nftables)
```
Input:
- SSH (22) from Proxmox host only
- K8s API (6443) from control plane nodes + Proxmox
- Kubelet (10250) from control plane nodes
- Tailscale (41641/udp) from 0.0.0.0/0
- Established/related

Default: DROP
```

### Layer 4: Cilium Network Policies
```yaml
# Default deny all ingress
# Allow only specific namespaces/pods
# See network-policies/ directory
```

### Layer 5: Pod Security Standards
```yaml
# Enforce restricted pod security
# Drop all capabilities by default
# Run as non-root
```

## Manifest Size Solution

**Problem:** Cilium + OCI CCM + Tailscale Operator > 1MB inline manifest limit

**Solution:** Host manifests in separate repo and reference via URL

### Manifest Repository Structure
```
github.com/your-user/k8s-manifests-private/
├── cilium/
│   └── manifest.yaml
├── oci-ccm/
│   └── manifest.yaml
└── tailscale-operator/
    └── manifest.yaml
```

### Talos Configuration
```yaml
cluster:
  externalCloudProvider:
    enabled: true
    manifests:
      - https://raw.githubusercontent.com/your-user/k8s-manifests-private/main/cilium/manifest.yaml
      - https://raw.githubusercontent.com/your-user/k8s-manifests-private/main/oci-ccm/manifest.yaml
      - https://raw.githubusercontent.com/your-user/k8s-manifests-private/main/tailscale-operator/manifest.yaml
```

**Security:** Use private repo with GitHub token authentication or host on bastion via HTTPS.

## Network Policy Defaults

All namespaces start with:
1. **Deny all ingress** by default
2. **Allow DNS** to kube-system/coredns
3. **Allow metrics** to monitoring namespace
4. **Allow health checks** from kubelet

Workloads must explicitly allow required traffic.

## Implementation Order

1. **Bootstrap Talos** with CNI disabled
2. **Install Cilium** from external manifest
3. **Install OCI CCM** with API credentials
4. **Install Tailscale Operator** with auth key
5. **Apply default network policies**
6. **Test service exposure patterns**
7. **Deploy workloads**

## Monitoring

- Cilium Hubble: Network flow visibility
- Tailscale: Mesh connectivity
- OCI CCM: IP assignment logs
- Grafana Alloy: Export all to Grafana Cloud
