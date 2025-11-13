# Complete OCI Always Free Resources List

This document provides a comprehensive list of all Oracle Cloud Infrastructure (OCI) Always Free resources, verified from official Oracle documentation as of November 2024.

## Compute Resources

### Ampere A1 Compute (ARM-based)
- **Total Allocation**: 4 OCPUs and 24 GB RAM
- **Flexibility**: Can be split across up to 4 VM instances
- **Shape**: VM.Standard.A1.Flex
- **Architecture**: ARM64 (Ampere Altra processors)
- **Monthly Allocation**: 3,000 OCPU hours and 18,000 GB-hours

**Configuration Examples**:
1. Four 1-OCPU instances with 6 GB RAM each
2. Two 2-OCPU instances with 12 GB RAM each  
3. One 4-OCPU instance with 24 GB RAM
4. One 2-OCPU instance with 12 GB + Two 1-OCPU instances with 6 GB

**Notes**:
- High demand - capacity often unavailable
- Superior price/performance for ARM-compatible workloads
- Ideal for containerized applications, web servers, development environments

### VM.Standard.E2.1.Micro (AMD-based, x86)
- **Count**: 2 instances maximum
- **Shape**: VM.Standard.E2.1.Micro (fixed)
- **CPU**: 1/8 OCPU per instance
- **Memory**: 1 GB RAM per instance
- **Architecture**: x86_64 (AMD EPYC processors)
- **Limitation**: Can only create in one availability domain

**Notes**:
- More readily available than Ampere A1
- Good for lightweight workloads, testing, small services
- Lower performance than Ampere but better compatibility

## Storage Resources

### Block Volume Storage
- **Total Allocation**: 200 GB combined
- **Components**: Includes boot volumes + block volumes
- **Minimum Boot Volume**: 47 GB per instance
- **Volume Backups**: 5 backups included
- **Performance**: Up to 10 VPUs (Volume Performance Units)

**Important Calculations**:
- 4 Ampere instances @ 47 GB each = 188 GB (12 GB remaining)
- 2 Micro instances @ 47 GB each = 94 GB (106 GB remaining)
- Plan storage allocation carefully before deployment

### Object Storage (Standard)
- **Capacity**: 20 GB total storage
- **API Requests**: 50,000 per month
- **Request Types**: 10,000 PUT/POST, 50,000 GET requests
- **Data Transfer**: Ingress free, egress covered by network allowance

**Use Cases**:
- Static website hosting
- Backup storage
- Application data storage
- Content delivery

### Archive Storage
- **Capacity**: 10 GB total storage
- **Retrieval Time**: Up to 4 hours
- **API Requests**: 10,000 per month

**Use Cases**:
- Long-term backup retention
- Compliance archives
- Cold storage

## Networking Resources

### Virtual Cloud Network (VCN)
- **Count**: 2 VCNs
- **Subnets**: Unlimited per VCN
- **CIDR Blocks**: Customizable (e.g., 10.0.0.0/16)
- **DNS**: Built-in DNS resolution

### Network Gateways
- **Internet Gateway**: Unlimited (free)
- **NAT Gateway**: 1 NAT gateway per VCN
- **Service Gateway**: Unlimited (free)
- **Dynamic Routing Gateway**: 1 DRG

### Load Balancer
- **Count**: 1 flexible load balancer
- **Bandwidth**: 10 Mbps
- **Type**: Layer 7 (HTTP/HTTPS) and Layer 4 (TCP)

**Notes**:
- Sufficient for development and small production workloads
- SSL/TLS termination supported

### Public IP Addresses
- **Reserved IPs**: 2 reserved public IPv4 addresses
- **Ephemeral IPs**: Additional ephemeral IPs assigned to instances

### Network Data Transfer
- **Outbound Transfer**: 10 TB per month
- **Inbound Transfer**: Unlimited (always free)

**Note**: Monitor usage if running bandwidth-intensive applications

### VPN Connect
- **Site-to-Site VPN**: 50 IPSec connections
- **Encryption**: Industry-standard encryption

## Database Resources

### Autonomous Database
- **Count**: 2 databases
- **OCPU**: 1 OCPU per database
- **Storage**: 20 GB per database (40 GB total)
- **Types Available**:
  - Autonomous Transaction Processing (ATP)
  - Autonomous Data Warehouse (ADW)
  - Autonomous JSON Database

**Features**:
- Automated patching and updates
- Automatic scaling (within free tier limits)
- Built-in security and encryption
- Oracle APEX included

**Limitations**:
- Cannot exceed 1 OCPU per database
- 20 GB storage limit per database

### NoSQL Database Cloud Service
- **Read Operations**: 133 million reads per month
- **Write Operations**: 133 million writes per month
- **Storage**: 25 GB per table
- **Tables**: Up to 3 tables
- **Total Storage**: 75 GB across all tables

**Features**:
- Schemaless JSON document store
- Single-digit millisecond latency
- ACID transactions

## Additional Core Services

