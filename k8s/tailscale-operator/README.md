# Tailscale Operator for Kubernetes

Exposes Kubernetes services to Tailscale mesh network with zero-trust security.

## Overview

Tailscale Operator provides:
- **Service exposure** - Expose K8s services to Tailscale network via label
- **MagicDNS** - Automatic DNS names for services (e.g., `my-service.tail-xxxxx.ts.net`)
- **Zero-trust** - ACLs control who can access each service
- **No public exposure** - Services accessible only via Tailscale mesh
- **Ingress controller** - Acts as L7 proxy for HTTP(S) traffic

## Why Tailscale for Internal Services

**Use cases:**
- Internal APIs (not internet-facing)
- Development/staging environments
- Admin dashboards
- Databases with Tailscale client authentication
- Services for team members only

**Advantages:**
- No need for VPN setup
- Per-service access control
- Automatic TLS certificates
- Works from anywhere (roaming users)
- Free for personal use (up to 100 devices)

## Architecture

```
Developer Laptop (Tailscale client)
    |
    v
Tailscale Coordination Server
    |
    v
Proxmox Host (Tailscale LXC)
    |
    v
Talos VM (Tailscale sidecar in pod)
    |
    v
K8s Service (exposed via operator)
```

## Installation

### 1. Prerequisites

- **Tailscale account** (free tier: 100 devices, 3 users)
- **OAuth client** for Kubernetes operator
- **Tailnet name** (e.g., `tail-xxxxx.ts.net`)

### 2. Create Tailscale OAuth Client

```bash
# Visit: https://login.tailscale.com/admin/settings/oauth
# Create new OAuth client with scopes:
# - devices:write
# - routes:read
# - routes:write
# - dns:read
# - dns:write

# Save client ID and secret
export TS_CLIENT_ID="..."
export TS_CLIENT_SECRET="..."
```

### 3. Deploy Operator

```bash
# Create namespace
kubectl create namespace tailscale

# Create OAuth secret
kubectl create secret generic operator-oauth \
  --namespace tailscale \
  --from-literal=client-id="$TS_CLIENT_ID" \
  --from-literal=client-secret="$TS_CLIENT_SECRET"

# Apply operator manifest
kubectl apply -f tailscale-operator.yaml

# Verify deployment
kubectl get pods -n tailscale
```

### 4. Deploy as Inline Manifest (Talos Bootstrap)

**Generate manifest:**
```bash
helm repo add tailscale https://pkgs.tailscale.com/helmcharts
helm repo update

helm template tailscale-operator tailscale/tailscale-operator \
  --namespace tailscale \
  --create-namespace \
  --set oauth.clientId="$TS_CLIENT_ID" \
  --set oauth.clientSecret="$TS_CLIENT_SECRET" \
  > tailscale-operator-manifest.yaml
```

## Usage Patterns

### Pattern 1: Expose Service to Tailscale

```yaml
apiVersion: v1
kind: Service
metadata:
  name: internal-api
  annotations:
    tailscale.com/expose: "true"  # Enable Tailscale exposure
    tailscale.com/hostname: "api"  # Optional: custom hostname
    tailscale.com/tags: "tag:k8s,tag:prod"  # Optional: Tailscale ACL tags
spec:
  type: ClusterIP  # Keep internal, expose via Tailscale
  selector:
    app: api
  ports:
    - port: 8080
      targetPort: 8080
```

**Access:** `http://api.tail-xxxxx.ts.net:8080` from any Tailscale device

### Pattern 2: Tailscale Ingress (HTTP/HTTPS)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: internal-web
  annotations:
    tailscale.com/expose: "true"
    tailscale.com/hostname: "dashboard"
    cert-manager.io/cluster-issuer: "letsencrypt"  # Automatic TLS
spec:
  ingressClassName: tailscale
  rules:
    - host: dashboard.tail-xxxxx.ts.net
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web
                port:
                  number: 80
  tls:
    - hosts:
        - dashboard.tail-xxxxx.ts.net
      secretName: dashboard-tls
```

**Access:** `https://dashboard.tail-xxxxx.ts.net` from any Tailscale device

### Pattern 3: Subnet Router (Expose Entire Cluster)

