# Architecture Diagrams

Visual representations of the OCI Free Tier infrastructure using clean, readable Mermaid diagrams.

## Table of Contents

1. [Deployment Pipeline](#deployment-pipeline)
2. [Talos Kubernetes](#talos-kubernetes)  
3. [Terraform Layers](#terraform-layers)
4. [Network Architecture](#network-architecture)
5. [Cost Enforcement](#cost-enforcement)

---

## Deployment Pipeline

### Complete Flow

End-to-end deployment in 6 phases.

```mermaid
%%{init: {'theme':'forest'}}%%
flowchart LR
    Setup["⚙️ Setup<br/><small>OCI CLI + Flux</small>"] --> Build["🔨 Build<br/><small>Images</small>"]
    Build --> OCI["☁️ OCI<br/><small>Infrastructure</small>"]
    OCI --> Proxmox["🗄️ Proxmox<br/><small>Cluster</small>"]
    Proxmox --> Talos["🐧 Talos<br/><small>K8s</small>"]
    Talos --> Apps["📦 Apps<br/><small>GitOps</small>"]
    
    classDef phaseNode fill:#2d5016,stroke:#5a9216,stroke-width:3px,color:#fff,font-size:14px
    class Setup,Build,OCI,Proxmox,Talos,Apps phaseNode
```

### Phase 0: Setup

```mermaid
%%{init: {'theme':'forest'}}%%
flowchart LR
    Start(["task setup"]) --> CheckOCI{"OCI<br/>CLI?"}
    CheckOCI -->|Missing| InstallOCI["oci setup<br/>config"]
    CheckOCI -->|Exists| GenTF["Generate<br/>tfvars"]
    InstallOCI --> GenTF
    GenTF --> SSH["SSH Keys"]
    
    StartFlux(["task<br/>setup:flux"]) --> Cilium["Cilium<br/>Manifest"]
    Cilium --> Age["Age Key<br/>+ SOPS"]
    Age --> Encrypt["Encrypt<br/>Secrets"]
    
    SSH --> Done[("✓")]
    Encrypt --> Done
    
    classDef success fill:#2d5016,stroke:#5a9216,stroke-width:3px,color:#fff
    class Done success
```

### Phase 1: Build Images

```mermaid
%%{init: {'theme':'forest'}}%%
flowchart LR
    Start(["task<br/>build:images"]) --> Base["Base Image<br/><small>Debian 12</small>"]
    Start --> Proxmox["Proxmox Image<br/><small>+PVE +Ceph</small>"]
    
    Base --> Check{"< 20GB<br/>total?"}
    Proxmox --> Check
    
    Check -->|Yes| Upload["Upload to<br/>OCI Storage"]
    Check -->|No| Fail[("❌")]
    
    Upload --> Images["Custom<br/>Images"]
    Images --> Done[("✓")]
    
    classDef success fill:#2d5016,stroke:#5a9216,stroke-width:3px,color:#fff
    classDef error fill:#8b0000,stroke:#ff0000,stroke-width:3px,color:#fff
    class Done success
    class Fail error
```

### Phase 2: OCI Infrastructure

```mermaid
%%{init: {'theme':'forest'}}%%
flowchart LR
    Start(["task<br/>deploy:oci"]) --> Plan["tofu plan"]
    Plan --> Apply["tofu apply"]
    
    Apply --> VCN["VCN<br/><small>10.0.0.0/16</small>"]
    VCN --> Ampere["3× Ampere<br/><small>ARM64</small>"]
    VCN --> Bastion["1× Micro<br/><small>x86</small>"]
    
    Ampere --> Mesh["Tailscale<br/>Mesh"]
    Bastion --> Mesh
    Mesh --> Done[("✓")]
    
    classDef success fill:#2d5016,stroke:#5a9216,stroke-width:3px,color:#fff
    class Done success
```

### Phase 3: Proxmox Cluster

```mermaid
%%{init: {'theme':'forest'}}%%
flowchart LR
    Start(["task<br/>deploy:proxmox"]) --> Node1["pvecm create"]
    Node1 --> Nodes["pvecm add<br/><small>nodes 2-3</small>"]
    
    Nodes --> Quorum{"Quorum?"}
    Quorum -->|No| FailQ[("❌")]
    Quorum -->|Yes| Ceph["pveceph init"]
    
    Ceph --> OSD["Create OSDs"]
    OSD --> Health{"HEALTH_OK?"}
    Health -->|No| FailC[("❌")]
    Health -->|Yes| Done[("✓")]
    
    classDef success fill:#2d5016,stroke:#5a9216,stroke-width:3px,color:#fff
    classDef error fill:#8b0000,stroke:#ff0000,stroke-width:3px,color:#fff
    class Done success
    class FailQ,FailC error
```

### Phase 4: Talos Kubernetes

```mermaid
%%{init: {'theme':'forest'}}%%
flowchart LR
    Start(["task<br/>deploy:talos"]) --> Image["Download<br/>Talos"]
    Image --> VMs["Create 3×<br/>VMs"]
    VMs --> Boot["Boot"]
    
    Boot --> Cilium["Deploy<br/>Cilium CNI"]
    Cilium --> Flux["Deploy<br/>Flux"]
    Flux --> SOPS["Inject<br/>SOPS Keys"]
    
    SOPS --> Reconcile["Flux<br/>Reconciles"]
    Reconcile --> Apps["Deploy<br/>Apps"]
    Apps --> Done[("✓")]
    
    classDef success fill:#2d5016,stroke:#5a9216,stroke-width:3px,color:#fff
    class Done success
```

### Phase 5: Validation

```mermaid
%%{init: {'theme':'forest'}}%%
flowchart TB
    Start(["task validate"]) --> Images["Images"]
    Start --> OCI["OCI"]
    Start --> Proxmox["Proxmox"]
    Start --> Talos["Talos"]
    Start --> Cost["Cost"]
    
    Images --> Check{"All<br/>Pass?"}
    OCI --> Check
    Proxmox --> Check
    Talos --> Check
    Cost --> Check
    
    Check -->|Yes| Success[("✅ Complete")]
    Check -->|No| Fail[("❌ Fix Issues")]
    
    classDef success fill:#2d5016,stroke:#5a9216,stroke-width:3px,color:#fff
    classDef error fill:#8b0000,stroke:#ff0000,stroke-width:3px,color:#fff
    class Success success
    class Fail error
```

---

## Talos Kubernetes

### Architecture Overview

```mermaid
%%{init: {'theme':'forest'}}%%
graph TB
    subgraph OCI["☁️ OCI Infrastructure"]
        Ampere["3× Ampere A1<br/>ARM64, 1.33 OCPU, 8GB"]
        Bastion["1× Micro<br/>x86, 1GB RAM"]
    end
    
    subgraph PVE["🗄️ Proxmox Cluster"]
        Node1["Node 1"]
        Node2["Node 2"]
        Node3["Node 3"]
        Ceph["Ceph Storage<br/>150GB"]
    end
    
    subgraph K8s["🐧 Talos K8s"]
        CP1["Control Plane 1"]
        CP2["Control Plane 2"]
        CP3["Control Plane 3"]
    end
    
    subgraph Apps["📦 Applications"]
        Tailscale["Tailscale"]
        Cert["cert-manager"]
        Alloy["Grafana Alloy"]
    end
    
    Ampere -.-> Node1 & Node2 & Node3
    Node1 & Node2 & Node3 -.-> Ceph
    Node1 --> CP1
    Node2 --> CP2
    Node3 --> CP3
    CP1 & CP2 & CP3 --> Tailscale & Cert & Alloy
    
    Bastion -.SSH.-> Node1 & Node2 & Node3
```

### Bootstrap Sequence

```mermaid
%%{init: {'theme':'forest'}}%%
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

---

## Terraform Layers

### Three-Layer Architecture

```mermaid
%%{init: {'theme':'forest'}}%%
graph LR
    subgraph L1["Layer 1: OCI"]
        OCI_Main["main.tf<br/><small>VCN + Compute</small>"]
        OCI_Out["outputs.tf<br/><small>IPs</small>"]
    end
    
    subgraph L2["Layer 2: Proxmox"]
        PVE_Main["main.tf<br/><small>Cluster + Ceph</small>"]
        PVE_Out["outputs.tf<br/><small>API</small>"]
    end
    
    subgraph L3["Layer 3: Talos"]
        K8s_Main["talos-vms.tf<br/><small>VMs + K8s</small>"]
        K8s_Secret["flux-secrets.tf<br/><small>SOPS</small>"]
        K8s_Out["outputs.tf<br/><small>kubeconfig</small>"]
    end
    
    OCI_Out -->|remote state| PVE_Main
    PVE_Out -->|remote state| K8s_Main
    
    classDef layer1 fill:#2d5016,stroke:#5a9216,stroke-width:2px,color:#fff
    classDef layer2 fill:#3a2d16,stroke:#9b7216,stroke-width:2px,color:#fff
    classDef layer3 fill:#162d29,stroke:#16929b,stroke-width:2px,color:#fff
    class OCI_Main,OCI_Out layer1
    class PVE_Main,PVE_Out layer2
    class K8s_Main,K8s_Secret,K8s_Out layer3
```

### Layer 1: OCI Resources

```mermaid
%%{init: {'theme':'forest'}}%%
graph TB
    VCN["VCN<br/>10.0.0.0/16"] --> IGW["Internet<br/>Gateway"]
    IGW --> RT["Route<br/>Table"]
    RT --> SL["Security<br/>List"]
    SL --> Subnet["Subnet<br/>10.0.1.0/24"]
    
    Subnet --> Ampere["3× Ampere A1"]
    Subnet --> Micro["1× Micro"]
    
    Ampere --> Storage["Boot Volumes<br/>150GB"]
    Micro --> Storage
    
    Budget["Budget Alert<br/>$0.01"] -.monitors.-> Ampere & Micro
```

### Layer 2: Proxmox Setup

```mermaid
%%{init: {'theme':'forest'}}%%
graph LR
    Inputs["OCI IPs<br/><small>remote state</small>"] --> SSH["SSH<br/>Provisioner"]
    SSH --> Cluster["Form Cluster<br/><small>pvecm</small>"]
    Cluster --> Ceph["Configure Ceph<br/><small>pveceph</small>"]
    Ceph --> LXC["Deploy<br/>Tailscale LXC"]
    LXC --> Test["Test<br/>Migration"]
    Test --> Outputs["API URL<br/>Ceph Health"]
```

### Layer 3: Talos Deployment

```mermaid
%%{init: {'theme':'forest'}}%%
graph LR
    Inputs["Proxmox API<br/><small>remote state</small>"] --> Image["Download<br/>Talos Image"]
    Image --> CloudInit["Render<br/>cloud-init"]
    CloudInit --> VMs["Create<br/>3 VMs"]
    VMs --> Bootstrap["Auto<br/>Bootstrap"]
    Bootstrap --> Secret["Inject<br/>SOPS Key"]
    Secret --> Outputs["kubeconfig<br/>endpoints"]
```

---

## Network Architecture

### Physical + Logical Topology

```mermaid
%%{init: {'theme':'forest'}}%%
graph TB
    Internet["🌐 Internet"]
    
    subgraph OCI_Net["OCI VCN: 10.0.0.0/16"]
        IGW["Internet<br/>Gateway"]
        Subnet["Subnet<br/>10.0.1.0/24"]
    end
    
    subgraph Instances["Compute Instances"]
        A1["Ampere 1<br/>10.0.1.10"]
        A2["Ampere 2<br/>10.0.1.11"]
        A3["Ampere 3<br/>10.0.1.12"]
        BAS["Bastion<br/>10.0.1.20<br/>Reserved IP"]
    end
    
    subgraph Mesh["Tailscale Mesh: 100.x.x.x"]
        TS1["100.64.0.1"]
        TS2["100.64.0.2"]
        TS3["100.64.0.3"]
        TS4["100.64.0.4"]
    end
    
    subgraph K8s_Net["K8s Network"]
        Pods["Pods<br/>10.244.0.0/16"]
        Svcs["Services<br/>10.96.0.0/12"]
        Ingress["Ingress<br/>Reserved IP #2"]
    end
    
    Internet --> IGW
    IGW --> Subnet
    Subnet --> A1 & A2 & A3 & BAS
    
    A1 -.-> TS1
    A2 -.-> TS2
    A3 -.-> TS3
    BAS -.-> TS4
    
    TS1 -.mesh.-> TS2 & TS3 & TS4
    
    A1 & A2 & A3 --> Pods
    Pods --> Svcs
    Svcs --> Ingress
    Ingress -.-> Internet
```

### IP Allocation Strategy

```mermaid
%%{init: {'theme':'forest'}}%%
graph TB
    subgraph Free["Free Tier: 2 Reserved IPs"]
        R1["Reserved IP #1<br/>→ Bastion<br/><small>Static SSH access</small>"]
        R2["Reserved IP #2<br/>→ Ingress<br/><small>K8s services</small>"]
    end
    
    subgraph Ephemeral["Ephemeral IPs"]
        E1["Ampere 1<br/>Setup + Mgmt"]
        E2["Ampere 2<br/>Setup + Mgmt"]
        E3["Ampere 3<br/>Setup + Mgmt"]
    end
    
    subgraph Internal["Internal: Tailscale"]
        T["Unlimited services<br/>100.x.x.x range<br/><small>No public IPs needed</small>"]
    end
    
    R1 --> SSH["SSH Entry Point"]
    R2 --> NAT["1:1 NAT<br/>→ NodePort"]
    E1 & E2 & E3 --> Mesh["Tailscale Mesh"]
    T --> Private["Private Services"]
```

---

## Cost Enforcement

### Free Tier Validation Flow

```mermaid
%%{init: {'theme':'forest'}}%%
graph TB
    subgraph Limits["Free Tier Limits"]
        C["Compute<br/>4 OCPU, 24GB"]
        S["Storage<br/>200GB"]
        N["Network<br/>2 Reserved IPs"]
        O["Objects<br/>20GB"]
    end
    
    subgraph TF_Val["Terraform Validations"]
        V1["variables.tf<br/>count ≤ 4"]
        V2["variables.tf<br/>ocpus ≤ 4"]
        V3["variables.tf<br/>ram ≤ 24GB"]
        V4["variables.tf<br/>storage ≤ 200GB"]
    end
    
    subgraph Checks["Pre-Deploy Checks"]
        Plan["tofu plan<br/>review"]
        Build["task build:validate<br/>< 20GB"]
    end
    
    subgraph Monitor["Runtime Monitor"]
        Budget["Budget Alert<br/>$0.01"]
        Email["Email on<br/>any charge"]
    end
    
    subgraph Validate["Post-Deploy"]
        Cost["task validate:cost"]
        Billing["OCI billing:<br/>$0.00"]
        Grafana["Grafana Cloud:<br/>within free tier"]
    end
    
    C & S & N & O --> V1 & V2 & V3 & V4
    V1 & V2 & V3 & V4 --> Plan & Build
    Plan & Build --> Budget
    Budget --> Email
    Email --> Cost
    Cost --> Billing & Grafana
    
    Billing --> Result{"$0.00?"}
    Grafana --> Result
    Result -->|Yes| Safe[("✅ Safe")]
    Result -->|No| Stop[("❌ STOP")]
    
    classDef success fill:#2d5016,stroke:#5a9216,stroke-width:3px,color:#fff
    classDef error fill:#8b0000,stroke:#ff0000,stroke-width:3px,color:#fff
    class Safe success
    class Stop error
```

### Validation Matrix

```mermaid
%%{init: {'theme':'forest'}}%%
graph LR
    V["task validate"] --> I["Images<br/><20GB"]
    V --> O["OCI<br/>free tier"]
    V --> P["Proxmox<br/>quorum"]
    V --> T["Talos<br/>ready"]
    V --> C["Cost<br/>$0.00"]
    
    I --> R{"All<br/>✓?"}
    O --> R
    P --> R
    T --> R
    C --> R
    
    R -->|Yes| Success[("✅")]
    R -->|No| Fail[("❌")]
    
    classDef success fill:#2d5016,stroke:#5a9216,stroke-width:3px,color:#fff
    classDef error fill:#8b0000,stroke:#ff0000,stroke-width:3px,color:#fff
    class Success success
    class Fail error
```

---

## Deployment Timeline

```mermaid
%%{init: {'theme':'forest'}}%%
gantt
    title Deployment Timeline (End-to-End)
    dateFormat HH:mm
    axisFormat %H:%M
    
    section Setup
    OCI CLI + SSH        :done, 00:00, 10m
    Flux + SOPS         :done, 00:10, 10m
    
    section Build
    Dagger Pipeline     :active, 00:20, 5m
    Base Image          :00:25, 25m
    Proxmox Image       :00:50, 30m
    Upload to OCI       :01:20, 15m
    
    section Deploy
    OCI Infrastructure  :01:35, 15m
    Proxmox Cluster     :01:50, 30m
    Talos K8s           :02:20, 20m
    Flux Reconcile      :02:40, 10m
    
    section Validate
    All Checks          :02:50, 10m
```

**Total time:** ~3 hours (with image builds) | ~1 hour (pre-built images)

---

## Legend

### Visual Elements

- **🌐 Internet** - Public internet
- **☁️ OCI** - Oracle Cloud Infrastructure
- **🗄️ Proxmox** - Proxmox VE hypervisor
- **🐧 Talos** - Talos Linux (immutable K8s OS)
- **📦 Applications** - Deployed workloads
- **✓** - Success state
- **❌** - Error/failure state

### Colors

- **Green (#2d5016)** - Success, ready state
- **Red (#8b0000)** - Error, failure state
- **Forest theme** - Professional, readable palette

### Abbreviations

- **OCI** - Oracle Cloud Infrastructure
- **VCN** - Virtual Cloud Network
- **IGW** - Internet Gateway
- **CNI** - Container Network Interface (Cilium)
- **PVE** - Proxmox Virtual Environment
- **LXC** - Linux Container
- **SOPS** - Secrets OPerationS (encryption)
- **CCM** - Cloud Controller Manager

---

## Related Documentation

- [PLAN.md](../PLAN.md) - Detailed deployment steps
- [QUICKSTART.md](./QUICKSTART.md) - Quick start guide
- [WARP.md](../WARP.md) - Complete architecture reference
- [Taskfile.yml](../Taskfile.yml) - All automation commands
