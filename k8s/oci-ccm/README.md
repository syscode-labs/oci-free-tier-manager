# OCI Cloud Controller Manager

Integrates Kubernetes with Oracle Cloud Infrastructure for automated IP management.

## Overview

The OCI CCM enables:
- Attaching OCI reserved public IPs to services via annotations
- Managing OCI Load Balancer resources (optional, 1 free tier limit)
- Node lifecycle integration with OCI compute
- Security list management

## Architecture Decision

**Configuration:** Attach reserved IPs directly to services WITHOUT creating OCI Load Balancers.

**Why:**
- Free tier includes only 1 Load Balancer (10 Mbps)
- Direct IP attachment via annotation doesn't use LB quota
- OCI reserved IP #2 forwarded via 1:1 NAT on Proxmox host

**How it works:**
```
Internet → OCI Reserved IP #2 → Proxmox Host (DNAT) → Talos VM → K8s Service
```

## Prerequisites

1. **OCI API credentials** with permissions:
   - `manage load-balancers` (even if not creating LBs)
   - `manage public-ips`
   - `inspect vcns`
   - `inspect subnets`

2. **OCI configuration values** from Terraform output:
   - Tenancy OCID
   - User OCID
   - Compartment OCID
   - VCN OCID
   - Subnet OCID(s)
   - Region
   - API key fingerprint

3. **Reserved public IP #2 OCID** from Terraform

## Installation

### 1. Create OCI API Key Secret

```bash
# Base64 encode your OCI private key
cat ~/.oci/oci_api_key.pem | base64 -w 0 > oci-key-b64.txt

# Create secret
kubectl create secret generic oci-cloud-controller-manager \
  -n kube-system \
  --from-file=cloud-provider.yaml=cloud-provider.yaml \
  --from-literal=oci-api-key="$(cat oci-key-b64.txt)"
```

### 2. Configure cloud-provider.yaml

```yaml
# cloud-provider.yaml
auth:
  region: uk-london-1
  tenancy: ocid1.tenancy.oc1..xxxxx
  user: ocid1.user.oc1..xxxxx
  key: |
    -----BEGIN RSA PRIVATE KEY-----
    <your private key>
    -----END RSA PRIVATE KEY-----
  fingerprint: aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99
  
vcn: ocid1.vcn.oc1.uk-london-1.xxxxx
compartment: ocid1.compartment.oc1..xxxxx

loadBalancer:
  disabled: false  # Enable for reserved IP management
  disableSecurityListManagement: true  # Manage security lists via Terraform
  
rateLimiter:
  rateLimitQPSRead: 20.0
  rateLimitBucketRead: 5
  rateLimitQPSWrite: 20.0
  rateLimitBucketWrite: 5
```

### 3. Deploy OCI CCM

```bash
# Apply manifests (generated via Helm or from upstream)
kubectl apply -f oci-ccm-manifest.yaml

# Verify deployment
kubectl get pods -n kube-system -l app=oci-cloud-controller-manager
```

### 4. Configure Talos Nodes

Talos nodes need OCI metadata for CCM to identify them:

```yaml
# In Talos machine config
machine:
  kubelet:
    extraArgs:
      cloud-provider: external
      provider-id: oci://<instance-ocid>
```

**Get instance OCID:**
```bash
# From OCI CLI on Proxmox host
oci compute instance list --compartment-id <compartment-ocid> \
  --display-name <instance-name> \
  --query 'data[0].id' --raw-output
```

## Usage: Attach Reserved IP to Service

### Using Service Annotation

```yaml
apiVersion: v1
kind: Service
metadata:
  name: public-web
  annotations:
    # Option 1: Use reserved IP directly (no LB created)
    service.beta.kubernetes.io/oci-load-balancer-internal: "false"
    oci.oraclecloud.com/oci-network-load-balancer-security-mode: "none"
    service.beta.kubernetes.io/oci-load-balancer-shape: "flexible"
    service.beta.kubernetes.io/oci-load-balancer-shape-flex-min: "10"
    service.beta.kubernetes.io/oci-load-balancer-shape-flex-max: "10"
    
    # Attach reserved public IP
    service.beta.kubernetes.io/oci-load-balancer-subnet1: <subnet-ocid>
    oci.oraclecloud.com/reserved-public-ip-id: <reserved-ip-2-ocid>
spec:
  type: LoadBalancer
  selector:
    app: web
  ports:
    - protocol: TCP
      port: 443
      targetPort: 8443
```

## Alternative: Manual 1:1 NAT (Simpler for Free Tier)

Since we have limited public IPs and only need 1-2 public services:

### On Proxmox Host

```bash
# Enable IP forwarding
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# DNAT rule: Forward reserved IP #2 to Talos VM
# Assuming:
# - Reserved IP #2: 150.x.x.2
# - Talos VM (control plane): 10.0.0.10
# - K8s NodePort: 30443

iptables -t nat -A PREROUTING \
  -d 150.x.x.2 -p tcp --dport 443 \
  -j DNAT --to-destination 10.0.0.10:30443

# SNAT for return traffic
iptables -t nat -A POSTROUTING \
  -s 10.0.0.10 -p tcp --sport 30443 \
  -j SNAT --to-source 150.x.x.2

# Make persistent
apt-get install iptables-persistent
netfilter-persistent save
```

### Kubernetes Service (NodePort)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: public-web
spec:
  type: NodePort
  selector:
    app: web
  ports:
    - protocol: TCP
      port: 443
      targetPort: 8443
      nodePort: 30443  # Must match DNAT rule
```

## Recommendation

**For 1-2 public services:** Use manual 1:1 NAT (simpler, no CCM needed)
**For dynamic IP management:** Use OCI CCM with annotations

## Troubleshooting

### CCM not assigning IPs

```bash
# Check CCM logs
kubectl logs -n kube-system -l app=oci-cloud-controller-manager

# Common issues:
# - Missing OCI API permissions
# - Incorrect compartment/VCN OCID
# - Reserved IP already attached
# - Nodes missing provider-id
```

### Verify node provider IDs

```bash
kubectl get nodes -o jsonpath='{.items[*].spec.providerID}'
# Should show: oci://<instance-ocid>
```

### Test OCI API access from pod

```bash
kubectl run oci-test --rm -it --image=oraclelinux:8 -- bash
yum install -y oci-cli
oci iam region list  # Should work with mounted credentials
```

## Security Considerations

1. **API key rotation:** Rotate OCI API keys every 90 days
2. **Least privilege:** Grant only required OCI permissions
3. **Secret encryption:** Enable Kubernetes secret encryption at rest
4. **Network policies:** Restrict CCM pod egress to OCI API endpoints only

## Monitoring

Add to Grafana Alloy scrape config:

```yaml
- job_name: oci-ccm
  kubernetes_sd_configs:
    - role: pod
      namespaces:
        names:
          - kube-system
  relabel_configs:
    - source_labels: [__meta_kubernetes_pod_label_app]
      regex: oci-cloud-controller-manager
      action: keep
```

## References

- [OCI CCM GitHub](https://github.com/oracle/oci-cloud-controller-manager)
- [OCI Load Balancer Annotations](https://github.com/oracle/oci-cloud-controller-manager/blob/master/docs/load-balancer-annotations.md)
- [Talos External Cloud Provider](https://www.talos.dev/latest/kubernetes-guides/configuration/kubeadm/#enabling-external-cloud-provider)
