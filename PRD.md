# Product Requirements Document (PRD)
## OCI Free Tier Manager

**Document Version:** 1.0  
**Last Updated:** 2025-11-18  
**Status:** Active Development  
**Author:** Engineering Team

---

## 1. Normalized Intent

### 1.1 Who
**Primary Users:**
- DevOps engineers and infrastructure practitioners
- Developers learning Kubernetes and cloud-native technologies
- Self-hosters seeking free, production-grade infrastructure
- Students and hobbyists exploring distributed systems

**Stakeholders:**
- Individual contributors (primary)
- Open-source community
- Oracle Cloud Infrastructure (platform provider)

### 1.2 What
A comprehensive automation toolkit that maximizes Oracle Cloud Infrastructure (OCI) Always Free tier resources to deploy a production-grade Kubernetes cluster with zero ongoing costs.

**Core Components:**
1. Python availability monitoring script
2. Terraform infrastructure-as-code configurations
3. Packer image building pipelines (base hardened + Proxmox)
4. Kubernetes deployment automation (Talos Linux on Proxmox)
5. Observability stack (Grafana Cloud integration)

### 1.3 Why
**Problem Statement:**
OCI provides generous Always Free tier resources (4 ARM cores, 24GB RAM, 200GB storage), but:
- Ampere A1 instances are frequently unavailable due to high demand
- Manual monitoring of availability is tedious and inefficient
- Complex configuration required to stay within free tier limits
- Risk of accidental charges without proper guardrails
- Lack of reference architecture for maximizing free tier value

**Business Value:**
- **Cost savings:** $300-500/month equivalent infrastructure at $0 cost
- **Learning platform:** Production-grade K8s, Proxmox, Ceph, Tailscale
- **Flexibility:** Full control vs. managed services (EKS, GKE, AKS)
- **Portability:** Skills transferable to enterprise environments

### 1.4 Constraints
**Technical Constraints:**
- OCI Always Free limits: 4 OCPU, 24GB RAM, 200GB storage, 2 reserved IPs
- Ampere A1 availability is unpredictable (requires monitoring)
- Object Storage: 20GB limit for custom images
- Network: 10TB/month egress (sufficient for most workloads)
- Micro instances: fixed shape (1/8 OCPU, 1GB RAM, x86)

**Operational Constraints:**
- PAYG account recommended (better availability, requires credit card)
- Budget alert at $0.01 threshold (critical safety net)
- Must maintain zero-cost operation
- UK region preferred (uk-london-1)

**Dependencies:**
- OCI CLI configured with valid credentials
- Terraform 1.0+, Packer, Talosctl
- GitHub account (for manifest hosting)
- Grafana Cloud free tier account
- Tailscale account for mesh networking

---

## 2. Related Context

### 2.1 Past Work
- Project structure established with Terraform configurations
- Availability checker script implemented and tested
- Documentation written (README, WARP.md, PLAN.md)
- Architecture decisions documented (ARCHITECTURE.md, DEPLOYMENT-SUMMARY.md)

### 2.2 Similar Solutions
**Alternatives Comparison:**

| Solution | Cost | Control | Complexity | Free Tier |
|----------|------|---------|------------|-----------|
| OCI Free Tier (this) | $0 | Full | High | Forever |
| AWS EKS Free Tier | $73/mo* | Medium | Medium | 12 months |
| GCP GKE Autopilot | $73/mo* | Low | Low | $300 credit |
| DigitalOcean K8s | $48/mo | Low | Low | None |
| Self-hosted (own hardware) | Hardware cost | Full | High | N/A |

*EKS/GKE control plane cost; worker nodes additional

**Key Differentiators:**
- Only solution with permanent $0 cost
- Production-grade architecture (HA, distributed storage, monitoring)
- Educational value (Proxmox, Ceph, Talos, Cilium)
- Automation-first approach (availability monitoring, IaC)

### 2.3 Related Metrics
**Current Project State:**
- Repository structure: Complete
- Terraform modules: Functional (needs custom image integration)
- Packer configurations: Not yet implemented
- Kubernetes manifests: Documented, not yet created
- Monitoring stack: Architecture defined, not deployed

**Community Interest:**
- Target audience: 10k+ potential users (based on similar projects)
- OCI free tier search volume: High demand, limited documentation
- Pain points validated: Ampere availability is widely reported issue

---

## 3. Outcomes and KPIs

### 3.1 Primary Outcomes
**User Outcomes:**
1. Successfully deploy 3-node K8s cluster on OCI free tier within 4 hours
2. Zero ongoing operational costs (verified monthly)
3. Production-grade observability via Grafana Cloud
4. 99%+ cluster uptime (limited by OCI SLA)

**Technical Outcomes:**
1. Automated Ampere availability detection (15-minute polling)
2. One-command infrastructure deployment (`terraform apply`)
3. Reproducible image builds with Packer
4. Automated safety nets (budget alerts, resource limits)

### 3.2 Key Performance Indicators

**Adoption Metrics:**
- GitHub stars (target: 500+ in 6 months)
- Successful deployments (tracked via telemetry opt-in, target: 100+)
- Documentation visits (target: 5k/month)
- Community contributions (PRs, issues, discussions)

**Operational Metrics:**
- Availability checker success rate (% of checks that successfully query OCI)
- Ampere detection accuracy (true positive rate when capacity available)
- Terraform apply success rate (target: >95%)
- Image build success rate (target: >98%)

**Cost Metrics (Critical):**
- Users staying within $0.01/month (target: 100%)
- Budget alert false positive rate (target: <1%)
- Average monthly OCI bill (target: $0.00)

**User Experience Metrics:**
- Time to first successful deployment (target: <4 hours)
- Documentation completeness score (community feedback)
- Support request volume (lower is better, indicates good docs)

### 3.3 Success Criteria
**MVP Success (Phase 1-3):**
- [ ] Packer builds produce <20GB total images
- [ ] Terraform deploys 4 instances without errors
- [ ] Proxmox cluster achieves quorum and Ceph health OK
- [ ] Budget alert triggers on any cost >$0.01
- [ ] Documentation enables first-time user to deploy independently

