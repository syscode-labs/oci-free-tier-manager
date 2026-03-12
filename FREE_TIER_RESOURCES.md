# OCI Always Free Resources — Complete Reference

> Last verified: March 2026 against live OCI tenancy limits via API.
> Covers two OCI account types with different free tier behaviours.

---

## Two Types of OCI Free Tier

OCI has two distinct account types, both offering "Always Free" resources but with
**important differences** in which shapes are available:

| Feature | Always Free Account | PAYG Account (with Always Free) |
|---------|--------------------|---------------------------------|
| Account type | Dedicated free-tier account | Pay-as-you-go with free allowances |
| E2.1.Micro (x86 bastion) | ✅ Available (up to 2) | ❌ Not available as a shape |
| A1.Flex OCPU granularity | Fractional (e.g. 1.33) | Integer only (1, 2, 3…) |
| A1.Flex total allowance | 4 OCPUs / 24 GB RAM | 4 OCPUs / 24 GB RAM |
| Load Balancer (10Mbps) | ✅ 1 × Always Free | ✅ 1 × Always Free |
| Network Load Balancer | ✅ 1 × Always Free | No hourly charge, pay-per-GB only |
| Block Storage | 200 GB | 200 GB |
| Object Storage | 20 GB | 20 GB |

> **How to identify**: OCI's service limit API explicitly marks Always Free resources
> with descriptions containing "Always Free" (e.g. `lb-10mbps-micro-count` =
> "10Mbps **Always Free** Load Balancer Count"). Resources without this marker are
> paid, even if they appear in the same limits list.

---

## Compute

### Ampere A1.Flex (ARM64)

- **Shape**: `VM.Standard.A1.Flex`
- **Billing type**: `LIMITED_FREE` — verified from OCI shape API
- **Total allowance**: **4 OCPUs and 24 GB RAM** across all instances
- **OCPU granularity**: Depends on account type (see table above)
- **Architecture**: ARM64 (Ampere Altra)

**Always Free configurations (integer OCPUs — PAYG accounts)**:

| Instances | OCPUs each | RAM each | Total OCPUs | Total RAM |
|-----------|-----------|---------|------------|----------|
| 4 | 1 | 6 GB | 4 | 24 GB ✅ |
| 3 | 1 | 8 GB | 3 | 24 GB (1 OCPU unused) |
| 2 | 2 | 12 GB | 4 | 24 GB ✅ |
| 1 | 4 | 24 GB | 4 | 24 GB ✅ |

**Always Free configurations (fractional OCPUs — dedicated free accounts)**:

| Instances | OCPUs each | RAM each | Total OCPUs | Total RAM |
|-----------|-----------|---------|------------|----------|
| 3 | 1.33 | 8 GB | ~4 | 24 GB ✅ |
| 4 | 1 | 6 GB | 4 | 24 GB ✅ |

> To maximise both OCPUs and RAM with integer constraints: **4 × (1 OCPU / 6 GB)**

### VM.Standard.E2.1.Micro (x86, AMD)

- **Shape**: `VM.Standard.E2.1.Micro` (fixed, not Flex)
- **Count**: Up to **2 instances**
- **CPU**: 1/8 OCPU per instance
- **RAM**: 1 GB per instance
- **Architecture**: x86_64 (AMD EPYC)
- **⚠️ Only available in dedicated Always Free accounts** — not available as a shape
  in PAYG accounts (confirmed via OCI shape list API in uk-london-1)

---

## Storage

### Block Volume Storage

| Limit | Value | Source |
|-------|-------|--------|
| Total free storage | **200 GB** per AD | `total-free-storage-gb` = "Free Volume Size (GB)" |
| Free backups | **5** | `free-backup-count` = "Free Backup Counts" |
| Minimum boot volume | 47 GB per instance | OCI minimum |

**Storage planning**:

| Config | Boot volumes | Remaining for data |
|--------|-------------|-------------------|
| 4 × A1.Flex + 2 × Micro | 4×47 + 2×47 = 282 GB | ❌ exceeds 200 GB |
| 4 × A1.Flex only | 4×47 = 188 GB | 12 GB data |
| 3 × A1.Flex only | 3×50 = 150 GB | 50 GB data |
| 3 × A1.Flex (50 GB each) | 150 GB | 50 GB for Ceph OSDs |

> Boot volumes are included in the 200 GB total. Plan carefully.

### Object Storage

- **Capacity**: 20 GB standard storage
- **API Requests**: 50,000/month (10,000 PUT, 50,000 GET)
- **No free archive tier** beyond standard limits

---

## Networking

### Virtual Cloud Networks (VCN)

