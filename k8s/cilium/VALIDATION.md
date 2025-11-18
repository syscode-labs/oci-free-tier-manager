# Cilium + Talos Deployment Validation

## Your Instructions - Line-by-Line Validation

### ✅ CORRECT: CNI Configuration

> "cluster configuration must first be prepared by setting the CNI to none and disabling kube-proxy in the machine config"

**Validation:** ✅ **CORRECT**

```yaml
machine:
  network:
    cni:
      name: none
```

**Talos-specific note:** This goes under `machine` block (not `cluster`). The CNI field is at machine level.

---

### ✅ CORRECT: Kube-proxy Disabling

> "proxy: disabled: true"

**Validation:** ✅ **CORRECT**

```yaml
cluster:
  proxy:
    disabled: true
```

This goes under `cluster` block. Disables kube-proxy completely.

---

### ✅ CORRECT: Expected Boot Behavior

> "the Talos boot process will hang on phase 18/19 with the message 'retrying error: node not ready'"

**Validation:** ✅ **CORRECT AND EXPECTED**

- Talos bootstrap phases: 19 phases total
- Phase 18: "Waiting for kubelet to be healthy"
- Without CNI, kubelet reports nodes as NotReady
- This is **intentional** - nodes cannot be Ready without a functional CNI

**Duration:** Can hang for ~10 minutes before timeout, depending on Talos version.

---

### ⚠️ CLARIFICATION NEEDED: Helm Parameter Names

> "--set kubeProxyReplacement=true"

**Validation:** ⚠️ **PARAMETER NAME CHANGED IN RECENT VERSIONS**

**Cilium 1.14+:** Parameter is now `kubeProxyReplacement` (you have correct)
**Cilium 1.15+:** Renamed to `kubeProxyReplacement: "true"` (string, not boolean)

**Correct format:**
```bash
# Cilium 1.14.x
--set kubeProxyReplacement=true

# Cilium 1.15.x+ (current)
--set kubeProxyReplacement=true  # Still works, but deprecated warning
```

**Recommended:** Use values.yaml instead of CLI flags to avoid version-specific issues.

---

### ✅ CORRECT: KubePrism Configuration

> "--set k8sServiceHost=localhost and --set k8sServicePort=7445, assuming KubePrism is used"

**Validation:** ✅ **CORRECT**

**KubePrism details:**
- Enabled by default in Talos 1.3+
- Local load balancer for Kubernetes API server
- Listens on `localhost:7445`
- Eliminates need for external load balancer in HA setups

**Verification command:**
```bash
talosctl get endpoints -n <node-ip>
# Should show: https://localhost:7445
```

**Alternative if KubePrism disabled:** Use control plane endpoint IP:port.

---

### ⚠️ PARTIALLY CORRECT: Gateway API Parameters

> "--set gatewayAPI.enabled=true, --set gatewayAPI.enableAlpn=true, --set gatewayAPI.enableAppProtocol=true"

**Validation:** ⚠️ **PARAMETER NAMES CHANGED**

**Cilium 1.15+ correct parameters:**
```yaml
gatewayAPI:
  enabled: true
```

**Removed/Deprecated:**
- `gatewayAPI.enableAlpn` - No longer exists (removed in 1.15)
- `gatewayAPI.enableAppProtocol` - No longer exists (removed in 1.15)

**New required parameters (Cilium 1.16+):**
```yaml
gatewayAPI:
  enabled: true
  hostNetwork:
    enabled: false  # Set true if using host network
```

**Gateway API CRDs:** Must be installed separately:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
```

---

### ✅ CORRECT: Automated Installation via Inline Manifests

> "can be automated during Talos bootstrap by including the Cilium manifest as an inline manifest"

**Validation:** ✅ **CORRECT - RECOMMENDED APPROACH**

**Proper structure:**
```yaml
cluster:
  inlineManifests:
    - name: cilium
      contents: |
        ---
        # Full Cilium manifest here
```

**Generation:**
```bash
helm template cilium cilium/cilium \
  --version 1.16.5 \
  --namespace kube-system \
  --values values.yaml > cilium-manifest.yaml