**V1.0 Success (Phase 4-5):**
- [ ] Talos K8s cluster bootstraps successfully
- [ ] Cilium CNI operational with kube-proxy-free mode
- [ ] Grafana Cloud monitoring operational
- [ ] 10+ external users report successful deployments
- [ ] Zero unresolved critical bugs

---

## 4. Users and Scenarios

### 4.1 Primary Personas

**Persona 1: "Alex the Learner"**
- Background: Developer with 2-3 years experience, wants to learn K8s
- Goals: Hands-on experience with production architecture
- Pain points: AWS/GCP free tiers too limited or expired
- Technical level: Comfortable with CLI, basic IaC knowledge
- Success: Deploys cluster, runs sample apps, learns observability

**Persona 2: "Jordan the Self-Hoster"**
- Background: Experienced DevOps engineer, runs personal services
- Goals: Free, reliable platform for side projects (blog, APIs, tools)
- Pain points: Home lab power costs, dynamic IP issues
- Technical level: Expert (knows K8s, Terraform, Ansible)
- Success: Migrates services to OCI cluster, reduces costs to $0

**Persona 3: "Sam the Student"**
- Background: CS student, building portfolio projects
- Goals: Free hosting for capstone project, learn cloud technologies
- Pain points: Limited budget, need production-like environment
- Technical level: Intermediate (knows Docker, learning K8s)
- Success: Hosts portfolio site, demonstrates K8s skills to employers

### 4.2 User Scenarios

**Scenario 1: First-Time Deployment**
```
Given: User has OCI free tier account, basic CLI knowledge
When: User follows README quick start guide
Then: 
- Availability checker runs and detects capacity
- Terraform deploys infrastructure in 30 minutes
- User receives SSH access to all instances
- Budget alert confirms $0 charges
```

**Scenario 2: Ampere Unavailability**
```
Given: Ampere A1 instances are out of capacity (common scenario)
When: User runs availability checker in cron job (*/30 * * * *)
Then:
- Script polls every 30 minutes automatically
- Notifies user when capacity available
- User triggers Terraform apply
- Infrastructure deploys before capacity disappears
```

**Scenario 3: Accidental Cost Overrun**
```
Given: User accidentally creates paid resource (e.g., wrong instance shape)
When: OCI bills >$0.01 for any resource
Then:
- Budget alert emails user within 1 hour
- User identifies paid resource in OCI console
- User terminates resource immediately
- Total cost < $1 (caught early)
```

**Scenario 4: Kubernetes Application Deployment**
```
Given: K8s cluster is operational
When: User deploys application with Ingress
Then:
- Application accessible via reserved IP #2
- Tailscale allows internal-only services
- Grafana Cloud shows application metrics and logs
- Application runs reliably with zero ongoing cost
```

**Scenario 5: Cluster Maintenance**
```
Given: Security updates available for Proxmox/Talos
When: User follows upgrade procedure
Then:
- Rolling updates maintain cluster availability
- Ceph ensures VM migration without downtime
- Monitoring validates cluster health post-update
- No user-visible service interruption
```

---

## 5. Scope and Non-Goals

### 5.1 In Scope (V1.0)

**Phase 1: Image Building**
- ✅ Packer configuration for base-hardened image (Debian 12 + SSH + Tailscale)
- ✅ Packer configuration for Proxmox-Ampere image (base + Proxmox VE + Ceph)
- ✅ Automated upload to OCI Object Storage
- ✅ Custom image creation via OCI CLI

**Phase 2: Infrastructure**
- ✅ Terraform module for 3 Ampere + 1 Micro deployment
- ✅ Reserved IP management (2 IPs: bastion + ingress)
- ✅ Budget alert configuration ($0.01 threshold)
- ✅ VCN, security lists, DNS zone setup
- ✅ Tailscale integration documentation

**Phase 3: Proxmox + Ceph**
- ✅ Proxmox cluster formation (3-node quorum)
- ✅ Ceph configuration (distributed storage)
- ✅ Proxmox Helper Scripts integration (tteck/Proxmox)
- ✅ VM live migration validation

**Phase 4: Kubernetes**
- ✅ Talos Linux VM creation on Proxmox
- ✅ K8s cluster bootstrapping
- ✅ Cilium CNI deployment (kube-proxy-free + Hubble)
- ✅ Tailscale Operator for internal services
- ✅ OCI CCM for LoadBalancer support (optional)
- ✅ Ingress controller with reserved IP #2

**Phase 5: Monitoring**
- ✅ Grafana Alloy agent deployment
- ✅ Grafana Cloud integration (Prometheus, Loki, Tempo)
- ✅ Pre-built dashboards (Proxmox, K8s, Ceph, Tailscale)
- ✅ Alert rules for critical failures

**Cross-Cutting**
- ✅ Comprehensive documentation (README, PLAN, PRD, WARP.md)
- ✅ Automated testing (Terraform validate, Packer build tests)
- ✅ Example configurations and troubleshooting guides
- ✅ Cost verification procedures

### 5.2 Out of Scope (Future Work)

**Not in V1.0:**
- ❌ GitOps workflow (Flux/ArgoCD) - users can add manually
- ❌ Multi-region deployments - free tier supports 1 region only
- ❌ Automated backup to external providers (can use OCI Object Storage)
- ❌ Service mesh (Istio/Linkerd) - resource constraints
- ❌ CI/CD pipelines (GitHub Actions/Jenkins) - users configure separately
- ❌ Database operators (PostgreSQL/MySQL) - users deploy as needed
- ❌ Certificate management automation (cert-manager) - documented but not automated
- ❌ Secrets management (External Secrets Operator) - users configure separately

**Explicitly Non-Goals:**
- ❌ Paid resource support (project is free-tier-only by design)
- ❌ Windows workloads (free tier is Linux-only)
- ❌ GPU workloads (not available in free tier)
- ❌ Managed Kubernetes (defeats purpose of learning/control)
- ❌ Multi-tenancy (single-user assumption)

### 5.3 Future Roadmap (Post-V1.0)

**V1.1 - Hardening & HA:**
- Network policies (default-deny, fine-grained rules)
- Automated backup/restore procedures
- Disaster recovery runbooks
- Security scanning (Trivy, Falco)