- 2 VCNs, unlimited subnets per VCN
- Internet Gateway, NAT Gateway (1 per VCN), Service Gateway: free

### Load Balancer

| Type | Free? | How to identify | Notes |
|------|-------|----------------|-------|
| **Flexible LB (10 Mbps)** | ✅ **Always Free** | `lb-10mbps-micro-count` — "10Mbps Always Free LB" | 1 instance, L4+L7 |
| Flexible LB (>10 Mbps) | ❌ Paid | `lb-flexible-count` | Pay by bandwidth |
| **Network LB** | ⚠️ No hourly fee | `max-nlb-flexible-count` — no Always Free marker | Pay-per-GB processed |

> **Kubernetes (OCI CCM)**: To provision the free 10 Mbps LB instead of a paid
> flexible LB, annotate your Service with
> `service.beta.kubernetes.io/oci-load-balancer-shape: "10Mbps"`.
> Without this annotation the CCM defaults to a paid flexible shape.
> *(Full CCM annotation reference — see architectural backlog)*

### Public IP Addresses

- **Reserved IPs**: 2 reserved public IPv4 addresses (free)
- **Ephemeral IPs**: Assigned to instances at no cost

### Data Transfer

- **Outbound**: 10 TB/month free
- **Inbound**: Always free

---

## Database

### Autonomous Database

- 2 databases, 1 OCPU each, 20 GB storage each
- Types: ATP, ADW, JSON

### NoSQL Database

- 3 tables, 25 GB per table, 133M reads + 133M writes/month

---

## What We Actually Have Free — syscode vs fonderiadigitale

This repo targets two tenancies with complementary free tier profiles:

| Resource | syscode (PAYG) | fonderiadigitale (Always Free) | Combined |
|----------|---------------|-------------------------------|---------|
| A1.Flex | 4 OCPUs / 24 GB (integers) | 4 OCPUs / 24 GB (fractional) | 8 OCPUs / 48 GB |
| E2.1.Micro | ❌ Not available | ✅ 2 instances | 2 × Micro |
| Block Storage | 200 GB | 200 GB | 400 GB |
| Object Storage | 20 GB | 20 GB | 40 GB |
| Load Balancer (free) | 1 × 10 Mbps | 1 × 10 Mbps | 2 × 10 Mbps |
| Public IPs | 2 reserved | 2 reserved | 4 reserved |
| VCNs | 2 | 2 | 4 |

> The syscode PAYG account has **no E2.1.Micro** and requires **integer OCPUs**.
> If a bastion/jump host is needed it must run in fonderiadigitale or use an
> A1.Flex instance in syscode.

---

## Practical Limits for This Project (syscode tenancy)

Current deployment in `homelab` compartment, uk-london-1:

| Resource | Allocated | Free limit | Remaining |
|----------|-----------|-----------|-----------|
| A1.Flex OCPUs | 3 (3 × 1) | 4 | **1 OCPU free** |
| A1.Flex RAM | 24 GB (3 × 8) | 24 GB | **0 GB** (maxed) |
| Block Storage | 150 GB (3 × 50) | 200 GB | **50 GB** |
| Reserved IPs | 1 (ingress) | 2 | **1 remaining** |
| Load Balancer | 0 | 1 | **1 × 10 Mbps available** |

> To use the remaining free 1 OCPU: add a 4th A1.Flex instance with 1 OCPU.
> Memory must be paid (24 GB already exhausted) or reduce existing instances
> to e.g. 3 × 6 GB + 1 × 6 GB = 24 GB with 4 × 1 OCPU.

---

## Service Limits Quick Reference

| Resource | Always Free Amount |
|----------|-------------------|
| A1.Flex OCPUs | **4 total** |
| A1.Flex RAM | **24 GB total** |
| E2.1.Micro | **2** (Always Free accounts only) |
| Block Storage | **200 GB** |
| Block Storage Backups | **5** |
| Object Storage | **20 GB** |
| Load Balancer (10 Mbps) | **1** |
| Reserved Public IPs | **2** |
| VCNs | **2** |
| Outbound Transfer | **10 TB/month** |
| Autonomous Databases | **2** (1 OCPU, 20 GB each) |
| NoSQL Tables | **3** (25 GB each) |
| Functions | **2M invocations/month** |
| API Gateway | **1M requests/month** |
| Monitoring | **500M datapoints/month** |

---

## References

- [OCI Always Free Documentation](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
- [OCI Service Limits](https://docs.oracle.com/en-us/iaas/Content/General/Concepts/servicelimits.htm)
- [OCI Pricing](https://www.oracle.com/cloud/price-list.html)

---

**Last verified:** March 2026 — live API queries against syscode (PAYG) tenancy, uk-london-1
