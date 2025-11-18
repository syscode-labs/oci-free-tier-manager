# K8s Deployment Summary

## Architecture Overview

**Stack:** Talos Linux on Proxmox VMs on OCI Ampere instances with Cilium CNI (kube-proxy-free), OCI CCM, and Tailscale Operator.

## Key Decisions

### 1. **Cilium CNI - Kube-Proxy-Free Mode ✅**
- **Why:** Modern, eBPF-based networking with better performance
- **Config:** KubePrism localhost:7445, CNI disabled in Talos, kube-proxy disabled
- **Hubble:** Network observability built-in
- **Deployment:** External manifest (exceeds 1MB inline limit)

### 2. **OCI Cloud Controller Manager (Optional) ⚠️**
- **Why:** Manage OCI reserved IPs via Kubernetes annotations
- **Reality:** Simpler to use 1:1 NAT on Proxmox for 1-2 public services
- **Decision:** Implement 1:1 NAT first, add CCM later if needed
- **Note:** Free tier has only 1 OCI Load Balancer (10 Mbps)

### 3. **Tailscale Operator ✅**
- **Why:** Expose unlimited internal services without public IPs
- **Use case:** Dev/staging, admin dashboards, internal APIs
- **Advantage:** Zero-trust mesh, MagicDNS, no VPN setup
- **Cost:** Free for <100 devices

### 4. **Manifest Hosting Strategy ✅**
- **Problem:** Cilium + CCM + Tailscale > 1MB Talos inline limit
- **Solution:** Host in private GitHub repo, reference via URL
- **Security:** Private repo with token OR self-host on bastion

### 5. **Dual-Stack Networking ✅**
- **Public:** OCI ephemeral IPs on Proxmox hosts
- **Private:** Proxmox vmbr0 (10.0.0.0/24) for Talos VMs
- **Mesh:** Tailscale (100.64.x.x) for internal services
- **Firewall:** 5 layers (OCI, Proxmox, Talos, Cilium, Pod Security)

### 6. **Default-Deny Network Policies ✅**
- **Principle:** Zero-trust - deny all, explicitly allow required
- **Applied:** Cluster-wide except kube-system
- **Allowed:** DNS, kubelet probes, metrics, Tailscale operator

## Deployment Flow

```
┌─────────────────────────────────────────────────────────────┐
│ Phase 1: Image Building (Packer)                            │
├─────────────────────────────────────────────────────────────┤
│ 1. Build base-hardened.qcow2                                │
│    - Debian 12 + SSH + Tailscale                            │
│ 2. Build proxmox-ampere.qcow2                               │
│    - Base + Proxmox + tteck scripts + Ceph                  │
│ 3. Upload to OCI Object Storage                             │
│ 4. Create OCI custom images                                 │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Phase 2: Infrastructure (Terraform)                         │
├─────────────────────────────────────────────────────────────┤
│ 1. Deploy 3 Ampere + 1 Micro bastion                        │
│ 2. Attach 2 reserved IPs (bastion + public services)        │
│ 3. Verify Tailscale connectivity                            │
│ 4. Verify Proxmox web UI (no enterprise nag)                │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Phase 3: Proxmox Cluster                                    │
├─────────────────────────────────────────────────────────────┤
│ 1. Form 3-node cluster                                      │
│ 2. Configure Ceph storage                                   │
│ 3. Test VM live migration                                   │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Phase 4: Kubernetes (Talos)                                 │
├─────────────────────────────────────────────────────────────┤
│ 1. Generate Talos config with:                              │
│    - CNI: none                                              │
│    - Kube-proxy: disabled                                   │
│    - External manifests: Cilium, CCM, Tailscale             │
│ 2. Apply config to nodes (talosctl apply-config)            │
│ 3. Bootstrap first control plane (talosctl bootstrap)       │
│ 4. Cluster auto-provisions (2-5 min, no intervention):      │
│    a. Nodes reach phase 18/19 (waiting for CNI)             │
│    b. Cilium installs automatically from external manifest  │
│    c. Nodes become Ready                                    │
│    d. OCI CCM installs automatically (optional)             │
│    e. Tailscale Operator installs automatically             │
│ 5. Apply network policies (kubectl apply)                   │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Phase 5: Service Exposure                                   │
├─────────────────────────────────────────────────────────────┤
│ 1. Public services: NodePort + Proxmox 1:1 NAT              │
│    Reserved IP #2 → Proxmox host → Talos VM:30443           │
│ 2. Internal services: Tailscale operator annotation         │
│    tailscale.com/expose: "true"                             │
│ 3. Test both patterns                                       │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Phase 6: Monitoring (Grafana Cloud)                         │
├─────────────────────────────────────────────────────────────┤
│ 1. Deploy Grafana Alloy DaemonSet                           │
│ 2. Configure remote write to Grafana Cloud                  │
│ 3. Set up dashboards                                        │
└─────────────────────────────────────────────────────────────┘
```

## Service Exposure Patterns

### Pattern 1: Public Internet (1-2 services)
```yaml
apiVersion: v1
kind: Service
metadata:
  name: public-web
spec:
  type: NodePort
  nodePort: 30443
  ports:
    - port: 443
      targetPort: 8443
```

**Proxmox 1:1 NAT:**
```bash
iptables -t nat -A PREROUTING \
  -d <RESERVED_IP_2> -p tcp --dport 443 \
  -j DNAT --to-destination 10.0.0.10:30443
```