**V1.2 - DX Improvements:**
- CLI tool for common operations (`octfm status`, `octfm upgrade`)
- Ansible playbooks for post-deployment configuration
- Pre-configured application templates (WordPress, Ghost, etc.)
- Interactive deployment wizard

**V2.0 - Advanced Features:**
- Multi-cluster management (if user has multiple OCI accounts)
- Cost optimization recommendations
- Capacity planning tools
- Community-contributed integrations

---

## 6. UX Flows

### 6.1 Initial Setup Flow

```
[User Starts]
    ↓
[Install Prerequisites]
    - OCI CLI → oci setup config
    - Terraform → brew install terraform
    - Packer → brew install packer
    - Talosctl → brew install talosctl
    ↓
[Clone Repository]
    - git clone oci-free-tier-manager
    - cd oci-free-tier-manager
    ↓
[Configure Credentials]
    - Edit terraform/terraform.tfvars
    - Add OCI API keys, compartment IDs
    - Add SSH public key
    ↓
[Check Availability]
    - ./check_availability.py
    - If unavailable: setup cron job, wait
    - If available: proceed
    ↓
[Phase 1: Build Images]
    - cd packer
    - packer build base-hardened.pkr.hcl
    - packer build proxmox-ampere.pkr.hcl
    - Upload to OCI Object Storage
    - Create custom images
    ↓
[Phase 2: Deploy Infrastructure]
    - cd terraform
    - terraform init
    - terraform plan (verify $0 cost)
    - terraform apply
    ↓
[Verify Infrastructure]
    - SSH to bastion
    - Verify Tailscale mesh
    - Access Proxmox UI (https://node:8006)
    ↓
[Success: Infrastructure Ready]
```

### 6.2 Kubernetes Deployment Flow

```
[Infrastructure Ready]
    ↓
[Phase 3: Configure Proxmox]
    - SSH to Ampere node 1
    - pvecm create cluster-name
    - SSH to nodes 2-3: pvecm add <node1-ip>
    - Initialize Ceph: pveceph install, init, mon create
    - Create Ceph pool: pveceph pool create vm-storage
    - Test VM migration
    ↓
[Phase 4: Deploy Talos]
    - Download Talos ARM64 ISO
    - Upload to Proxmox
    - Create 3 VMs via Proxmox CLI/UI
    - Generate Talos configs: talosctl gen config
    - Apply configs to VMs
    - Bootstrap etcd: talosctl bootstrap
    - Get kubeconfig
    ↓
[Install CNI & Operators]
    - Apply Cilium manifest (from external repo)
    - Apply OCI CCM manifest (optional)
    - Apply Tailscale Operator manifest
    - Verify all pods running
    ↓
[Configure Ingress]
    - Deploy ingress-nginx
    - Configure 1:1 NAT on Proxmox for reserved IP #2
    - Update DNS records
    - Test public access
    ↓
[Phase 5: Deploy Monitoring]
    - Create Grafana Cloud account
    - Get API keys (Prometheus, Loki, Tempo)
    - Deploy Alloy agent: helm install alloy
    - Import dashboards
    - Verify metrics/logs flowing
    ↓
[Success: K8s Cluster Ready]
```

### 6.3 Ongoing Operations Flow

```
[Cluster Operational]
    ↓
┌─────────────────────────────────────────┐
│ Daily: Automated Monitoring             │
│ - Grafana Cloud dashboards              │
│ - Budget alert monitoring (email)       │
│ - Tailscale mesh health                 │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ Weekly: Application Deployment          │
│ - Deploy apps via kubectl/helm          │
│ - Configure Ingress for public services │
│ - Expose internal services via Tailscale│
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ Monthly: Maintenance                    │
│ - Update Proxmox (rolling)              │
│ - Update Talos images                   │
│ - Review Grafana Cloud usage (stay <50GB)│
│ - Verify $0 OCI bill                    │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ As-Needed: Troubleshooting              │
│ - Check logs in Grafana Cloud           │
│ - SSH to bastion → Tailscale to nodes  │
│ - Proxmox UI for VM status              │
│ - Ceph health checks                    │
└─────────────────────────────────────────┘
```

### 6.4 Error Recovery Flow

```
[Error Detected]
    ↓
┌─────────────────────────────────────────┐
│ Budget Alert Triggered                  │
│ - Check email for alert                 │
│ - Login to OCI Console                  │
│ - Identify paid resource                │
│ - Terminate immediately                 │
│ - Verify bill <$1                       │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ Node Failure                            │
│ - Grafana alerts on node down           │
│ - Check Proxmox cluster status          │
│ - If Ampere node: quorum may be lost    │
│ - If Micro bastion: access via Tailscale│
│ - Reboot/recreate via Terraform         │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ Ceph Degraded                           │
│ - Check ceph health detail              │
│ - Identify failed OSDs                  │
│ - Repair or recreate OSDs               │
│ - Wait for Ceph recovery                │
│ - Verify ceph health OK                 │
└─────────────────────────────────────────┘
```

---

## 7. Functional Requirements

### 7.1 Availability Checker

**REQ-1.1: Ampere Availability Detection**
```
Given: User has OCI CLI configured
When: User runs ./check_availability.py
Then: Script queries all availability domains in region
  And: Returns exit code 0 if Ampere capacity available
  And: Returns exit code 1 if no capacity available
  And: Logs timestamp and availability status
```

**REQ-1.2: Micro Availability Detection**
```
Given: User has OCI CLI configured
When: User runs ./check_availability.py
Then: Script queries E2.1.Micro availability
  And: Reports status for Micro instances separately
  And: Checks only one AD (Micro restriction)
```

**REQ-1.3: Error Handling**
```
Given: OCI API is unavailable or credentials invalid
When: Script attempts API call
Then: Log clear error message with troubleshooting guidance
  And: Return exit code 1
  And: Do not crash or expose credentials
```

### 7.2 Image Building

**REQ-2.1: Base Image Build**
```
Given: Packer is installed and configured
When: User runs packer build base-hardened.pkr.hcl
Then: Create Debian 12 minimal image
  And: Install SSH server with hardened config
  And: Install Tailscale
  And: Configure firewall rules
  And: Enable automatic security updates
  And: Output base-hardened.qcow2 <10GB
```