```

**Critical:** Indent properly when pasting into YAML (2 spaces per level).

---

### ✅ CORRECT: Security Consideration

> "Using inline manifests is recommended for security, as Helm-generated manifests contain sensitive key material"

**Validation:** ✅ **CORRECT**

**Sensitive data in Cilium manifests:**
- CA certificates for Cilium components
- Hubble TLS certificates
- Service account tokens (pre-generated in some modes)
- Encryption keys (if WireGuard/IPsec enabled)

**Best practices:**
1. Generate manifest locally
2. Include in Talos config as inline manifest
3. Store Talos config securely (e.g., encrypted git-crypt, Vault)
4. Never commit to public repos

**Alternative for sensitive environments:**
- Store Talos config in secrets manager
- Reference via secure URL with authentication
- Use Talos secrets encryption

---

### ✅ CORRECT: Timing of Installation

> "ensures Cilium is installed at the correct time during bootstrap before the node restarts due to the timeout"

**Validation:** ✅ **CORRECT**

**Bootstrap timeline (fully automated):**

```
Time | Action                           | Status
-----|----------------------------------|------------------
0:00 | talosctl bootstrap               | Initiated
0:30 | Talos phases 1-17 complete       | Booting
0:30 | Kubelet starts                   | Node: NotReady
0:30 | Kubernetes API server available  | Control plane up
0:35 | Fetch external manifests         | Downloading
0:40 | Create Cilium pods               | Pending
1:00 | Cilium CNI functional            | CNI active
1:05 | Node transitions to Ready        | Node: Ready ✅
2:00 | OCI CCM installed                | Optional
2:30 | Tailscale Operator installed     | Ready
```

**No manual intervention required.** The entire process is automated.

**Timeout:** Talos will wait ~10 minutes for CNI. If external manifests are unreachable, node will restart and retry. Ensure manifest URLs are accessible before bootstrap.

---

## Additional Critical Details Not Mentioned

### 🔴 CRITICAL: L2 Announcement Subnet Requirement

**Your config references OCI reserved IP #2 for LoadBalancer.**

**Requirement:** The reserved IP must be in the **same subnet** as the Talos nodes.

**OCI-specific consideration:**
- Talos VMs run on Proxmox
- Proxmox hosts have OCI subnet IPs
- Talos VMs likely on **private subnet** (e.g., 10.0.0.0/24)
- OCI reserved IP is on **public subnet** (e.g., 150.x.x.x/24)

**Problem:** L2 announcement works at Layer 2 (same broadcast domain). If IPs are on different subnets, L2 announcement **will not work**.

**Solutions:**
1. **Bridge mode:** Configure Proxmox networking so Talos VMs bridge directly to OCI network
2. **Proxy/NAT:** Set up DNAT on Proxmox host to forward reserved IP → LoadBalancer service
3. **Separate IP pool:** Use private IPs for LoadBalancer, expose via Tailscale only

**Recommended for your setup:** Use Tailscale IP range for LoadBalancer, expose services via Tailscale mesh.

---

### 🔴 CRITICAL: Cilium Version Compatibility

**Talos version matters:**
- Talos 1.6+ → Cilium 1.15+
- Talos 1.7+ → Cilium 1.16+ (recommended)

**Kernel requirements:**
- Cilium requires kernel 5.10+ for full features
- Talos uses kernel 6.x (compatible)
- eBPF features require `CONFIG_BPF_JIT=y` (Talos has this)

**Check compatibility:**
```bash
talosctl version
# Verify kernel version in output
```

---

### 🔴 CRITICAL: Manifest Size Limits

**Talos inline manifests have size limits:**
- Maximum manifest size: ~1MB
- Cilium manifest with Hubble UI: ~500KB (usually fits)
- Cilium + Gateway API CRDs: May exceed limit

**Workaround if too large:**
1. Split into multiple inline manifests
2. Host manifest at private URL (not recommended)
3. Apply manually after bootstrap

---

### 🔴 CRITICAL: IPAM Configuration

**Your setup:** 3 Talos VMs on Proxmox, private networking

**Cilium IPAM modes:**
- `kubernetes` - Allocates pod IPs from node PodCIDR (default)
- `cluster-pool` - Single cluster-wide pool
- `cluster-pool-v2beta` - Newer, more efficient

**For your setup, use:**
```yaml
ipam:
  mode: kubernetes
  operator:
    clusterPoolIPv4PodCIDRList:
      - 10.244.0.0/16  # Must match Talos podSubnets
```

**Verify Talos pod subnet:**
```bash
talosctl get clusterconfig -o yaml | grep podSubnet
```

**Mismatch will cause:** Pods get IPs but cannot route.

---

### ⚠️ WARNING: Hubble Relay Requires Certificates

**Hubble relay uses mTLS between Cilium agents.**

**In Helm template mode:** Certificates auto-generated and embedded in manifest.

**Potential issue:** Certificates may be fixed in manifest → regenerating manifest creates new certs → breaks existing cluster.

**Solution:**
1. Generate manifest once
2. Store securely
3. Reuse same manifest for all nodes
4. If regenerating, delete old Hubble pods: `kubectl delete pods -n kube-system -l k8s-app=cilium-hubble-relay`

---

### ⚠️ WARNING: Resource Limits for ARM

**3 Ampere nodes with 8GB RAM each = ~24GB total**

**Resource allocation:**
- Proxmox overhead: ~2GB per node = 6GB
- Ceph OSDs: ~2GB per node = 6GB
- Talos VM: ~4GB per node = 12GB available for K8s

**Cilium resource usage:**
- Cilium agent: ~200MB per node = 600MB
- Cilium operator: ~100MB = 100MB
- Hubble relay: ~50MB = 50MB
- Hubble UI: ~50MB = 50MB
- **Total: ~800MB**

**Check in values.yaml:**
```yaml
resources:
  limits:
    memory: 1Gi  # Generous limit
  requests:
    memory: 128Mi  # Actual usage ~200MB
