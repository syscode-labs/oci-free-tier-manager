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
   - [Bootstrap Sequence (Detailed)](#bootstrap-sequence-detailed)

### 3. [Terraform Layers](#terraform-layers)
   - [Three-Layer Architecture](#three-layer-architecture)
   - [Layer 1: OCI Resources (Detailed)](#layer-1-oci-resources-detailed)
   - [Layer 2: Proxmox Setup (Detailed)](#layer-2-proxmox-setup-detailed)
   - [Layer 3: Talos Deployment (Detailed)](#layer-3-talos-deployment-detailed)

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

### Bootstrap Sequence (Detailed)

Detailed sequence diagram showing exact interactions between components during Talos K8s bootstrap.

**Related files:** [`tofu/talos/`](../tofu/talos/), [oci-free-tier-flux repo](https://github.com/syscode-labs/oci-free-tier-flux)

```mermaid
%%{init: {'theme':'base', 'themeVariables': {
  'actorBkg':'#0891b2',
  'actorBorder':'#06b6d4',
  'actorTextColor':'#fff',
  'actorLineColor':'#3b82f6',
  'signalColor':'#3b82f6',
  'signalTextColor':'#fff',
  'labelBoxBkgColor':'#d97706',
  'labelBoxBorderColor':'#f59e0b',
  'labelTextColor':'#fff',
  'loopTextColor':'#fff',
  'noteBkgColor':'#d97706',
  'noteTextColor':'#fff',
  'noteBorderColor':'#f59e0b',
  'activationBkgColor':'#2563eb',
  'activationBorderColor':'#3b82f6'
}}}%%
sequenceDiagram
    participant TF as Terraform
    participant PVE as Proxmox
    participant T as Talos
    participant GH as GitHub
    participant K8s as Kubernetes
    
    Note over TF,K8s: Phase 1: Provision
    TF->>PVE: Create 3 VMs
    PVE-->>T: Boot Talos
    
    Note over T,GH: Phase 2: Bootstrap
    T->>GH: Fetch Cilium
    GH-->>T: cilium.yaml
    T->>K8s: Deploy CNI
    
    T->>GH: Fetch Flux
    GH-->>T: install.yaml
    T->>K8s: Deploy GitOps
    
    Note over TF,K8s: Phase 3: Configure
    TF->>K8s: Inject SOPS Key
    
    Note over K8s,GH: Phase 4: Reconcile
    loop Every 1 minute
        K8s->>GH: Poll for changes
        GH-->>K8s: Encrypted manifests
        K8s->>K8s: Decrypt with SOPS
        K8s->>K8s: Apply manifests
    end
```

## Terraform Layers

### Layer 1: OCI Resources (Detailed)

Detailed workflow of OCI infrastructure provisioning.

**Related files:** [`tofu/oci/main.tf`](../tofu/oci/main.tf)

```mermaid
%%{init: {'theme':'base', 'themeVariables': {
  'actorBkg':'#2563eb',
  'actorBorder':'#3b82f6',
  'actorTextColor':'#fff',
  'signalColor':'#3b82f6',
  'signalTextColor':'#fff',
  'labelBoxBkgColor':'#2563eb',
  'labelBoxBorderColor':'#3b82f6',
  'labelTextColor':'#fff',
  'noteBkgColor':'#2563eb',
  'noteTextColor':'#fff',
  'noteBorderColor':'#3b82f6'
}}}%%
sequenceDiagram
    participant Dev as Developer
    participant TF as Terraform
    participant OCI as Oracle Cloud
    
    Note over Dev,OCI: Planning Phase
    Dev->>TF: tofu plan
    TF->>TF: Validate variables
    TF->>OCI: Query existing resources
    OCI-->>TF: Current state
    TF-->>Dev: Show planned changes
    
    Note over Dev,OCI: Apply Phase
    Dev->>TF: tofu apply
    TF->>OCI: Create VCN
    TF->>OCI: Create subnet
    TF->>OCI: Create 3x Ampere instances
    TF->>OCI: Create 1x Micro bastion
    TF->>OCI: Attach reserved IPs
    OCI-->>TF: Instance IPs
    TF-->>Dev: Outputs (IPs, IDs)
```

### Layer 2: Proxmox Setup (Detailed)

Detailed sequence of Proxmox cluster formation and Ceph configuration.

**Related files:** [`tofu/proxmox-cluster/main.tf`](../tofu/proxmox-cluster/main.tf)

```mermaid
%%{init: {'theme':'base', 'themeVariables': {
  'actorBkg':'#7c3aed',
  'actorBorder':'#a855f7',
  'actorTextColor':'#fff',
  'signalColor':'#3b82f6',
  'signalTextColor':'#fff',
  'labelBoxBkgColor':'#7c3aed',
  'labelBoxBorderColor':'#a855f7',
  'labelTextColor':'#fff',
  'noteBkgColor':'#7c3aed',
  'noteTextColor':'#fff',
  'noteBorderColor':'#a855f7'
}}}%%
sequenceDiagram
    participant TF as Terraform
    participant N1 as Node 1
    participant N2 as Node 2
    participant N3 as Node 3
    
    Note over TF,N3: Read OCI State
    TF->>TF: Fetch instance IPs
    
    Note over TF,N3: Install Proxmox
    TF->>N1: SSH + Ansible
    TF->>N2: SSH + Ansible
    TF->>N3: SSH + Ansible
    N1-->>TF: Proxmox installed
    N2-->>TF: Proxmox installed
    N3-->>TF: Proxmox installed
    
    Note over TF,N3: Form Cluster
    TF->>N1: pvecm create cluster
    TF->>N2: pvecm add node1
    TF->>N3: pvecm add node1
    N1-->>TF: Quorum established
    
    Note over TF,N3: Configure Ceph
    TF->>N1: ceph-mon init
    TF->>N2: ceph-mon init
    TF->>N3: ceph-mon init
    TF->>N1: Create OSD
    TF->>N2: Create OSD
    TF->>N3: Create OSD
    N1-->>TF: Ceph healthy
```

### Layer 3: Talos Deployment (Detailed)

Detailed Talos VM creation and K8s bootstrap workflow.

**Related files:** [`tofu/talos/talos-vms.tf`](../tofu/talos/talos-vms.tf)

```mermaid
%%{init: {'theme':'base', 'themeVariables': {
  'actorBkg':'#0891b2',
  'actorBorder':'#06b6d4',
  'actorTextColor':'#fff',
  'signalColor':'#3b82f6',
  'signalTextColor':'#fff',
  'labelBoxBkgColor':'#0891b2',
  'labelBoxBorderColor':'#06b6d4',
  'labelTextColor':'#fff',
  'noteBkgColor':'#0891b2',
  'noteTextColor':'#fff',
  'noteBorderColor':'#06b6d4'
}}}%%
sequenceDiagram
    participant TF as Terraform
    participant PVE as Proxmox API
    participant Factory as factory.talos.dev
    participant VM as Talos VMs
    participant K8s as Kubernetes
    
    Note over TF,K8s: Download Image
    TF->>Factory: Download nocloud image
    Factory-->>TF: talos-amd64.raw.xz
    
    Note over TF,K8s: Create VMs
    TF->>TF: Render machine config
    TF->>PVE: Create VM 1 (control plane)
    TF->>PVE: Create VM 2 (control plane)
    TF->>PVE: Create VM 3 (control plane)
    TF->>PVE: Inject cloud-init configs
    PVE-->>VM: Boot VMs
    
    Note over TF,K8s: Bootstrap K8s
    VM->>VM: Fetch Cilium manifest
    VM->>VM: Deploy CNI
    VM->>VM: Fetch Flux manifest
    VM->>VM: Deploy GitOps
    VM-->>K8s: Cluster ready
    
    Note over TF,K8s: Inject Secrets
    TF->>K8s: Create SOPS Age secret
    K8s-->>TF: Secret stored
    TF-->>TF: Output kubeconfig
```