**REQ-2.2: Proxmox Image Build**
```
Given: Base image exists as base-hardened.qcow2
When: User runs packer build proxmox-ampere.pkr.hcl
Then: Start from base image
  And: Install Proxmox VE (official script)
  And: Run tteck post-pve-install script
  And: Install Ceph packages (ceph-mon, ceph-osd, ceph-mgr)
  And: Output proxmox-ampere.qcow2 <10GB
  And: Total both images <20GB
```

**REQ-2.3: Image Upload**
```
Given: Images built successfully
When: User uploads to OCI Object Storage
Then: Verify total storage <20GB (within free tier)
  And: Create OCI custom images from uploaded files
  And: Output image OCIDs for Terraform
```

### 7.3 Infrastructure Provisioning

**REQ-3.1: Terraform Validation**
```
Given: User has configured terraform.tfvars
When: User runs terraform plan
Then: Validate all resources are free tier eligible
  And: Calculate total: 4 OCPU, 24GB RAM, 200GB storage
  And: Show $0 estimated cost
  And: Display resource counts and configurations
```

**REQ-3.2: Compute Instance Creation**
```
Given: Terraform plan validated
When: User runs terraform apply
Then: Create 3 Ampere A1 instances with proxmox-ampere image
  And: Create 1 E2.1.Micro instance with base-hardened image
  And: Assign ephemeral IPs to Ampere nodes
  And: Assign reserved IP #1 to Micro bastion
  And: Inject SSH public key
  And: Output instance IPs and SSH commands
```

**REQ-3.3: Networking Configuration**
```
Given: Terraform apply in progress
When: Network resources are created
Then: Create VCN with CIDR 10.0.0.0/16
  And: Create public subnet with Internet Gateway
  And: Configure security list: allow 22, 80, 443, ICMP
  And: Create 2 reserved public IPs
  And: Create OCI DNS zone (optional)
```

**REQ-3.4: Budget Alert Creation**
```
Given: User has tenancy administrator privileges
When: Terraform creates budget resource
Then: Set threshold to $0.01
  And: Configure email alert to user-provided address
  And: Target compartment-level costs
  And: Enable immediate alerts (monthly reset)
```

### 7.4 Proxmox Cluster

**REQ-4.1: Cluster Formation**
```
Given: 3 Ampere instances running Proxmox
When: User executes pvecm create on node 1
  And: User executes pvecm add on nodes 2-3
Then: Proxmox cluster achieves quorum (3/3 nodes)
  And: pvecm status shows all nodes joined
  And: Cluster tolerates 1 node failure
```

**REQ-4.2: Ceph Configuration**
```
Given: Proxmox cluster has quorum
When: User initializes Ceph on all nodes
Then: Ceph monitors created on all 3 nodes
  And: OSDs created from available storage
  And: Ceph pool created for VM storage
  And: ceph health reports HEALTH_OK
  And: Replication factor: 2 (min_size: 1)
```

**REQ-4.3: VM Migration**
```
Given: Ceph is healthy and VMs are running
When: User executes qm migrate <vmid> <target-node> --online
Then: VM remains running (no downtime)
  And: VM responds to ping throughout migration
  And: Migration completes in <2 minutes
  And: VM storage accessible from target node
```

### 7.5 Kubernetes Deployment

**REQ-5.1: Talos VM Creation**
```
Given: Proxmox cluster operational
When: User creates 3 VMs from Talos ISO
Then: Allocate 4GB RAM, 1.33 OCPU per VM
  And: Allocate 20GB storage per VM (from Ceph)
  And: Configure network bridge to vmbr0
  And: VMs boot from Talos ISO
```

**REQ-5.2: K8s Cluster Bootstrap**
```
Given: 3 Talos VMs running
When: User applies Talos configuration
  And: User bootstraps etcd on first control plane
Then: 3-node K8s control plane forms
  And: etcd achieves quorum
  And: User obtains valid kubeconfig
  And: kubectl cluster-info succeeds
```

**REQ-5.3: CNI Deployment**
```
Given: K8s cluster bootstrapped (no CNI yet)
When: User applies Cilium manifest from external URL
Then: Cilium deploys in kube-proxy-free mode
  And: All nodes transition to Ready state
  And: Hubble observability enabled
  And: Pod-to-pod networking functional
```

**REQ-5.4: Ingress Configuration**
```
Given: Cilium CNI operational
When: User deploys ingress-nginx
  And: User configures 1:1 NAT on Proxmox (reserved IP #2 → K8s NodePort)
Then: External traffic routes to ingress controller
  And: Ingress resources expose services publicly
  And: TLS termination functional (user-provided certs)
```

### 7.6 Monitoring

**REQ-6.1: Alloy Agent Deployment**
```
Given: K8s cluster operational
When: User deploys Grafana Alloy via Helm
Then: Alloy DaemonSet runs on all nodes
  And: Collects metrics from Talos nodes, K8s cluster
  And: Collects logs from all pods
  And: Remote writes to Grafana Cloud
```

**REQ-6.2: Grafana Cloud Integration**
```
Given: Alloy agents deployed with credentials
When: Metrics and logs start flowing
Then: Grafana Cloud receives <10k metric series (free tier limit)
  And: Grafana Cloud receives <50GB logs/month (free tier limit)
  And: Data retention: 14 days
  And: Pre-built dashboards display data correctly
```

**REQ-6.3: Alerting**
```
Given: Monitoring operational
When: Critical condition occurs (node down, Ceph degraded, budget alert)
Then: Grafana Cloud triggers alert within 5 minutes
  And: User receives email notification
  And: Alert includes context and remediation guidance
```

---

## 8. Non-Functional Requirements

### 8.1 Performance

**NFR-1: Infrastructure Provisioning Speed**
- Target: Terraform apply completes in <30 minutes (excluding image upload)
- Measurement: Time from `terraform apply` to SSH access available
- Constraint: Limited by OCI API rate limits and instance boot time

**NFR-2: Image Build Speed**
- Target: Base image builds in <15 minutes, Proxmox image in <25 minutes
- Measurement: Packer build duration
- Constraint: Limited by package download speeds and installation scripts

**NFR-3: Cluster Bootstrap Speed**
- Target: K8s cluster fully operational in <20 minutes
- Measurement: Time from Talos VM creation to all pods Running
- Constraint: Limited by Cilium image pulls and etcd initialization