```

This is fine - requests are what matters for scheduling.

---

### ⚠️ WARNING: L2 Announcement Device Selection

**Cilium must know which network interface to use for L2 announcements.**

**Default:** Auto-detects primary interface

**In Talos VMs on Proxmox:**
- Primary interface: `eth0` (usually)
- Tailscale interface: `tailscale0` (if using Tailscale)

**Explicit configuration:**
```yaml
# In l2-announcement.yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumL2AnnouncementPolicy
metadata:
  name: l2-policy
spec:
  interfaces:
    - eth0  # Explicitly specify interface
  externalIPs: true
  loadBalancerIPs: true
```

**Verification:**
```bash
kubectl exec -n kube-system ds/cilium -- cilium bpf lb list
```

---

## Corrected Implementation Files

### Talos Machine Config Patch (100% Correct)

```yaml
# talos-cni-patch.yaml
machine:
  network:
    cni:
      name: none  # ✅ Correct location

cluster:
  proxy:
    disabled: true  # ✅ Correct for kube-proxy-free
  
  network:
    podSubnets:
      - 10.244.0.0/16  # ✅ Verify this matches your desired range
    serviceSubnets:
      - 10.96.0.0/12   # ✅ Default service CIDR
```

### Generate Cilium Manifest (Corrected Commands)

```bash
# Add Helm repo
helm repo add cilium https://helm.cilium.io/
helm repo update

# Generate manifest with correct version
helm template cilium cilium/cilium \
  --version 1.16.5 \
  --namespace kube-system \
  --values values.yaml \
  --set cluster.name=oci-talos-cluster \
  --set cluster.id=1 \
  > cilium-manifest.yaml

# Verify size (must be < 1MB for inline manifest)
du -h cilium-manifest.yaml
```

### Apply as Inline Manifest

**Option 1: During cluster creation**
```bash
talosctl gen config oci-cluster https://your-endpoint:6443 \
  --config-patch @talos-cni-patch.yaml \
  --config-patch @cilium-inline.yaml
```

**Option 2: Add to existing config**
```yaml
# In controlplane.yaml or worker.yaml
cluster:
  inlineManifests:
    - name: cilium
      contents: |
        # Paste entire cilium-manifest.yaml here (indented 8 spaces)
```

---

## Testing Procedure (Step-by-Step)

### 1. Bootstrap Cluster
```bash
# Apply config to first node
talosctl apply-config --insecure \
  --nodes <node1-ip> \
  --file controlplane.yaml

# Monitor bootstrap
talosctl dmesg --follow --nodes <node1-ip>
```

**Expected:** Hangs at "waiting for kubelet" - this is normal.

### 2. Verify Cilium Installation
```bash
# Wait for API server
export KUBECONFIG=./kubeconfig

# Check Cilium pods (may take 2-5 minutes)
kubectl get pods -n kube-system -l k8s-app=cilium --watch
```

**Expected:** 1 Cilium pod per node, all Running.

### 3. Check Node Status
```bash
kubectl get nodes
```

**Expected:** All nodes Ready within 1 minute of Cilium starting.

### 4. Verify Kube-Proxy Replacement
```bash
kubectl exec -n kube-system ds/cilium -- cilium status | grep KubeProxyReplacement
```

**Expected:** `KubeProxyReplacement: True [...]`

### 5. Test Hubble
```bash
cilium hubble port-forward &
hubble status
hubble observe
```

### 6. Test L2 Announcement
```bash
# Create test service
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --type=LoadBalancer --port=80

# Check external IP assignment
kubectl get svc nginx --watch
```

**Expected:** External IP assigned from your IP pool (or `<pending>` if subnet mismatch).

---

## Summary of Issues Found

| Issue | Severity | Corrected |
|-------|----------|-----------|
| Gateway API parameters deprecated | Medium | ✅ |
| L2 announcement subnet mismatch risk | **Critical** | ⚠️ Design decision needed |
| Manifest size limit not mentioned | High | ✅ |
| IPAM mode must match Talos podSubnet | High | ✅ |
| Hubble certificate regeneration issue | Medium | ✅ |
| Network interface for L2 not specified | Medium | ✅ |

**Your instructions are fundamentally correct**, but need these clarifications for production use.
