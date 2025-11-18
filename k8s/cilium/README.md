# Cilium Installation for Talos

This directory contains the Cilium CNI configuration for deploying on Talos Linux in kube-proxy-free mode.

## Overview

Cilium is deployed with:
- **Kube-proxy replacement** - Native L3/L4 load balancing without kube-proxy
- **L2 announcement** - LoadBalancer services using the 2nd OCI reserved IP
- **Hubble** - Network observability and flow visualization
- **Gateway API** - Modern ingress alternative (optional)
- **Network policies** - Sane defaults for cluster security

## Prerequisites

1. **Talos cluster** must be configured with CNI disabled in machine config
2. **Reserved IP #2** from OCI Terraform output
3. **KubePrism** enabled in Talos (default on port 7445)

## Files

- `values.yaml` - Helm values for Cilium installation
- `network-policies/` - Default network policies for workloads
- `l2-announcement.yaml` - L2 announcement policy for LoadBalancer services
- `install.sh` - Automated installation script

## Installation Methods

### Method 1: Automated Bootstrap (Recommended)

Include Cilium manifest as inline manifest in Talos machine config:

```bash
# Generate manifest
helm template cilium cilium/cilium \
  --version 1.15.0 \
  --namespace kube-system \
  --values values.yaml > cilium-manifest.yaml

# Include in Talos machine config under cluster.inlineManifests
```

**Security note:** Inline manifests keep sensitive key material within your config. Do not commit to public repos.

### Method 2: Install After Bootstrap

```bash
# Install using Helm
helm repo add cilium https://helm.cilium.io/
helm repo update
helm install cilium cilium/cilium \
  --version 1.15.0 \
  --namespace kube-system \
  --values values.yaml

# Wait for Cilium to be ready
cilium status --wait

# Apply L2 announcement policy
kubectl apply -f l2-announcement.yaml
```

### Method 3: Using install.sh script

```bash
./install.sh <RESERVED_IP_2>
```

## Talos Configuration

**Required patch for Talos machine config** (`talos-cni-patch.yaml`):

```yaml
machine:
  network:
    cni:
      name: none  # Disable default CNI

cluster:
  proxy:
    disabled: true  # Disable kube-proxy for Cilium replacement
    
  inlineManifests:
    - name: cilium
      contents: |
        # Paste generated cilium-manifest.yaml here
```

Apply during `talosctl gen config`:
```bash
talosctl gen config my-cluster https://<endpoint>:6443 \
  --config-patch @talos-cni-patch.yaml
```

## Expected Bootstrap Behavior (Fully Automated)

**This is a hands-off process - no manual intervention required.**

1. **talosctl apply-config** - Apply machine config to nodes
2. **talosctl bootstrap** - Bootstrap first control plane node
3. **Automatic sequence (2-5 minutes):**
   - Talos boots and reaches phase 18/19
   - Kubelet starts but nodes show "NotReady" (waiting for CNI)
   - Kubernetes API server becomes available
   - External manifests are fetched automatically from URLs
   - Cilium pods are created and start
   - CNI becomes functional
   - Nodes transition to "Ready"
   - OCI CCM and Tailscale Operator install automatically

**Timeline:**
- Phase 1-17: ~30 seconds (Talos initialization)
- Phase 18/19: ~2-5 minutes (waiting for CNI to install)
- Total bootstrap: ~3-6 minutes from `talosctl bootstrap` to Ready nodes

**Important:** The "node not ready" message is **normal behavior**, not an error. Nodes cannot be Ready without a functioning CNI. Once Cilium starts, nodes automatically become Ready.

## Verification

```bash
# Check Cilium status
cilium status

# Verify kube-proxy replacement
cilium status | grep KubeProxyReplacement

# Test Hubble
cilium hubble port-forward &
hubble status

# Check L2 announcement
kubectl get l2announcements -n kube-system

# Test LoadBalancer service
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --type=LoadBalancer --port=80
kubectl get svc nginx  # Should show EXTERNAL-IP as reserved IP #2
```

## Network Policies

Default policies are in `network-policies/`:
- `default-deny-ingress.yaml` - Deny all ingress by default
- `allow-dns.yaml` - Allow DNS from all pods
- `allow-kube-system.yaml` - Allow traffic to kube-system services
- `allow-hubble.yaml` - Allow Hubble metrics collection

Apply all:
```bash
kubectl apply -f network-policies/
```

## Troubleshooting

**Nodes stuck in NotReady:**
- Verify CNI is set to `none` in Talos config
- Check Cilium pods: `kubectl get pods -n kube-system`
- View logs: `kubectl logs -n kube-system -l k8s-app=cilium`

**LoadBalancer IP not assigned:**
- Verify L2 announcement policy: `kubectl describe l2announcement`
- Check Cilium agent logs for L2 errors
- Ensure reserved IP is in the same subnet as nodes

**Hubble UI not accessible:**
- Enable Hubble UI in values.yaml: `hubble.ui.enabled: true`
- Port-forward: `kubectl port-forward -n kube-system svc/hubble-ui 12000:80`

## References

- [Cilium kube-proxy replacement](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)
- [Talos Cilium guide](https://www.talos.dev/latest/kubernetes-guides/network/deploying-cilium/)
- [Cilium L2 announcement](https://docs.cilium.io/en/stable/network/l2-announcements/)
- [Hubble observability](https://docs.cilium.io/en/stable/gettingstarted/hubble/)