**NFR-4: Availability Checker Latency**
- Target: Script completes in <10 seconds
- Measurement: Time from execution to exit
- Constraint: OCI API response time (typically 2-5 seconds)

### 8.2 Reliability & Availability

**NFR-5: Cluster High Availability**
- Target: 99% uptime (limited by OCI SLA, not architecture)
- Single node failure: Cluster remains operational (quorum: 2/3)
- Storage resilience: Ceph tolerates 1 node failure (replication factor 2)
- Monitoring: Detect failures within 5 minutes

**NFR-6: Data Durability**
- Target: 99.9% durability for VM data on Ceph
- Strategy: Replication factor 2, min_size 1
- Backup: User-configured (OCI Object Storage, external)

**NFR-7: Failover Capabilities**
- VM migration: <2 minutes downtime (live migration)
- Control plane: etcd quorum maintained with 1 node loss
- Ingress: Load balanced across nodes (if multiple replicas)

### 8.3 Security

**NFR-8: Network Security**
- Bastion-only public SSH access (no direct SSH to Ampere nodes)
- Tailscale mesh for internal communication (encrypted)
- Security list: minimal open ports (22, 80, 443, ICMP)
- K8s network policies: default-deny (user-configured)

**NFR-9: Image Hardening**
- SSH: Key-only authentication, no passwords
- Firewall: Configured by default (nftables/iptables)
- Updates: Automatic security updates enabled
- Proxmox: Enterprise nag removed, community repos only

**NFR-10: Secrets Management**
- OCI credentials: Stored in terraform.tfvars (gitignored)
- Tailscale keys: Provided via environment variables
- Grafana Cloud keys: Provided via Helm values (gitignored)
- K8s secrets: Stored as native Secrets (user-managed)

**NFR-11: Budget Protection**
- Budget alert: <1 hour notification delay
- Alert threshold: $0.01 (catch any charges immediately)
- Terraform validation: Prevent paid resource creation
- Documentation: Clear warnings about paid resources

### 8.4 Scalability

**NFR-12: Resource Limits**
- Hard limits: 4 OCPU, 24GB RAM, 200GB storage (OCI free tier)
- No horizontal scaling beyond 3 Ampere + 1 Micro
- Vertical scaling: Not possible (free tier fixed)
- Workload scaling: Within K8s cluster (pod autoscaling supported)

**NFR-13: Storage Scaling**
- Ceph pool: 150GB usable (3 nodes × 50GB storage)
- VM storage: Limited by Ceph pool capacity
- Block volumes: Cannot add more (200GB total limit)

### 8.5 Maintainability

**NFR-14: Documentation Quality**
- README: Complete quick start guide (<5 minutes to understand)
- PLAN.md: Step-by-step deployment instructions
- PRD.md: Comprehensive requirements and context
- WARP.md: AI agent guidance for automated assistance
- ARCHITECTURE.md: System design and decisions

**NFR-15: Code Quality**
- Terraform: HCL formatting via `terraform fmt`
- Python: PEP 8 compliant (linting with ruff)
- Comments: Inline documentation for complex logic
- Version control: Conventional commits, atomic changes

**NFR-16: Upgradeability**
- Proxmox: Rolling updates (one node at a time)
- Talos: Declarative updates via Talosctl
- K8s components: Helm chart updates
- Infrastructure: Terraform state management

### 8.6 Observability

**NFR-17: Logging**
- Centralized: All logs in Grafana Loki (14-day retention)
- Structured: JSON logs where possible
- Coverage: K8s pods, Talos nodes, Proxmox audit logs
- Query: LogQL queries in Grafana Cloud

**NFR-18: Metrics**
- Collection: Prometheus metrics via Alloy agents
- Retention: 14 days (Grafana Cloud free tier)
- Dashboards: Pre-built for Proxmox, K8s, Ceph, Tailscale
- Cardinality: <10k series (within free tier limit)

**NFR-19: Tracing**
- Optional: Tempo integration for distributed tracing
- Coverage: Application-level tracing (user-deployed apps)
- Retention: 14 days, 50GB/month limit

### 8.7 Usability

**NFR-20: Developer Experience**
- Prerequisites: Clearly documented, testable (oci --version)
- Error messages: Actionable, with troubleshooting links
- Outputs: Terraform outputs provide SSH commands, IPs
- Idempotency: Re-running commands is safe

**NFR-21: Time to Value**
- First deployment: <4 hours for experienced users
- Availability monitoring: Setup in <5 minutes
- Learning curve: Documented prerequisites, expected skill level

### 8.8 Cost Constraints

**NFR-22: Zero-Cost Operation (CRITICAL)**
- OCI bill: $0.00/month (verified via budget reports)
- Grafana Cloud: Within free tier (<10k series, <50GB logs)
- Tailscale: Free tier (up to 100 devices)
- Total monthly cost: $0.00

**NFR-23: Cost Monitoring**
- Real-time: Budget alert within 1 hour of charge
- Monthly: Automated cost verification procedure
- Visibility: OCI usage API queries, billing console

---

## 9. Design & Rollout

### 9.1 System Architecture

**High-Level Components:**
```
┌─────────────────────────────────────────────────────────────┐
│                       OCI Free Tier                          │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │  Ampere A1   │  │  Ampere A1   │  │  Ampere A1   │     │
│  │  Proxmox VE  │  │  Proxmox VE  │  │  Proxmox VE  │     │
│  │  + Ceph OSD  │  │  + Ceph OSD  │  │  + Ceph OSD  │     │
│  │              │  │              │  │              │     │
│  │ ┌──────────┐ │  │ ┌──────────┐ │  │ ┌──────────┐ │     │
│  │ │ Talos VM │ │  │ │ Talos VM │ │  │ │ Talos VM │ │     │
│  │ │  K8s CP  │ │  │ │  K8s CP  │ │  │ │  K8s CP  │ │     │
│  │ └──────────┘ │  │ └──────────┘ │  │ └──────────┘ │     │
│  │              │  │              │  │              │     │
│  │ Tailscale LXC│  │ Tailscale LXC│  │ Tailscale LXC│     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│         ↓                  ↓                  ↓             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │           Ceph Distributed Storage                   │  │
│  │           (Replication Factor 2)                     │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────┐         ┌──────────────┐                 │
│  │ E2.1.Micro   │         │ Reserved IPs │                 │
│  │ Bastion      │◄────────┤ #1: Bastion  │                 │
│  │ (Hardened)   │         │ #2: Ingress  │                 │
│  └──────────────┘         └──────────────┘                 │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                           ↓
                  ┌──────────────────┐
                  │ Tailscale Mesh   │
                  │ (Encrypted WG)   │
                  └──────────────────┘
                           ↓
                  ┌──────────────────┐
                  │ Grafana Cloud    │
                  │ (Monitoring)     │
                  └──────────────────┘
```

