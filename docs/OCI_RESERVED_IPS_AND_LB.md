# OCI Reserved IPs and Load Balancer — Usage Patterns

## Reserved IP Pricing

**Reserved public IPs are free on OCI — assigned or unassigned, any quantity.**

This differs from AWS (charges for idle Elastic IPs) and Azure (charges for static IPs).
Verified empirically: a reserved IP was created, attached to a running instance, detached, and deleted with zero cost impact.

---

## Current Reserved IPs (managed by Terraform)

| Name | IP | Purpose | State |
|------|----|---------|-------|
| `k8s-ingress-ip` | `84.8.144.240` | K8s ingress / OCI CCM LB | Unassigned (pre-provisioned) |
| `bastion-ip` | `145.241.217.226` | Micro instance fixed address | Assigned to micro-instance-1 |
| `ampere-instance-1-ip` | `144.21.60.245` | Ampere node 1 | Assigned (replaced lost ephemeral) |

> **Warning:** If you delete an ephemeral public IP from a VNIC, OCI will not auto-reassign one.
> You must create a reserved IP and assign it manually. Avoid deleting ephemeral IPs outside Terraform.

---

## Option A — OCI Cloud Controller Manager owns the Load Balancer

Recommended for Talos/K8s workloads. Terraform holds only the reserved IP; the LB lifecycle is owned by K8s.

### What stays in Terraform

```hcl
# terraform.tfvars
load_balancer = null   # CCM manages the LB, not Terraform
```

The `k8s-ingress-ip` reserved IP remains in Terraform so it survives cluster rebuilds.

### K8s Service annotation

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx
  annotations:
    # Free 10 Mbps tier — omit this and OCI creates a paid flexible LB
    service.beta.kubernetes.io/oci-load-balancer-shape: "10Mbps"

    # Pin to the pre-provisioned reserved IP from Terraform output ingress_reserved_ip
    oci.oraclecloud.com/oci-load-balancer-public-ip: "84.8.144.240"
spec:
  type: LoadBalancer
```

### OCI CCM requirements

- Install the OCI Cloud Controller Manager in the cluster
- CCM needs OCI credentials: either **instance principal** (preferred — no key management) or a kubeconfig secret
- For instance principal: add IAM policy `Allow dynamic-group k8s-nodes to manage load-balancers in compartment homelab`

### IP lifecycle

```text
Terraform apply  →  reserved IP created (84.8.144.240), unassigned
K8s Service created  →  CCM creates OCI LB, claims 84.8.144.240
K8s Service deleted  →  CCM deletes OCI LB, IP reverts to unassigned (still in TF state)
terraform destroy  →  reserved IP deleted
```

The IP address never changes across cluster rebuilds as long as the Terraform reserved IP resource exists.

---

## Option B — Terraform owns the Load Balancer, wire backends manually

Keep `load_balancer = {}` in Terraform and add backend sets pointing at your Ampere nodes' NodePorts.
Best when you have no cloud provider in K8s (pure Talos, no CCM).

```hcl
resource "oci_load_balancer_backend_set" "ingress" {
  load_balancer_id = oci_load_balancer_load_balancer.free_tier_lb[0].id
  name             = "ingress-backend-set"
  policy           = "ROUND_ROBIN"
  health_checker {
    protocol = "TCP"
    port     = 30080
  }
}

resource "oci_load_balancer_backend" "ampere" {
  for_each         = toset(oci_core_instance.ampere_instance[*].private_ip)
  load_balancer_id = oci_load_balancer_load_balancer.free_tier_lb[0].id
  backendset_name  = oci_load_balancer_backend_set.ingress.name
  ip_address       = each.value
  port             = 30080   # ingress controller NodePort — keep in sync with K8s
}

resource "oci_load_balancer_listener" "http" {
  load_balancer_id         = oci_load_balancer_load_balancer.free_tier_lb[0].id
  name                     = "http"
  default_backend_set_name = oci_load_balancer_backend_set.ingress.name
  port                     = 80
  protocol                 = "HTTP"
}
```

**Downside:** NodePort is hardcoded in Terraform and must be kept in sync manually.

---

## Option C — Proxmox HA Floating IP

OCI reserved IPs can be moved between VNICs via API. This enables IP failover for Proxmox HA:
when Proxmox migrates a VM to a surviving node, a hook script reassigns the reserved IP to the new node.

### What Terraform provides

```hcl
# A REGIONAL reserved IP, not assigned to any instance at creation time.
# Proxmox scripts claim it on VM start.
resource "oci_core_public_ip" "proxmox_vip" {
  compartment_id = var.compartment_ocid
  lifetime       = "RESERVED"
  display_name   = "proxmox-vip"
  # private_ip_id intentionally omitted — Proxmox assigns it
}
```

### Proxmox HA hook script

Place at `/etc/pve/ha/hooks/` (called by pve-ha-manager on VM start/migrate):

```bash
#!/bin/bash
# /etc/pve/ha/hooks/assign-oci-vip
# Called with: <event> <vmid>
# Reassigns the OCI reserved IP to the node where the VM just started.

EVENT=$1
VMID=$2
RESERVED_IP_ID="ocid1.publicip.oc1...."   # from terraform output proxmox_vip_id
SUBNET_ID="..."                             # from terraform output subnet_id
OCI_PROFILE="DEFAULT"

if [[ "$EVENT" != "started" && "$EVENT" != "relocated" ]]; then
  exit 0
fi

# Find this node's private IP
NODE_IP=$(ip -4 addr show | grep "10.0.1." | awk '{print $2}' | cut -d/ -f1)

# Get private IP OCID
PRIVATE_IP_ID=$(oci network private-ip list \
  --subnet-id "$SUBNET_ID" \
  --ip-address "$NODE_IP" \
  --profile "$OCI_PROFILE" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['data'][0]['id'])")

# Reassign reserved IP to this node
oci network public-ip update \
  --public-ip-id "$RESERVED_IP_ID" \
  --private-ip-id "$PRIVATE_IP_ID" \
  --profile "$OCI_PROFILE"
```

### There is no Proxmox Cloud Controller for OCI

Unlike K8s (which has the OCI CCM), Proxmox has no native OCI integration. IP failover is always a
custom script. The pattern above is the standard approach.

---

## Recommended stack layout

```text
Terraform manages:
  ├── ingress_reserved_ip   → pre-provisioned, claimed by OCI CCM at K8s service creation
  ├── bastion_reserved_ip   → permanently assigned to micro-instance-1 (bastion)
  └── proxmox_vip_ip        → floating IP, moved by Proxmox HA hook on failover

OCI CCM manages:
  └── OCI Load Balancer     → created/deleted with K8s Service, uses ingress_reserved_ip

Proxmox HA manages:
  └── VM migration + hook   → reassigns proxmox_vip_ip to active node on failover
```