### Monitoring
- **Metric Ingestion**: 500 million ingestion datapoints per month
- **Metric Retrieval**: 1 billion retrieval datapoints per month
- **Alarms**: 10 alarm definitions

### Notifications
- **Messages**: 1 million notification delivery options per month
- **Topics**: Unlimited topics
- **Subscriptions**: Unlimited subscriptions

**Supported Protocols**:
- Email
- SMS (may incur carrier charges)
- HTTPS webhooks
- PagerDuty, Slack integrations

### Logging
- **Log Volume**: 10 GB per month
- **Log Retention**: Configurable
- **Log Sources**: All OCI services

### Email Delivery
- **Monthly Limit**: 1,000 emails sent per month
- **Daily Limit**: 3,000 emails sent per day
- **SMTP Support**: Yes

**Use Cases**:
- Application notifications
- User registration emails
- System alerts

## Security Services

### Vault (Key Management)
- **Encryption Keys**: 20 key versions
- **Secrets**: 150 secrets
- **Master Encryption Keys**: Managed keys for encryption

**Features**:
- FIPS 140-2 Level 3 compliant
- Centralized key management
- Secret rotation support

### Bastion
- **Bastion Hosts**: 5 OCI Bastion instances
- **Sessions**: Managed SSH sessions
- **Security**: Eliminates need for public IPs on private resources

### Web Application Firewall (WAF)
- **Requests**: 10,000 requests per month
- **Protection**: OWASP Top 10 vulnerabilities

## Management and Operations

### Resource Manager (Managed Terraform)
- **Plans**: Unlimited
- **Jobs**: Unlimited
- **Stack Management**: Full Terraform state management

**Features**:
- Infrastructure as Code
- Version control integration
- Drift detection

### Service Connector Hub
- **Connectors**: 2 service connectors
- **Data Flow**: Automated data movement between services

**Examples**:
- Logs → Object Storage
- Monitoring → Notifications
- Functions → Object Storage

### Events
- **Rules**: Unlimited event rules
- **Events**: Unlimited events processed
- **Actions**: Trigger notifications, functions, streams

## Streaming and Messaging

### Streaming
- **Storage**: Up to 400 hours (configurable retention)
- **Partitions**: Limited by service quotas

### Queue
- **Messages**: Basic message queuing
- **Throughput**: Subject to service limits

## Additional Services

### Functions (Serverless)
- **Invocations**: 2 million invocations per month
- **Execution Time**: 400,000 GB-seconds per month

**Example**:
- Functions with 128 MB memory = ~3.1M seconds of execution

### API Gateway
- **Requests**: 1 million requests per month
- **Gateways**: 1 gateway

### GoldenGate Stream Analytics
- **Compute**: 1 OCPU
- **Use**: Real-time stream processing and analytics

### Digital Assistant
- **Requests**: Limited number of requests for development

### Application Performance Monitoring (APM)
- **Traces**: 1,000 traces per hour
- **Span Storage**: 1 GB per month

## Service Limits Summary Table

| Resource | Quantity | Unit |
|----------|----------|------|
| Ampere A1 OCPUs | 4 | Total |
| Ampere A1 Memory | 24 | GB |
| E2.1.Micro Instances | 2 | Instances |
| Block Storage | 200 | GB |
| Object Storage | 20 | GB |
| Outbound Transfer | 10 | TB/month |
| Autonomous Databases | 2 | Databases |
| Autonomous DB Storage | 20 | GB/database |
| NoSQL Reads | 133M | Per month |
| NoSQL Writes | 133M | Per month |
| Load Balancers | 1 | Instance |
| Public IPs | 2 | Reserved |
| VCNs | 2 | Networks |
| Monitoring Ingestion | 500M | Datapoints/month |
| Logging | 10 | GB/month |
| Email Delivery | 1,000 | Emails/month |
| Functions Invocations | 2M | Per month |
| API Gateway Requests | 1M | Per month |

## Important Notes

### Always Free vs. Free Trial
- **Always Free**: Never expires, available indefinitely
- **Free Trial**: $300 credit for 30 days, includes more resources

This document covers **Always Free** resources only.

### Resource Availability
- Ampere A1 instances may be unavailable due to high demand
- Use the availability checker script to monitor capacity
- E2.1.Micro instances are generally more available

### Geographic Restrictions
- Always Free resources available in all OCI commercial regions
- Some services may have regional limitations

### Fair Use Policy
- OCI reserves the right to reclaim idle resources
- Keep instances and services actively used
- Avoid cryptocurrency mining (violates terms of service)

### Monitoring Costs
- While services are free within limits, exceeding them incurs charges
- Use budget alerts to monitor spending
- Review cost analysis dashboard regularly

## References

- [Official OCI Free Tier Documentation](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
- [OCI Service Limits](https://docs.oracle.com/en-us/iaas/Content/General/Concepts/servicelimits.htm)
- [OCI Pricing](https://www.oracle.com/cloud/price-list.html)

---

*Last Updated: November 2024*
*Source: Official Oracle Cloud Infrastructure Documentation*