**Data Flow:**
1. User → Bastion (SSH, reserved IP #1)
2. Bastion → Ampere nodes (via Tailscale)
3. Ampere nodes → Ceph (internal storage replication)
4. Talos VMs → Cilium (pod networking)
5. Ingress controller ← Reserved IP #2 (via Proxmox NAT)
6. Alloy agents → Grafana Cloud (metrics, logs, traces)

### 9.2 Technology Stack

**Infrastructure:**
- OCI: Always Free tier (uk-london-1)
- Terraform: Infrastructure-as-Code
- Packer: Custom image building

**Compute:**
- Proxmox VE: Type 1 hypervisor
- Talos Linux: Immutable K8s OS
- Kubernetes: v1.29+ (latest Talos-supported)

**Storage:**
- Ceph: Distributed storage
- Block volumes: OCI Block Storage (200GB total)

**Networking:**
- Cilium: CNI (kube-proxy-free mode)
- Tailscale: Mesh networking (WireGuard-based)
- OCI VCN: Virtual networking
- OCI DNS: Custom domain management (optional)

**Observability:**
- Grafana Cloud: Hosted (free tier)
- Grafana Alloy: Unified agent (metrics, logs, traces)
- Prometheus/Mimir: Metrics storage
- Loki: Log aggregation
- Tempo: Distributed tracing (optional)

**Security:**
- SSH: Key-based authentication
- Tailscale: Zero-trust network access
- OCI Security Lists: Network firewalling
- K8s Network Policies: Pod-level segmentation

### 9.3 Rollout Strategy

**Phase-Based Rollout:**

**Phase 0: Validation (1 week)**
- Validate Packer configurations on local VM
- Test Terraform in isolated OCI compartment
- Verify budget alert triggers correctly
- Document prerequisites and dependencies

**Phase 1: MVP - Infrastructure (2 weeks)**
- Implement Packer configurations
- Upload images to OCI Object Storage
- Test Terraform deployment end-to-end
- Create comprehensive troubleshooting guide

**Phase 2: Proxmox + Ceph (2 weeks)**
- Document Proxmox cluster formation
- Test Ceph configuration and replication
- Validate VM live migration
- Create runbooks for common issues

**Phase 3: Kubernetes (2 weeks)**
- Document Talos installation
- Test K8s cluster bootstrap
- Deploy Cilium and validate networking
- Test ingress with reserved IP

**Phase 4: Monitoring (1 week)**
- Deploy Grafana Alloy agents
- Configure Grafana Cloud integration
- Create dashboards for all components
- Set up alert rules

**Phase 5: Community Launch (ongoing)**
- Publish to GitHub (README, docs)
- Create demo video walkthrough
- Write blog post / Reddit post
- Monitor issues, provide support

### 9.4 Experiment Gates

**Gate 1: Packer Image Quality**
- Criteria: Images build successfully, <20GB total, boot correctly
- Validation: Manual test in OCI, verify SSH access
- Fail condition: Images exceed 20GB or fail to boot
- Rollback: Revise Packer configs, re-test

**Gate 2: Terraform Free Tier Compliance**
- Criteria: terraform plan shows $0 cost, all resources within limits
- Validation: Review plan output, calculate resources manually
- Fail condition: Any paid resources detected
- Rollback: Fix Terraform configs, re-validate

**Gate 3: Budget Alert Functionality**
- Criteria: Alert triggers on $0.01 charge within 1 hour
- Validation: Create temporary paid resource, verify email received
- Fail condition: Alert does not trigger or delayed >2 hours
- Rollback: Debug budget configuration, test with smaller charge

**Gate 4: Proxmox + Ceph Stability**
- Criteria: Cluster quorum stable, Ceph health OK, VM migration successful
- Validation: Run for 48 hours, perform 10 VM migrations
- Fail condition: Quorum lost, Ceph degraded, migration failures
- Rollback: Debug cluster configuration, check network/storage

**Gate 5: K8s Operational Readiness**
- Criteria: All pods Running, Cilium healthy, ingress functional
- Validation: Deploy test application, access via reserved IP
- Fail condition: Pods CrashLooping, networking broken
- Rollback: Debug CNI, check Talos configuration

**Gate 6: Monitoring Completeness**
- Criteria: Metrics flowing, logs searchable, dashboards populated
- Validation: Query Grafana Cloud, verify data for all components
- Fail condition: Missing data, exceeded free tier limits
- Rollback: Adjust Alloy config, filter unnecessary data

### 9.5 Launch Criteria

**Minimum Viable Product (V1.0) Launch:**
- [ ] All 5 phases documented and tested
- [ ] At least 3 successful full deployments (internal testing)
- [ ] Zero critical bugs (P0) unresolved
- [ ] Documentation reviewed and validated by external user
- [ ] Budget alert tested and confirmed functional
- [ ] Repository published with MIT license
- [ ] GitHub README includes badges (build status, license)
- [ ] Community support channel established (GitHub Discussions)

**Success Metrics (3 months post-launch):**
- 100+ GitHub stars
- 10+ external deployments reported
- 5+ community contributions (PRs, docs improvements)
- <5 unresolved critical bugs
- Positive feedback (4+ star rating if feedback collected)

---

## 10. Risks, Decisions & Open Questions

### 10.1 Key Risks

**RISK-1: Ampere A1 Unavailability (HIGH)**
- **Impact:** Users cannot deploy infrastructure
- **Likelihood:** High (well-known issue)
- **Mitigation:** 
  - Availability checker with automated polling
  - Documentation on best times to check (off-peak hours)
  - Alternative: Deploy with 1 Ampere + 2 Micro (reduced capacity)
  - Consider multi-region checking (future feature)

**RISK-2: Accidental Cost Overruns (CRITICAL)**
- **Impact:** Users incur unexpected charges
- **Likelihood:** Medium (user error, misconfig)
- **Mitigation:**
  - Budget alert at $0.01 (immediate notification)
  - Terraform validation (prevent paid resources)
  - Clear documentation warnings
  - Automated cost verification script

**RISK-3: OCI Policy Changes (MEDIUM)**
- **Impact:** Free tier limits reduced or resources deprecated
- **Likelihood:** Low (Oracle committed to free tier)
- **Mitigation:**
  - Monitor OCI announcements
  - Architecture is adaptable (can scale down)
  - Community will report changes quickly

**RISK-4: Image Build Complexity (MEDIUM)**
- **Impact:** Users struggle with Packer, fail to build images
- **Likelihood:** Medium (Packer requires specific knowledge)
- **Mitigation:**
  - Provide pre-built images (hosted on OCI Object Storage, public bucket)
  - Detailed Packer documentation
  - Troubleshooting guide for common issues
  - Video walkthrough

**RISK-5: Proxmox/Ceph Configuration Difficulty (HIGH)**
- **Impact:** Users fail to form cluster or configure Ceph correctly
- **Likelihood:** High (advanced topics, many failure points)
- **Mitigation:**
  - Extremely detailed step-by-step documentation
  - Automated scripts where possible (Ansible playbook)
  - Common issues section in docs
  - Community support via GitHub Discussions

**RISK-6: Resource Constraints for Workloads (MEDIUM)**
- **Impact:** Users deploy apps that exceed 3-node cluster capacity
- **Likelihood:** Medium (depends on workload)
- **Mitigation:**
  - Document resource limits clearly
  - Provide example workload sizing
  - Recommend lightweight alternatives (e.g., K3s if less overhead needed)
  - Resource quotas in K8s namespaces

**RISK-7: Grafana Cloud Free Tier Limits (LOW)**
- **Impact:** Users exceed 10k series or 50GB logs, incur charges
- **Likelihood:** Low (limits are generous for 3-node cluster)
- **Mitigation:**
  - Document Grafana Cloud limits
  - Configure Alloy with sampling/filtering
  - Monitor usage in Grafana Cloud UI
  - Alert when approaching 80% of limits

**RISK-8: Tailscale Mesh Connectivity Issues (LOW)**
- **Impact:** Internal services unreachable, monitoring breaks
- **Likelihood:** Low (Tailscale is reliable)
- **Mitigation:**
  - Document Tailscale setup clearly
  - Provide fallback (direct SSH to bastion, then to nodes)
  - Monitor Tailscale status in Grafana

**RISK-9: Security Vulnerabilities (MEDIUM)**
- **Impact:** Cluster compromised, data loss, OCI account abuse
- **Likelihood:** Medium (self-hosted, user-managed)
- **Mitigation:**
  - Hardened base image (minimal packages, SSH key-only)
  - Automatic security updates enabled
  - Document security best practices
  - Recommend periodic security audits (Trivy, Falco)

**RISK-10: Community Support Scalability (MEDIUM)**
- **Impact:** User questions overwhelm maintainers
- **Likelihood:** Medium (if project becomes popular)
- **Mitigation:**
  - Comprehensive documentation reduces questions
  - GitHub Discussions for community support
  - FAQ section for common issues
  - Encourage community contributions (wiki, examples)

### 10.2 Key Decisions

**DECISION-1: Proxmox over K3s/Kubeadm**
- **Rationale:** Enables VM live migration, Ceph distributed storage, better resource isolation
- **Tradeoffs:** Increased complexity vs. simpler K3s/Kubeadm on bare metal
- **Alternatives considered:** K3s directly on Ampere (simpler, less overhead)
- **Outcome:** Proxmox chosen for learning value and HA capabilities

**DECISION-2: Talos Linux over Ubuntu/Debian K8s Nodes**
- **Rationale:** Immutable OS, API-driven, security hardened, minimal attack surface
- **Tradeoffs:** Steeper learning curve vs. familiar Ubuntu/Kubeadm
- **Alternatives considered:** Ubuntu 22.04 with Kubeadm
- **Outcome:** Talos chosen for modern approach and operational benefits

**DECISION-3: Cilium over Calico/Flannel**
- **Rationale:** kube-proxy-free mode (less overhead), Hubble observability, eBPF performance
- **Tradeoffs:** More complex vs. simpler Flannel
- **Alternatives considered:** Calico (mature, well-documented)
- **Outcome:** Cilium chosen for best-in-class CNI with observability

**DECISION-4: Tailscale over OpenVPN/WireGuard**
- **Rationale:** Zero-config mesh, NAT traversal, built-in auth, free tier sufficient
- **Tradeoffs:** External dependency vs. self-hosted VPN
- **Alternatives considered:** Self-hosted WireGuard (more control, more complex)
- **Outcome:** Tailscale chosen for ease of use and reliability

**DECISION-5: Grafana Cloud over Self-Hosted Stack**
- **Rationale:** Free tier is generous, no resource overhead, managed service
- **Tradeoffs:** External dependency vs. full control
- **Alternatives considered:** Prometheus + Loki + Grafana on K8s (consumes resources)
- **Outcome:** Grafana Cloud chosen to maximize free tier compute for workloads

**DECISION-6: PAYG Account Recommendation over Always Free Tier**
- **Rationale:** Much better Ampere A1 availability, same free tier limits
- **Tradeoffs:** Requires credit card, risk of accidental charges
- **Alternatives considered:** Always Free only (no credit card required)
- **Outcome:** PAYG recommended with $0.01 budget alert as safety net

**DECISION-7: UK Region (uk-london-1) as Default**
- **Rationale:** Geographic proximity to maintainer, EU data residency
- **Tradeoffs:** Users in other regions have higher latency
- **Alternatives considered:** us-ashburn-1 (more popular)
- **Outcome:** UK chosen, but docs include instructions for other regions

**DECISION-8: Packer Image Layering Strategy**
- **Rationale:** DRY principle, faster rebuilds, consistent base
- **Tradeoffs:** Two-stage build vs. single image
- **Alternatives considered:** Single Proxmox image (duplicates hardening work)
- **Outcome:** Layered approach chosen for maintainability

**DECISION-9: External Manifest Hosting for K8s**
- **Rationale:** Talos 1MB inline manifest limit, need for large Cilium manifests
- **Tradeoffs:** External dependency vs. inline manifests
- **Alternatives considered:** Split manifests into smaller chunks (complex)
- **Outcome:** External GitHub repo chosen, with fallback to local files

**DECISION-10: Conventional Commits for Git Workflow**
- **Rationale:** Clear commit history, easier to generate changelogs
- **Tradeoffs:** Requires discipline vs. freeform commits
- **Alternatives considered:** Freeform commits
- **Outcome:** Conventional commits enforced per user rules

### 10.3 Open Questions

**Q1: Should we provide pre-built images?**
- **Context:** Users may struggle with Packer
- **Options:** 
  - A) Provide pre-built images in public OCI bucket
  - B) Require users to build their own (security, trust)