Expose entire K8s service CIDR to Tailscale:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: tailscale-subnet-router
  namespace: tailscale
data:
  routes: "10.96.0.0/12"  # K8s service CIDR
```

**Access:** All ClusterIP services accessible via their IP from Tailscale

## Tailscale ACL Configuration

Define who can access services in Tailscale admin console:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["group:developers"],
      "dst": ["tag:k8s:8080"]
    },
    {
      "action": "accept",
      "src": ["group:admins"],
      "dst": ["tag:k8s:*"]
    }
  ],
  "tagOwners": {
    "tag:k8s": ["autogroup:admin"]
  }
}
```

## Integration with Network Policies

Allow Tailscale operator pods to access services:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-tailscale-operator
  namespace: default
spec:
  endpointSelector:
    matchLabels:
      app: my-app
  ingress:
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: tailscale
            app: tailscale-operator
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
```

## Monitoring

### Check Tailscale Devices

```bash
# From any Tailscale device
tailscale status

# Should show:
# - Proxmox hosts
# - Talos VMs
# - K8s operator pods
```

### Check Exposed Services

```bash
# List all Tailscale-exposed services
kubectl get svc -A -l tailscale.com/exposed=true

# Check operator logs
kubectl logs -n tailscale -l app=tailscale-operator
```

### Metrics

Operator exposes Prometheus metrics:

```yaml
# ServiceMonitor for Prometheus Operator
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: tailscale-operator
  namespace: tailscale
spec:
  selector:
    matchLabels:
      app: tailscale-operator
  endpoints:
    - port: metrics
```

## Dual-Stack Service Example

Expose service both publicly (via OCI IP) and internally (via Tailscale):

```yaml
---
# Public service (via OCI reserved IP + Proxmox NAT)
apiVersion: v1
kind: Service
metadata:
  name: web-public
spec:
  type: NodePort
  selector:
    app: web
  ports:
    - port: 443
      targetPort: 8443
      nodePort: 30443  # Maps to OCI reserved IP via DNAT

---
# Internal service (via Tailscale)
apiVersion: v1
kind: Service
metadata:
  name: web-internal
  annotations:
    tailscale.com/expose: "true"
    tailscale.com/hostname: "web-internal"
spec:
  type: ClusterIP
  selector:
    app: web
  ports:
    - port: 443
      targetPort: 8443
```

**Result:**
- Public: `https://150.x.x.2` (via OCI reserved IP)
- Internal: `https://web-internal.tail-xxxxx.ts.net` (via Tailscale)

## Security Best Practices

1. **Use Tailscale ACLs** - Define granular access control
2. **Tag services** - Group services by environment/team
3. **Enable MFA** - Require MFA for Tailscale admin access
4. **Rotate OAuth tokens** - Regenerate tokens periodically
5. **Monitor access logs** - Review Tailscale audit logs

## Troubleshooting

### Service not accessible via Tailscale

```bash
# Check if service has Tailscale annotation
kubectl get svc <service-name> -o yaml | grep tailscale

# Check operator logs
kubectl logs -n tailscale -l app=tailscale-operator

# Verify Tailscale device is online
tailscale status | grep <hostname>
```

### DNS not resolving

```bash
# Check MagicDNS is enabled in Tailscale admin
# Visit: https://login.tailscale.com/admin/dns

# Test from Tailscale device
nslookup my-service.tail-xxxxx.ts.net
```

### Operator pod crashlooping

```bash
# Check OAuth secret
kubectl get secret operator-oauth -n tailscale -o yaml

# Verify client ID/secret are correct
# Regenerate OAuth token if needed
```

## Cost

- **Tailscale Personal** (free): Up to 100 devices, 3 users
- **Tailscale Premium**: $6/user/month, unlimited devices
- **For this project**: Free tier is sufficient (3 Proxmox hosts + 3 Talos VMs + team devices < 100)

## References

- [Tailscale Operator Documentation](https://tailscale.com/kb/1236/kubernetes-operator)
- [Tailscale Ingress Controller](https://tailscale.com/kb/1185/kubernetes/)
- [Tailscale ACLs](https://tailscale.com/kb/1018/acls)
- [MagicDNS](https://tailscale.com/kb/1081/magicdns)
