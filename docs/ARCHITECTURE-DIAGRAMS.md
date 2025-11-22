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