- **Dependencies:** Need OCI bucket storage strategy
- **Timeline:** Decide before Phase 1 completion
- **Owner:** TBD

**Q2: Should we include GitOps tooling (Flux/ArgoCD)?**
- **Context:** GitOps is standard practice, but adds complexity
- **Options:**
  - A) Include in V1.0 (comprehensive solution)
  - B) Document as optional add-on (V1.1 or community contribution)
- **Dependencies:** Resource constraints (GitOps consumes memory)
- **Timeline:** Decide before Phase 4 completion
- **Owner:** TBD

**Q3: Should we support multiple cloud providers?**
- **Context:** AWS, GCP, Azure have free tiers, but different
- **Options:**
  - A) OCI-only (current scope)
  - B) Multi-cloud support (significant scope increase)
- **Dependencies:** Major architecture changes, different IaC
- **Timeline:** Post-V1.0 (future roadmap)
- **Owner:** Community contributions

**Q4: Should we include managed database (Autonomous DB)?**
- **Context:** OCI free tier includes 2x Autonomous DB (20GB each)
- **Options:**
  - A) Include in V1.0 (comprehensive)
  - B) Document as optional (reduce complexity)
- **Dependencies:** Terraform modules, database setup
- **Timeline:** Decide before Phase 2 completion (impacts Terraform)
- **Owner:** TBD

