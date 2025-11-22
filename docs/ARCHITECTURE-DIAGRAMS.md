# Architecture Diagrams

Visual representations of the OCI Free Tier infrastructure. All diagrams use explicit color styling to ensure readability on both light and dark backgrounds.

## Table of Contents

### 1. [Deployment Pipeline](#deployment-pipeline)
   - [Complete Flow](#complete-flow)
   - [Phase 0: Setup](#phase-0-setup)
   - [Phase 2: OCI Infrastructure](#phase-2-oci-infrastructure)
   - [Phase 3: Proxmox Cluster](#phase-3-proxmox-cluster)

### 2. [Talos Kubernetes](#talos-kubernetes)
   - [Architecture Overview](#architecture-overview)
   - [Bootstrap Sequence](#bootstrap-sequence)

### 3. [Terraform Layers](#terraform-layers)
   - [Three-Layer Architecture](#three-layer-architecture)

### 4. [Network Architecture](#network-architecture)
   - [Physical + Logical Topology](#physical--logical-topology)

### 5. [Cost Enforcement](#cost-enforcement)
   - [Free Tier Validation Flow](#free-tier-validation-flow)

---

## Deployment Pipeline

### Complete Flow

This diagram shows the complete deployment pipeline from initial setup to running applications.

**Related files:** [`Taskfile.yml`](../Taskfile.yml), [`QUICKSTART.md`](./QUICKSTART.md)

```mermaid
%%{init: {'theme':'base', 'themeVariables': { 'primaryColor':'#0891b2','primaryTextColor':'#fff','primaryBorderColor':'#06b6d4','lineColor':'#3b82f6','secondaryColor':'#7c3aed','tertiaryColor':'#14b8a6','textColor':'#fff','fontSize':'16px'}}}%%
flowchart TB
    Setup["Setup<br/>OCI CLI + Flux"]
    Build["Build<br/>Images"]
    OCI["OCI<br/>Infrastructure"]
    Proxmox["Proxmox<br/>Cluster"]
    Talos["Talos<br/>K8s"]
    Apps["Apps<br/>GitOps"]
    
    Setup --> Build --> OCI --> Proxmox --> Talos --> Apps
    
    style Setup fill:#15803d,stroke:#22c55e,stroke-width:3px,color:#fff
    style Build fill:#15803d,stroke:#22c55e,stroke-width:3px,color:#fff
    style OCI fill:#15803d,stroke:#22c55e,stroke-width:3px,color:#fff
    style Proxmox fill:#15803d,stroke:#22c55e,stroke-width:3px,color:#fff
    style Talos fill:#15803d,stroke:#22c55e,stroke-width:3px,color:#fff
    style Apps fill:#15803d,stroke:#22c55e,stroke-width:3px,color:#fff
```

### Phase 0: Setup

Initializes the development environment by configuring OCI CLI and setting up Flux GitOps.

**Related files:** [`scripts/setup.sh`](../scripts/setup.sh), [`scripts/setup-flux.sh`](../scripts/setup-flux.sh)

```mermaid
%%{init: {'theme':'base', 'themeVariables': { 'primaryColor':'#0891b2','primaryTextColor':'#fff','primaryBorderColor':'#06b6d4','lineColor':'#3b82f6','textColor':'#fff','fontSize':'16px'}}}%%
flowchart TB
    Start(["task setup"])
    CheckOCI{"OCI CLI?"}
    InstallOCI["oci setup config"]
    GenTF["Generate tfvars"]
    SSH["SSH Keys"]
    Done[("✓")]
    
    Start --> CheckOCI
    CheckOCI -->|Missing| InstallOCI
    CheckOCI -->|Exists| GenTF
    InstallOCI --> GenTF
    GenTF --> SSH --> Done
    
    style Start fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style CheckOCI fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style InstallOCI fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style GenTF fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style SSH fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style Done fill:#059669,stroke:#10b981,stroke-width:3px,color:#fff
```

### Phase 2: OCI Infrastructure

Provisions Oracle Cloud Infrastructure resources within free tier limits.

**Related files:** [`tofu/oci/main.tf`](../tofu/oci/main.tf)

```mermaid
%%{init: {'theme':'base', 'themeVariables': { 'primaryColor':'#0891b2','primaryTextColor':'#fff','primaryBorderColor':'#06b6d4','lineColor':'#3b82f6','textColor':'#fff'}}}%%
flowchart LR
    Start(["task deploy:oci"])
    Plan["tofu plan/apply"]
    VCN["VCN + Networking"]
    Compute["3x Ampere + 1x Micro"]
    Mesh["Tailscale Mesh"]
    Done[("✓")]
    
    Start --> Plan --> VCN --> Compute --> Mesh --> Done
    
    style Start fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style Plan fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style VCN fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style Compute fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style Mesh fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style Done fill:#059669,stroke:#10b981,stroke-width:3px,color:#fff
```

### Phase 3: Proxmox Cluster

Forms 3-node Proxmox cluster with Ceph storage.

**Related files:** [`tofu/proxmox-cluster/main.tf`](../tofu/proxmox-cluster/main.tf)

```mermaid
%%{init: {'theme':'base', 'themeVariables': { 'primaryColor':'#0891b2','primaryTextColor':'#fff','primaryBorderColor':'#06b6d4','lineColor':'#3b82f6','textColor':'#fff'}}}%%
flowchart LR
    Start(["task deploy:proxmox"])
    Cluster["Form Cluster"]
    Check1{"Quorum?"}
    Ceph["Configure Ceph"]
    Check2{"Healthy?"}
    Fail1[("❌")]
    Fail2[("❌")]
    Done[("✓")]
    
    Start --> Cluster --> Check1
    Check1 -->|No| Fail1
    Check1 -->|Yes| Ceph --> Check2
    Check2 -->|No| Fail2
    Check2 -->|Yes| Done
    
    style Start fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style Cluster fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style Check1 fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style Ceph fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style Check2 fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style Fail1 fill:#dc2626,stroke:#ef4444,stroke-width:3px,color:#fff
    style Fail2 fill:#dc2626,stroke:#ef4444,stroke-width:3px,color:#fff
    style Done fill:#059669,stroke:#10b981,stroke-width:3px,color:#fff
```

## Talos Kubernetes

### Architecture Overview

Complete technology stack from OCI instances to Kubernetes applications.

**Related files:** [`WARP.md`](../WARP.md#architecture)

```mermaid
%%{init: {'theme':'base', 'themeVariables': { 'primaryColor':'#0891b2','primaryTextColor':'#fff','primaryBorderColor':'#06b6d4','lineColor':'#3b82f6','textColor':'#fff'}}}%%
graph TB
    subgraph OCI["OCI Infrastructure"]
        Ampere["3x Ampere A1<br/>ARM64"]
        Bastion["Micro Bastion"]
    end
    
    subgraph Proxmox["Proxmox + Ceph"]
        PVE["3-node Cluster"]
    end
    
    subgraph Talos["Talos K8s"]
        CP["3x Control Plane"]
    end
    
    subgraph Apps["Applications"]
        TS["Tailscale"]
        CM["cert-manager"]
    end
    
    Ampere --> PVE
    PVE --> CP
    CP --> TS
    CP --> CM
    Bastion -.SSH.-> PVE
    
    style Ampere fill:#2563eb,stroke:#3b82f6,stroke-width:2px,color:#fff
    style Bastion fill:#2563eb,stroke:#3b82f6,stroke-width:2px,color:#fff
    style PVE fill:#7c3aed,stroke:#a855f7,stroke-width:2px,color:#fff
    style CP fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style TS fill:#059669,stroke:#10b981,stroke-width:2px,color:#fff
    style CM fill:#059669,stroke:#10b981,stroke-width:2px,color:#fff
    style OCI fill:transparent,stroke:#3b82f6,stroke-width:2px,color:#fff
    style Proxmox fill:transparent,stroke:#7c3aed,stroke-width:2px,color:#fff
    style Talos fill:transparent,stroke:#0891b2,stroke-width:2px,color:#fff
    style Apps fill:transparent,stroke:#059669,stroke-width:2px,color:#fff
```

### Bootstrap Sequence

Talos K8s bootstrap timeline showing VM creation, CNI deployment, Flux installation, and GitOps reconciliation.

**Related files:** [`tofu/talos/`](../tofu/talos/), [oci-free-tier-flux repo](https://github.com/syscode-labs/oci-free-tier-flux)

```mermaid
%%{init: {'theme':'base', 'themeVariables': { 'primaryColor':'#0891b2','primaryTextColor':'#fff','primaryBorderColor':'#06b6d4','lineColor':'#3b82f6','textColor':'#fff'}}}%%
flowchart TB
    subgraph Phase1["Phase 1: Provision"]
        TF["Terraform"]
        PVE["Proxmox"]
        CreateVMs["Create 3 VMs"]
        BootTalos["Boot Talos"]
    end
    
    subgraph Phase2["Phase 2: Bootstrap"]
        Talos["Talos"]
        FetchCilium["Fetch Cilium"]
        DepCNI["Deploy CNI"]
        FetchFlux["Fetch Flux"]
        DepGitOps["Deploy GitOps"]
    end
    
    subgraph Phase3["Phase 3: Configure"]
        TF2["Terraform"]
        InjectSOPS["Inject SOPS Key"]
    end
    
    subgraph Phase4["Phase 4: Reconcile"]
        Poll["Poll for changes"]
        Decrypt["Decrypt with SOPS"]
        Apply["Apply manifests"]
    end
    
    TF --> CreateVMs --> PVE --> BootTalos --> Talos
    Talos --> FetchCilium --> DepCNI
    Talos --> FetchFlux --> DepGitOps
    DepGitOps --> TF2 --> InjectSOPS
    InjectSOPS --> Poll --> Decrypt --> Apply
    Apply -.loop.-> Poll
    
    style TF fill:#d97706,stroke:#f59e0b,stroke-width:2px,color:#fff
    style PVE fill:#d97706,stroke:#f59e0b,stroke-width:2px,color:#fff
    style CreateVMs fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style BootTalos fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style Talos fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style FetchCilium fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style DepCNI fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style FetchFlux fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style DepGitOps fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style TF2 fill:#d97706,stroke:#f59e0b,stroke-width:2px,color:#fff
    style InjectSOPS fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style Poll fill:#059669,stroke:#10b981,stroke-width:2px,color:#fff
    style Decrypt fill:#059669,stroke:#10b981,stroke-width:2px,color:#fff
    style Apply fill:#059669,stroke:#10b981,stroke-width:2px,color:#fff
    style Phase1 fill:transparent,stroke:#d97706,stroke-width:2px,color:#fff
    style Phase2 fill:transparent,stroke:#0891b2,stroke-width:2px,color:#fff
    style Phase3 fill:transparent,stroke:#d97706,stroke-width:2px,color:#fff
    style Phase4 fill:transparent,stroke:#059669,stroke-width:2px,color:#fff
```

## Terraform Layers

### Three-Layer Architecture

Three independent Terraform layers with clear intervention points and state dependencies.

**Related files:** [`tofu/oci/`](../tofu/oci/), [`tofu/proxmox-cluster/`](../tofu/proxmox-cluster/), [`tofu/talos/`](../tofu/talos/)

```mermaid
%%{init: {'theme':'base', 'themeVariables': { 'primaryColor':'#0891b2','primaryTextColor':'#fff','primaryBorderColor':'#06b6d4','lineColor':'#3b82f6','textColor':'#fff'}}}%%
flowchart TB
    L1["Layer 1: OCI<br/>VCN + Compute"]
    L1Out["outputs: IPs"]
    L2["Layer 2: Proxmox<br/>Cluster + Ceph"]
    L2Out["outputs: API"]
    L3["Layer 3: Talos<br/>VMs + K8s"]
    L3Out["outputs: kubeconfig"]
    
    L1 --> L1Out
    L1Out -.remote state.-> L2
    L2 --> L2Out
    L2Out -.remote state.-> L3
    L3 --> L3Out
    
    style L1 fill:#2563eb,stroke:#3b82f6,stroke-width:3px,color:#fff
    style L1Out fill:#2563eb,stroke:#3b82f6,stroke-width:2px,color:#fff
    style L2 fill:#7c3aed,stroke:#a855f7,stroke-width:3px,color:#fff
    style L2Out fill:#7c3aed,stroke:#a855f7,stroke-width:2px,color:#fff
    style L3 fill:#0891b2,stroke:#06b6d4,stroke-width:3px,color:#fff
    style L3Out fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
```

## Network Architecture

### Physical + Logical Topology

Complete network architecture showing OCI VCN, Tailscale mesh, and Kubernetes networks.

**Related files:** [`tofu/oci/main.tf`](../tofu/oci/main.tf), [`WARP.md`](../WARP.md#networking)

```mermaid
%%{init: {'theme':'base', 'themeVariables': { 'primaryColor':'#0891b2','primaryTextColor':'#fff','primaryBorderColor':'#06b6d4','lineColor':'#3b82f6','textColor':'#fff'}}}%%
graph TB
    Internet["Internet"]
    IGW["Internet Gateway"]
    Subnet["Subnet<br/>10.0.1.0/24"]
    A1["Ampere 1<br/>10.0.1.10"]
    A2["Ampere 2<br/>10.0.1.11"]
    A3["Ampere 3<br/>10.0.1.12"]
    Bastion["Bastion<br/>10.0.1.20"]
    TSMesh["Tailscale Mesh<br/>100.x.x.x"]
    K8sPods["K8s Pods<br/>10.244.0.0/16"]
    K8sSvc["K8s Services<br/>10.96.0.0/12"]
    
    Internet --> IGW --> Subnet
    Subnet --> A1 & A2 & A3 & Bastion
    A1 & A2 & A3 & Bastion --> TSMesh
    A1 & A2 & A3 --> K8sPods
    K8sPods --> K8sSvc
    
    style Internet fill:#94a3b8,stroke:#cbd5e1,stroke-width:2px,color:#fff
    style IGW fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style Subnet fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style A1 fill:#2563eb,stroke:#3b82f6,stroke-width:2px,color:#fff
    style A2 fill:#2563eb,stroke:#3b82f6,stroke-width:2px,color:#fff
    style A3 fill:#2563eb,stroke:#3b82f6,stroke-width:2px,color:#fff
    style Bastion fill:#7c3aed,stroke:#a855f7,stroke-width:2px,color:#fff
    style TSMesh fill:#d97706,stroke:#f59e0b,stroke-width:2px,color:#fff
    style K8sPods fill:#059669,stroke:#10b981,stroke-width:2px,color:#fff
    style K8sSvc fill:#059669,stroke:#10b981,stroke-width:2px,color:#fff
```

## Cost Enforcement

### Free Tier Validation Flow

Multi-stage validation ensuring all resources stay within free tier limits.

**Related files:** [`tofu/oci/variables.tf`](../tofu/oci/variables.tf), [`scripts/validate-cost.sh`](../scripts/validate-cost.sh)

```mermaid
%%{init: {'theme':'base', 'themeVariables': { 'primaryColor':'#0891b2','primaryTextColor':'#fff','primaryBorderColor':'#06b6d4','lineColor':'#3b82f6','textColor':'#fff'}}}%%
flowchart TB
    Limits["Free Tier Limits<br/>4 OCPU, 24GB, 200GB"]
    TFVal["Terraform Validations<br/>variables.tf"]
    PreCheck["Pre-Deploy Checks<br/>tofu plan"]
    Runtime["Runtime Monitor<br/>Budget Alert $0.01"]
    PostDeploy["Post-Deploy<br/>task validate:cost"]
    Pass["✅ $0.00"]
    Fail["❌ STOP"]
    
    Limits --> TFVal
    TFVal --> PreCheck
    PreCheck --> Runtime
    Runtime --> PostDeploy
    PostDeploy -->|Yes| Pass
    PostDeploy -->|No| Fail
    
    style Limits fill:#94a3b8,stroke:#cbd5e1,stroke-width:2px,color:#fff
    style TFVal fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style PreCheck fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style Runtime fill:#d97706,stroke:#f59e0b,stroke-width:3px,color:#fff
    style PostDeploy fill:#0891b2,stroke:#06b6d4,stroke-width:2px,color:#fff
    style Pass fill:#059669,stroke:#10b981,stroke-width:3px,color:#fff
    style Fail fill:#dc2626,stroke:#ef4444,stroke-width:3px,color:#fff
```