### Pattern 2: Tailscale Internal (unlimited)
```yaml
apiVersion: v1
kind: Service
metadata:
  name: internal-api
  annotations:
    tailscale.com/expose: "true"
    tailscale.com/hostname: "api"
spec:
  type: ClusterIP
  ports:
    - port: 8080
```

**Access:** `http://api.tail-xxxxx.ts.net:8080`

### Pattern 3: Cluster-Internal Only
```yaml
apiVersion: v1
kind: Service
metadata:
  name: database
spec:
  type: ClusterIP
  # No annotations - cluster-internal only
```

## Critical Validation Points

### ✅ Before Bootstrap
- [ ] Talos config has `network.cni.name: none`
- [ ] Talos config has `cluster.proxy.disabled: true`
- [ ] Talos config references external manifest URLs
- [ ] External manifests are accessible and < 1MB each
- [ ] Pod/Service CIDRs match Cilium values.yaml

### ✅ During Bootstrap (Automated - No Intervention Required)
- [ ] Nodes reach phase 18/19 "node not ready" (NORMAL - waiting for CNI)
- [ ] Automatic: Cilium installs from external manifest (2-5 minutes)
- [ ] Automatic: Nodes transition to Ready once CNI is functional
- [ ] Monitor: `kubectl get pods -n kube-system -l k8s-app=cilium --watch`

### ✅ After Bootstrap
- [ ] All nodes Ready
- [ ] Cilium status shows `KubeProxyReplacement: True`
- [ ] Hubble is accessible
- [ ] Network policies applied
- [ ] Test service: Create nginx, expose as NodePort, test via NAT
- [ ] Test Tailscale: Expose service, access from Tailscale device

## Security Checklist

### Network Layers
- [x] OCI Security Lists: SSH from bastion, HTTPS from 0.0.0.0/0, Tailscale UDP
- [x] Proxmox Firewall: Per-VM rules, deny by default
- [x] Talos nftables: SSH from Proxmox only, K8s API restricted
- [x] Cilium Network Policies: Default deny + explicit allows
- [x] Pod Security Standards: Restricted profile enforced

### Secrets Management
- [ ] OCI API keys in Kubernetes secrets (encrypted at rest)
- [ ] Tailscale OAuth tokens in secrets
- [ ] Rotate secrets every 90 days
- [ ] Never commit secrets to public repos

### Access Control
- [ ] Bastion jump host for SSH access only
- [ ] Tailscale ACLs define service access
- [ ] RBAC for Kubernetes API access
- [ ] MFA enabled for all admin accounts

## Resource Allocation (per node)

| Component | CPU | RAM | Notes |
|-----------|-----|-----|-------|
| Proxmox | 200m | 2GB | Hypervisor overhead |
| Ceph OSD | 100m | 2GB | Distributed storage |
| Talos VM | 1000m | 4GB | Available for K8s |
| **Available for K8s** | **~1 OCPU** | **~4GB** | Per Ampere node |

**Total cluster:** ~3 OCPU, ~12GB for K8s workloads

**Cilium usage:** ~600MB total (200MB per node)
**Remaining:** ~11.4GB for applications

## Troubleshooting Reference

### Nodes stuck NotReady
```bash
kubectl get nodes
kubectl get pods -n kube-system
kubectl logs -n kube-system -l k8s-app=cilium
```

### Cilium not starting
```bash
talosctl get clusterconfig -o yaml | grep -A 5 cni
# Should show: name: none

talosctl get clusterconfig -o yaml | grep -A 5 proxy
# Should show: disabled: true
```

### Service not accessible
```bash
# Public service via NAT
curl -v https://<RESERVED_IP_2>

# Tailscale service
tailscale status | grep <hostname>
curl http://<hostname>.tail-xxxxx.ts.net
```

### Network policy blocking traffic
```bash
# Check policies
kubectl get ciliumnetworkpolicies -A
kubectl get ciliumclusterwidenetworkpolicies

# Debug with Hubble
cilium hubble port-forward &
hubble observe --pod <pod-name>
```

## Cost Summary

| Resource | Type | Quantity | Cost |
|----------|------|----------|------|
| Ampere OCPU | Compute | 3.99 | $0 (free tier) |
| Ampere RAM | Compute | 24GB | $0 (free tier) |
| Micro instances | Compute | 1 | $0 (free tier) |
| Block storage | Storage | 200GB | $0 (free tier) |
| Reserved IPs | Network | 2 | $0 (free tier) |
| Object Storage | Storage | ~15GB | $0 (free tier) |
| Tailscale | SaaS | <100 devices | $0 (free tier) |
| Grafana Cloud | SaaS | Free tier | $0 |
| **TOTAL** | | | **$0/month** |

## Next Steps

1. Review and validate all configuration files in `k8s/` directory
2. Create private GitHub repo for external manifests
3. Generate Cilium/CCM/Tailscale manifests
4. Deploy Phase 1 (Packer images)
5. Deploy Phase 2 (Terraform infrastructure)
6. Continue with remaining phases

## References

- Talos: https://www.talos.dev/latest/kubernetes-guides/network/deploying-cilium/
- Cilium: https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/
- OCI CCM: https://github.com/oracle/oci-cloud-controller-manager
- Tailscale: https://tailscale.com/kb/1236/kubernetes-operator
- Hubble: https://docs.cilium.io/en/stable/gettingstarted/hubble/