**Q5: Should we provide a CLI tool for common operations?**
- **Context:** Users repeat common commands (status, upgrade, etc.)
- **Options:**
  - A) Create CLI tool (`octfm` command) in V1.1
  - B) Rely on Terraform, kubectl, Proxmox CLI
- **Dependencies:** CLI development (Python or Go)
- **Timeline:** Post-V1.0 (V1.1 feature)
- **Owner:** TBD

**Q6: Should we include Proxmox Backup Server?**
- **Context:** Backup is critical, but PBS consumes resources
- **Options:**
  - A) Deploy PBS as LXC container (consumes RAM)
  - B) Use OCI Object Storage for backups (20GB limit)
  - C) Document external backup strategies (user-managed)
- **Dependencies:** Resource allocation, storage limits
- **Timeline:** Post-V1.0 (V1.1 feature)
- **Owner:** TBD

**Q7: Should we support ARM-based bastion instead of Micro?**
- **Context:** Could deploy 4 Ampere nodes, use one as bastion
- **Options:**
  - A) Use Micro bastion (current design, saves OCPUs for K8s)
  - B) Use 1 Ampere as bastion (more resources, but reduces K8s capacity)
- **Dependencies:** Architecture redesign
- **Timeline:** V1.0 decision (impacts PLAN.md)
- **Owner:** TBD

**Q8: Should we include service mesh (Istio/Linkerd)?**
- **Context:** Service mesh provides advanced traffic management
- **Options:**
  - A) Include in V1.0 (comprehensive)
  - B) Document as optional (resource-intensive)
- **Dependencies:** Resource constraints (Istio is heavy)
- **Timeline:** Post-V1.0 (V2.0 feature)
- **Owner:** Community contributions

**Q9: How should we handle Talos upgrades?**
- **Context:** Talos releases frequently, upgrades are declarative
- **Options:**
  - A) Provide automated upgrade scripts
  - B) Document manual upgrade process
- **Dependencies:** Testing with multiple Talos versions
- **Timeline:** V1.1 feature
- **Owner:** TBD

**Q10: Should we create a community Discord/Slack?**
- **Context:** GitHub Discussions may not be sufficient for real-time support
- **Options:**
  - A) Create Discord server (active community)
  - B) Use GitHub Discussions only (centralized, searchable)
- **Dependencies:** Maintainer availability for support
- **Timeline:** Decide at community launch
- **Owner:** TBD

---

## Appendices

### A. Glossary

- **Always Free Tier:** OCI resources that never expire and cost $0
- **Ampere A1:** ARM-based compute instances (OCI free tier)
- **Ceph:** Distributed storage system for Proxmox
- **Cilium:** eBPF-based CNI for Kubernetes
- **OCI:** Oracle Cloud Infrastructure
- **OCPUs:** Oracle CPU units (1 OCPU = 2 vCPUs)
- **Proxmox VE:** Type 1 hypervisor for VM management
- **Talos Linux:** Immutable, API-driven Kubernetes OS
- **Tailscale:** WireGuard-based mesh VPN

### B. References

- [OCI Always Free Documentation](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [Talos Linux Documentation](https://www.talos.dev/v1.9/introduction/what-is-talos/)
- [Cilium Documentation](https://docs.cilium.io/)
- [Grafana Alloy Documentation](https://grafana.com/docs/alloy/)
- [tteck/Proxmox Helper Scripts](https://github.com/tteck/Proxmox)

### C. Document Change History

| Version | Date       | Changes                          | Author         |
|---------|------------|----------------------------------|----------------|
| 1.0     | 2025-11-18 | Initial PRD creation             | Engineering    |

---

**Document Status:** ✅ Active Development  
**Next Review:** 2025-12-01 (Post Phase 1 completion)  
**Approval Required From:** Project maintainer
