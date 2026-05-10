# OCI Always Free Resources — Complete Reference

> Last verified: May 2026 against OCI service limits documentation, API, and empirical billing data.
> Covers two OCI account types with different Always Free behaviours.

---

## Two Types of OCI Free Tier

OCI has two distinct account types, both offering "Always Free" resources, but with
differences in how some limits are applied:

| Feature | Always Free Account | PAYG Account (with Always Free) |
|---------|--------------------|---------------------------------|
| Account type | Dedicated free-tier account | Pay-as-you-go with free allowances |
| E2.1.Micro (x86 bastion) | ✅ Available (up to 2) | ✅ Available (up to 2) |
| A1.Flex OCPU granularity | Integer (1, 2, 3…) | Integer (1, 2, 3…) |
| A1.Flex total allowance | 4 OCPUs / 24 GB RAM | 4 OCPUs / 24 GB RAM |
| Load Balancer (10 Mbps) | ✅ 1 × Always Free | ⚠️ 1 × nominally free — verify billing |
| Network Load Balancer | ✅ 1 × Always Free | ✅ 1 × Always Free |
| Block Storage | 200 GB total | 200 GB total |
| Object Storage | 20 GB | 20 GB |

> **How to identify free resources in the API**: OCI's service limit API marks Always
> Free resources with descriptions containing "Always Free" (e.g. `lb-10mbps-micro-count`
> = "10Mbps **Always Free** Load Balancer Count"). Some Always Free resources (e.g. the
> Network Load Balancer) do not carry this marker in the API response but are still free
> — cross-reference with the [official Always Free documentation](#references).

---

## Compute

### Ampere A1.Flex (ARM64)

- **Shape**: `VM.Standard.A1.Flex`
- **Billing type**: `LIMITED_FREE` — reported by OCI shape API
- **Total allowance**: **4 OCPUs and 24 GB RAM** across all instances in the tenancy
- **OCPU granularity**: Integer values only (1, 2, 3, 4)
- **Architecture**: ARM64 (Ampere Altra)

**Always Free configurations**:

| Instances | OCPUs each | RAM each | Total OCPUs | Total RAM |
|-----------|-----------|---------|------------|----------|
| 4 | 1 | 6 GB | 4 | 24 GB ✅ |
| 3 | 1 | 8 GB | 3 | 24 GB (1 OCPU unused) |
| 2 | 2 | 12 GB | 4 | 24 GB ✅ |
| 1 | 4 | 24 GB | 4 | 24 GB ✅ |

> To maximise both OCPUs and RAM: **4 × (1 OCPU / 6 GB)**

### VM.Standard.E2.1.Micro (x86, AMD)

- **Shape**: `VM.Standard.E2.1.Micro` (fixed shape, not Flex)
- **Count**: Up to **2 instances**
- **CPU**: 1/8 OCPU per instance
- **RAM**: 1 GB per instance
- **Architecture**: x86_64 (AMD EPYC)
- **Available in both Always Free and PAYG accounts**

---

## Storage

### Block Volume Storage

| Limit | Value | Source |
|-------|-------|--------|
| Total free storage | **200 GB** total per tenancy | `total-free-storage-gb` = "Free Volume Size (GB)" |
| Free backups | **5** | `free-backup-count` = "Free Backup Counts" |
| Minimum boot volume | 50 GB per instance | OCI enforces 50 GB in practice (API docs say 47 GB) |

**Storage planning** (boot volumes count toward the 200 GB total):

| Config | Boot volumes | Remaining for data |
|--------|-------------|-------------------|
| 4 × A1.Flex + 1 × Micro | 4×50 + 50 = 250 GB | ❌ 50 GB over free tier |
| 4 × A1.Flex only | 4×50 = 200 GB | ✅ exactly at limit |
| 3 × A1.Flex only | 3×50 = 150 GB | 50 GB data |
| 2 × A1.Flex + 1 × Micro | 2×50 + 50 = 150 GB | 50 GB data |

> **Real-world note (May 2026):** Running 4×A1.Flex + 1×Micro hit 250 GB total — 50 GB over
> the free tier. The Micro's 50 GB boot volume was the unavoidable overage (~£0.07/day).
> The Micro was subsequently terminated, returning storage to exactly 200 GB.
> Boot volumes are included in the 200 GB total. Plan storage allocations carefully.

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

| Type | Free? | API identifier | Notes |
|------|-------|----------------|-------|
| **Flexible LB (10/10 Mbps)** | ⚠️ **Nominally free — verify** | `lb-10mbps-micro-count` | 1 instance, L4+L7 |
| Flexible LB (>10 Mbps) | ❌ Paid | `lb-flexible-count` | Pay by bandwidth |
| **Network LB** | ✅ **Always Free** | `max-nlb-flexible-count` | 1 instance, L4 only |

> **Kubernetes (OCI CCM)**: To stay within the free-tier bandwidth, annotate your
> Service with all three of:
> `service.beta.kubernetes.io/oci-load-balancer-shape: "flexible"`,
> `service.beta.kubernetes.io/oci-load-balancer-shape-flex-min: "10"`,
> `service.beta.kubernetes.io/oci-load-balancer-shape-flex-max: "10"`.
> Without these, the CCM defaults to a flexible LB with 100 Mbps max, which is paid.
> Prefer setting `loadBalancer.shape/flexShapeMinMbps/flexShapeMaxMbps` in the CCM
> `cloud-config` so every Service inherits the defaults.
>
> **Billing caveat (May 2026):** A flexible 10/10 Mbps LB on a PAYG tenancy was observed
> billing ~£0.24/day despite nominally qualifying for the Always Free allowance. Monitor
> costs for 48–72 hours after creating any LB and delete it if charges appear.

### Public IP Addresses

- **Reserved IPs**: Free regardless of count on a PAYG tenancy (OCI Always Free docs cite "2"
  but the PAYG service limit is much higher and all IPs are free whether assigned or not).
  Verified empirically: 4 reserved IPs running with zero billing impact.
- **Ephemeral IPs**: Assigned to instances at no cost

### Data Transfer

- **Outbound**: 10 TB/month free
- **Inbound**: Always free

---

## Database

### Autonomous Database

- 2 databases, 1 OCPU each, 20 GB storage each
- Types: ATP (OLTP), ADW (analytics), JSON

### NoSQL Database

- 3 tables, 25 GB per table, 133M reads + 133M writes/month

---

## Service Limits Quick Reference

| Resource | Always Free Amount |
|----------|-------------------|
| A1.Flex OCPUs | **4 total** |
| A1.Flex RAM | **24 GB total** |
| E2.1.Micro instances | **2** (both account types) |
| Block Storage | **200 GB total** |
| Block Storage Backups | **5** |
| Object Storage | **20 GB** |
| Load Balancer (10 Mbps) | **1** |
| Network Load Balancer | **1** |
| Reserved Public IPs | **free (unlimited on PAYG)** |
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

**Last verified:** May 2026 — OCI service limits documentation, API, and empirical billing data
