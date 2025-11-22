# Architecture Diagrams

Visual representations of the OCI Free Tier infrastructure architecture, automation workflows, and deployment processes.

## Table of Contents

1. [Automation Flow](#automation-flow)
   - [Simplified Overview](#simplified-automation-flow)
   - [Detailed Flow](#detailed-automation-flow)
2. [Talos Kubernetes Architecture](#talos-kubernetes-architecture)
   - [Simplified View](#simplified-talos-architecture)
   - [Detailed Deployment](#detailed-talos-deployment)
3. [Terraform Components](#terraform-components)
   - [Simplified Layer View](#simplified-terraform-layers)
   - [Detailed Component View](#detailed-terraform-components)

---

## Automation Flow

### Simplified Automation Flow

High-level overview of the deployment pipeline from setup to production.

```mermaid
%%{init: {'theme':'forest'}}%%
flowchart LR
    Setup["⚙️ Setup<br/><small>OCI CLI + SSH + Flux</small>"] --> Build["🔨 Build Images<br/><small>Dagger Pipeline</small>"]
    Build --> OCI["☁️ OCI Infrastructure<br/><small>3 Ampere + 1 Bastion</small>"]
    OCI --> Proxmox["🗄️ Proxmox Cluster<br/><small>+ Ceph Storage</small>"]
    Proxmox --> Talos["🐧 Talos K8s<br/><small>+ Cilium + Flux</small>"]
    Talos --> Apps["📦 Applications<br/><small>GitOps Deployed</small>"]
    
    classDef phaseNode fill:#2d5016,stroke:#5a9216,stroke-width:3px,color:#fff
    class Setup,Build,OCI,Proxmox,Talos,Apps phaseNode
```

### Detailed Automation Flow

Each phase broken down into key steps. Click through phases to see the full workflow.

#### Phase 0: Setup

```mermaid
%%{init: {'theme':'forest'}}%%
flowchart LR
    A["task setup"] --> B{"OCI CLI?"}
    B -->|Missing| C["oci setup config"]
    B -->|Exists| D["Generate<br/>terraform.tfvars"]
    C --> D
    D --> E["SSH Keys<br/>~/.ssh/oci_key"]
    
    F["task setup:flux"] --> G["Generate<br/>Cilium Manifest"]
    G --> H["Age Key<br/>SOPS Config"]
    H --> I["Encrypt<br/>Tailscale Secret"]
    I --> J["✓ Ready"]
    
    E --> J
    
    classDef success fill:#2d5016,stroke:#5a9216,stroke-width:2px,color:#fff
    class J success
```

#### Phase 1: Image Building

```mermaid
%%{init: {'theme':'forest'}}%%
flowchart LR
    A["task build:images"] --> B["Dagger:<br/>Base Image"]
    B --> C["base-hardened.qcow2<br/><8GB"]
    
    A --> D["Dagger:<br/>Proxmox Image"]
    D --> E["proxmox-ampere.qcow2<br/><10GB"]
    
    C --> F{"Total<br/><20GB?"}
    E --> F
    F -->|Yes| G["Upload to<br/>OCI Storage"]
    F -->|No| H["❌ Too Large"]
    
    G --> I["Create<br/>Custom Images"]
    I --> J["✓ OCIDs Ready"]
    
    classDef success fill:#2d5016,stroke:#5a9216,stroke-width:2px,color:#fff
    classDef error fill:#8b0000,stroke:#ff0000,stroke-width:2px,color:#fff
    class J success
    class H error
```

####Phase 2: OCI Infrastructure

```mermaid
%%{init: {'theme':'forest'}}%%
flowchart LR
    A["task deploy:oci"] --> B["tofu init<br/>tofu plan"]
    B --> C{"Plan OK?"}
    C -->|No| D["❌ Fix Config"]
    C -->|Yes| E["tofu apply"]
    
    E --> F["VCN + Networking<br/>10.0.0.0/16"]
    F --> G["3x Ampere A1<br/>1.33 OCPU, 8GB"]
    F --> H["1x Micro Bastion<br/>Reserved IP"]
    
    G --> I["Tailscale Mesh"]
    H --> I
    I --> J["✓ Infrastructure Ready"]
    
    classDef success fill:#2d5016,stroke:#5a9216,stroke-width:2px,color:#fff
    classDef error fill:#8b0000,stroke:#ff0000,stroke-width:2px,color:#fff
    class J success
    class D error
```

#### Phase 3: Proxmox Cluster

```mermaid
%%{init: {'theme':'forest'}}%%
flowchart LR
    A["task deploy:proxmox"] --> B["SSH to<br/>Node 1"]
    B --> C["pvecm create"]
    C --> D["SSH to<br/>Nodes 2-3"]
    D --> E["pvecm add"]
    
    E --> F{"Quorum?"}
    F -->|No| G["❌ Check Network"]
    F -->|Yes| H["pveceph init"]
    
    H --> I["Create OSDs<br/>Ceph Pool"]
    I --> J{"Ceph<br/>HEALTH_OK?"}
    J -->|No| K["❌ Check Storage"]
    J -->|Yes| L["✓ Cluster Ready"]
    
    classDef success fill:#2d5016,stroke:#5a9216,stroke-width:2px,color:#fff
    classDef error fill:#8b0000,stroke:#ff0000,stroke-width:2px,color:#fff
    class L success
    class G,K error
```

#### Phase 4: Talos Kubernetes

```mermaid
%%{init: {'theme':'forest'}}%%
flowchart LR
    A["task deploy:talos"] --> B["Download<br/>Talos Image"]
    B --> C["Create 3x VMs<br/>on Proxmox"]
    C --> D["Talos Boots"]
    
    D --> E["Deploy Cilium<br/>CNI Active"]
    E --> F["Deploy Flux<br/>GitOps Active"]
    F --> G["Inject<br/>SOPS Keys"]
    
    G --> H["Flux<br/>Reconciles"]
    H --> I["Deploy<br/>Applications"]
    I --> J["✓ K8s Ready"]
    
    classDef success fill:#2d5016,stroke:#5a9216,stroke-width:2px,color:#fff
    class J success
```

#### Phase 5: Validation

```mermaid
%%{init: {'theme':'forest'}}%%
flowchart LR
    A["task validate"] --> B["Images<br/><20GB"]
    A --> C["OCI<br/>Free Tier"]
    A --> D["Proxmox<br/>Quorum + Ceph"]
    A --> E["Talos<br/>Nodes Ready"]
    A --> F["Cost<br/>$0.00"]
    
    B --> G{"All Pass?"}
    C --> G
    D --> G
    E --> G
    F --> G
    
    G -->|Yes| H["✓ Deployment Complete"]
    G -->|No| I["❌ Fix Issues"]
    
    classDef success fill:#2d5016,stroke:#5a9216,stroke-width:2px,color:#fff
    classDef error fill:#8b0000,stroke:#ff0000,stroke-width:2px,color:#fff
    class H success
    class I error
    
    subgraph "Image Build Phase"
        C1[task build:images] --> C2[dagger call build-all-images]
        C2 --> C3[Dagger: Build Base Image]
        C3 --> C4[QEMU Builder<br/>Debian 12 Netinstall]
        C4 --> C5[Preseed Automated Install]
        C5 --> C6[Run Provisioners:<br/>install-tailscale.sh<br/>harden-base.sh]
        C6 --> C7[Output: base-hardened.qcow2]
        
        C2 --> C8[Dagger: Build Proxmox Image]
        C8 --> C9[QEMU Builder<br/>base-hardened.qcow2]
        C9 --> C10[Run Provisioners:<br/>install-proxmox.sh<br/>tteck-post-install.sh]
        C10 --> C11[Output: proxmox-ampere.qcow2]
        
        C7 --> C12[Validate: base < 10GB]
        C11 --> C13[Validate: proxmox < 10GB]
        C12 --> C14[Total < 20GB?]
        C13 --> C14
        C14 -->|Yes| C15[task build:upload]
        C14 -->|No| C16[ERROR: Images Too Large]
        
        C15 --> C17[oci os object put<br/>→ base-hardened.qcow2]
        C15 --> C18[oci os object put<br/>→ proxmox-ampere.qcow2]
        C17 --> C19[oci compute image create<br/>from Object Storage]
        C18 --> C19
        C19 --> C20[Custom Image OCIDs]
    end
    
    subgraph "OCI Deployment Phase"
        D1[task deploy:oci] --> D2[cd tofu/oci]
        D2 --> D3[tofu init -upgrade]
        D3 --> D4[tofu plan]
        D4 --> D5{Plan OK?}
        D5 -->|Yes| D6[tofu apply]
        D5 -->|No| D7[ERROR: Invalid Plan]
        
        D6 --> D8[Create VCN<br/>10.0.0.0/16]
        D8 --> D9[Create Internet Gateway]
        D9 --> D10[Create Route Table<br/>0.0.0.0/0 → IGW]
        D10 --> D11[Create Security List<br/>SSH/HTTP/HTTPS/ICMP]
        D11 --> D12[Create Subnet<br/>10.0.1.0/24]
        
        D12 --> D13[Create 3x Ampere A1<br/>1.33 OCPU, 8GB RAM, 50GB disk]
        D12 --> D14[Create 1x E2.1.Micro<br/>1GB RAM, 50GB disk]
        
        D13 --> D15[Assign Public IPs<br/>Ephemeral]
        D14 --> D16[Assign Reserved IP #1<br/>Bastion]
        
        D15 --> D17[Output: Instance IPs]
        D16 --> D17
        D17 --> D18[SSH to Bastion]
        D18 --> D19[tailscale up on all nodes]
        D19 --> D20[Verify Mesh Connectivity]
    end
    
    subgraph "Proxmox Cluster Phase"
        E1[task deploy:proxmox] --> E2[cd tofu/proxmox-cluster]
        E2 --> E3[Read OCI Instance IPs<br/>from remote state]
        E3 --> E4[tofu plan]
        E4 --> E5[tofu apply]
        
        E5 --> E6[SSH Provisioner:<br/>node1]
        E6 --> E7[pvecm create cluster-name]
        E7 --> E8[Ansible: Install Proxmox<br/>from official repos]
        E8 --> E9[Run tteck post-install:<br/>disable enterprise repo<br/>remove subscription nag]
        
        E5 --> E10[SSH Provisioner:<br/>node2, node3]
        E10 --> E11[pvecm add node1-ip]
        E11 --> E12[Ansible: Install Proxmox]
        E12 --> E13[Run tteck scripts]
        
        E9 --> E14[pvecm status<br/>Verify Quorum]
        E13 --> E14
        
        E14 --> E15[pveceph init<br/>--network 10.0.1.0/24]
        E15 --> E16[pveceph mon create<br/>on all nodes]
        E16 --> E17[pveceph osd create<br/>from available storage]
        E17 --> E18[pveceph pool create<br/>vm-storage]
        E18 --> E19[ceph -s<br/>Verify HEALTH_OK]
        
        E19 --> E20[Create Tailscale LXC<br/>on each node]
        E20 --> E21[tailscale up in LXC]
        
        E21 --> E22[Test VM Migration:<br/>qm migrate 999 node2]
        E22 --> E23[Verify Live Migration<br/>Success]
    end
    
    subgraph "Talos K8s Phase"
        F1[task deploy:talos] --> F2[cd tofu/talos]
        F2 --> F3[Read Proxmox API<br/>from remote state]
        F3 --> F4[tofu plan]
        F4 --> F5[tofu apply]
        
        F5 --> F6[Download Talos Image<br/>factory.talos.dev/nocloud-arm64]
        F6 --> F7[Upload to Proxmox<br/>as disk image]
        
        F7 --> F8[Render talos-config.yaml.tpl<br/>with Flux URLs]
        F8 --> F9[Create cloud-init snippet<br/>in Proxmox]
        
        F9 --> F10[Create 3x Talos VMs<br/>4GB RAM, 1 OCPU, 20GB disk]
        F10 --> F11[Attach cloud-init config]
        F11 --> F12[Start VMs]
        
        F12 --> F13[Talos boots]
        F13 --> F14[Apply machine config<br/>from cloud-init]
        F14 --> F15[Fetch Cilium manifest<br/>from GitHub]
        F15 --> F16[Deploy Cilium CNI]
        F16 --> F17[Networking Active]
        
        F17 --> F18[Fetch Flux install.yaml<br/>from GitHub]
        F18 --> F19[Deploy Flux Controllers]
        F19 --> F20[Fetch flux-sync.yaml<br/>from GitHub]
        F20 --> F21[GitRepository:<br/>oci-free-tier-flux]
        
        F21 --> F22[OpenTofu: Create K8s Secret<br/>sops-age]
        F22 --> F23[Inject Age private key<br/>to flux-system namespace]
        
        F23 --> F24[Flux Reconciles<br/>Every 1 minute]
        F24 --> F25[Decrypt secrets with SOPS]
        F25 --> F26[Apply HelmReleases:<br/>Tailscale, Cert-Manager<br/>OCI CCM, Alloy]
        
        F26 --> F27[kubectl get nodes<br/>Verify cluster ready]
        F27 --> F28[flux get all<br/>Verify GitOps active]
    end
    
    subgraph "Validation Phase"
        G1[task validate] --> G2[validate:images]
        G1 --> G3[validate:oci]
        G1 --> G4[validate:proxmox]
        G1 --> G5[validate:talos]
        G1 --> G6[validate:cost]
        
        G2 --> G7[Check image sizes<br/>< 20GB total]
        G3 --> G8[Verify 4 instances running<br/>within free tier limits]
        G4 --> G9[pvecm status: quorum<br/>ceph -s: HEALTH_OK]
        G5 --> G10[kubectl get nodes: Ready<br/>flux get all: reconciled]
        G6 --> G11[oci budgets: $0.00<br/>Grafana Cloud: within free tier]
        
        G7 --> G12{All Pass?}
        G8 --> G12
        G9 --> G12
        G10 --> G12
        G11 --> G12
        
        G12 -->|Yes| G13[✓ Deployment Complete]
        G12 -->|No| G14[ERROR: Validation Failed]
    end
    
    A8 --> C1
    B8 --> C1
    C20 --> D1
    D20 --> E1
    E23 --> F1
    F28 --> G1
    
    style A1 fill:#e1f5ff
    style C2 fill:#fff9e1
    style D6 fill:#ffe1f5
    style E5 fill:#f5e1ff
    style F5 fill:#e1ffe1
    style G13 fill:#c8e6c9
    style G14 fill:#ffcdd2
```

---

## Talos Kubernetes Architecture

### Simplified Talos Architecture

High-level view of Talos deployment on Proxmox.

```mermaid
graph TB
    subgraph "OCI Infrastructure"
        A[3x Ampere A1<br/>ARM64<br/>1.33 OCPU, 8GB RAM]
        B[1x Micro Bastion<br/>x86<br/>1GB RAM]
    end
    
    subgraph "Proxmox Cluster"
        C[Proxmox Node 1<br/>Ampere #1]
        D[Proxmox Node 2<br/>Ampere #2]
        E[Proxmox Node 3<br/>Ampere #3]
        
        F[Ceph Distributed Storage<br/>50GB per node = 150GB total]
        
        C --- F
        D --- F
        E --- F
    end
    
    subgraph "Talos VMs on Proxmox"
        G[Talos Control Plane 1<br/>4GB RAM, 20GB disk]
        H[Talos Control Plane 2<br/>4GB RAM, 20GB disk]
        I[Talos Control Plane 3<br/>4GB RAM, 20GB disk]
    end
    
    subgraph "Kubernetes Layer"
        J[etcd Cluster<br/>3 replicas]
        K[kube-apiserver<br/>3 replicas]
        L[Cilium CNI<br/>kube-proxy-free]
        M[Flux GitOps<br/>Continuous Reconciliation]
    end
    
    subgraph "Applications"
        N[Tailscale Operator<br/>Mesh Networking]
        O[Cert-Manager<br/>TLS Certificates]
        P[OCI CCM<br/>LoadBalancer Integration]
        Q[Grafana Alloy<br/>Observability Agents]
    end
    
    A --> C
    A --> D
    A --> E
    
    C --> G
    D --> H
    E --> I
    
    G --> J
    H --> J
    I --> J
    
    J --> K
    K --> L
    L --> M
    
    M --> N
    M --> O
    M --> P
    M --> Q
    
    B -.SSH Access.-> C
    B -.SSH Access.-> D
    B -.SSH Access.-> E
    
    style A fill:#ffebee
    style B fill:#e3f2fd
    style C fill:#f3e5f5
    style D fill:#f3e5f5
    style E fill:#f3e5f5
    style F fill:#fff9c4
    style G fill:#e8f5e9
    style H fill:#e8f5e9
    style I fill:#e8f5e9
    style J fill:#e1f5fe
    style K fill:#e1f5fe
    style L fill:#fce4ec
    style M fill:#f3e5f5
```

### Detailed Talos Deployment

Complete deployment flow with bootstrap sequence and GitOps integration.

```mermaid
sequenceDiagram
    participant TF as Terraform
    participant PVE as Proxmox API
    participant TALOS as Talos Nodes
    participant FACTORY as factory.talos.dev
    participant GITHUB as GitHub (Flux Repo)
    participant CILIUM as Cilium CNI
    participant FLUX as Flux Controllers
    participant K8S as Kubernetes API
    participant APPS as Applications
    
    Note over TF,APPS: Phase 1: VM Provisioning
    
    TF->>FACTORY: Download nocloud-arm64.raw.xz
    FACTORY-->>TF: Talos Image (v1.8.3)
    TF->>PVE: Upload image to Proxmox storage
    
    TF->>TF: Render talos-config.yaml.tpl<br/>with Cilium/Flux URLs
    TF->>PVE: Create cloud-init snippet<br/>from rendered config
    
    loop For each node (3x)
        TF->>PVE: Create VM<br/>4GB RAM, 1 OCPU, 20GB
        TF->>PVE: Attach Talos image as disk
        TF->>PVE: Attach cloud-init config
        TF->>PVE: Start VM
    end
    
    Note over TALOS: Phase 2: Talos Bootstrap
    
    loop All 3 nodes
        TALOS->>TALOS: Boot from Talos image
        TALOS->>TALOS: Read cloud-init config
        TALOS->>TALOS: Apply machine configuration
    end
    
    Note over TALOS,CILIUM: Phase 3: Networking (CNI must be first!)
    
    TALOS->>GITHUB: Fetch bootstrap/cilium.yaml
    GITHUB-->>TALOS: Cilium manifest
    TALOS->>CILIUM: Deploy Cilium CNI<br/>kube-proxy-free mode
    CILIUM->>CILIUM: Initialize eBPF programs
    CILIUM->>K8S: Networking ready
    
    Note over TALOS,FLUX: Phase 4: GitOps Installation
    
    TALOS->>GITHUB: Fetch flux2/install.yaml
    GITHUB-->>TALOS: Flux controllers manifest
    TALOS->>FLUX: Deploy Flux<br/>(source, kustomize, helm, notification)
    
    TALOS->>GITHUB: Fetch bootstrap/flux-sync.yaml
    GITHUB-->>TALOS: GitRepository + Kustomization
    TALOS->>FLUX: Configure Git sync<br/>repo: oci-free-tier-flux<br/>branch: main
    
    Note over TF,FLUX: Phase 5: SOPS Key Injection
    
    TF->>TF: Read age-key.txt<br/>from secrets/
    TF->>K8S: Create Secret sops-age<br/>namespace: flux-system
    K8S-->>FLUX: Secret available
    
    Note over FLUX,APPS: Phase 6: Flux Reconciliation Loop
    
    loop Every 1 minute
        FLUX->>GITHUB: Poll for changes
        GITHUB-->>FLUX: Manifests (encrypted)
        FLUX->>FLUX: Decrypt secrets with SOPS<br/>using sops-age key
        
        alt infrastructure/base/cert-manager
            FLUX->>APPS: Deploy cert-manager<br/>(dependency for Tailscale)
            APPS-->>FLUX: Ready
        end
        
        alt infrastructure/base/tailscale-operator
            FLUX->>APPS: Deploy Tailscale Operator<br/>with decrypted OAuth secret
            APPS->>APPS: Join Tailscale mesh
            APPS-->>FLUX: Ready
        end
        
        alt infrastructure/base/oci-ccm
            FLUX->>APPS: Deploy OCI Cloud Controller<br/>(optional, for LoadBalancer)
            APPS-->>FLUX: Ready
        end
        
        alt apps/base/monitoring
            FLUX->>APPS: Deploy Grafana Alloy<br/>with decrypted API keys
            APPS->>APPS: Start collecting metrics
            APPS-->>FLUX: Ready
        end
        
        FLUX->>K8S: Apply all manifests
        K8S-->>FLUX: Reconciliation complete
    end
    
    Note over FLUX: Self-healing: Flux reverts manual changes
```

---

## Terraform Components

### Simplified Terraform Layers

Three-layer architecture with intervention points.

```mermaid
graph TB
    subgraph "Layer 1: tofu/oci"
        A[OCI Provider<br/>oracle/oci]
        B[VCN Resources<br/>10.0.0.0/16]
        C[Compute Instances<br/>3x Ampere + 1x Micro]
        D[Block Storage<br/>200GB total]
        E[Budget Alerts<br/>$0.01 threshold]
        
        A --> B
        A --> C
        A --> D
        A --> E
    end
    
    subgraph "Layer 2: tofu/proxmox-cluster"
        F[SSH/Ansible Provider]
        G[Proxmox Cluster<br/>pvecm create/add]
        H[Ceph Configuration<br/>pveceph init/osd]
        I[Tailscale LXC<br/>mesh networking]
        
        F --> G
        G --> H
        H --> I
    end
    
    subgraph "Layer 3: tofu/talos"
        J[Proxmox Provider<br/>bpg/proxmox]
        K[Talos VMs<br/>cloud-init configs]
        L[Kubernetes Bootstrap<br/>via machine config]
        M[Flux SOPS Secrets<br/>Age key injection]
        
        J --> K
        K --> L
        L --> M
    end
    
    C -->|Instance IPs| F
    I -->|Proxmox API| J
    
    N[Layer 1 Output:<br/>Instance IPs, SSH Access]
    O[Layer 2 Output:<br/>Proxmox API, Ceph Status]
    P[Layer 3 Output:<br/>kubeconfig, Cluster Endpoints]
    
    E --> N
    I --> O
    M --> P
    
    Q[Intervention Point 1:<br/>Verify OCI instances]
    R[Intervention Point 2:<br/>Check Proxmox cluster health]
    S[Intervention Point 3:<br/>Access Talos before K8s bootstrap]
    
    N -.-> Q
    O -.-> R
    P -.-> S
    
    style A fill:#e1f5ff
    style F fill:#ffe1f5
    style J fill:#e1ffe1
    style Q fill:#fff9e1
    style R fill:#fff9e1
    style S fill:#fff9e1
```

### Detailed Terraform Components

Complete resource graph with dependencies.

```mermaid
graph TB
    subgraph "tofu/oci/main.tf - Networking"
        A[oci_core_vcn.free_tier_vcn<br/>CIDR: 10.0.0.0/16<br/>DNS: freetier]
        B[oci_core_internet_gateway<br/>free_tier_igw]
        C[oci_core_route_table<br/>0.0.0.0/0 → IGW]
        D[oci_core_security_list<br/>SSH, HTTP, HTTPS, ICMP]
        E[oci_core_subnet<br/>10.0.1.0/24<br/>DNS: subnet]
        
        A --> B
        A --> C
        A --> D
        A --> E
        B --> C
        C --> E
        D --> E
    end
    
    subgraph "tofu/oci/main.tf - Compute"
        F[oci_core_instance.ampere<br/>count = 3<br/>VM.Standard.A1.Flex<br/>1.33 OCPU, 8GB RAM]
        G[oci_core_instance.micro<br/>count = 1<br/>VM.Standard.E2.1.Micro<br/>1GB RAM]
        
        E --> F
        E --> G
    end
    
    subgraph "tofu/oci/main.tf - Storage"
        H[source_details.boot_volume<br/>Ampere: 50GB each<br/>Micro: 50GB]
        I[oci_core_volume<br/>additional_storage<br/>optional]
        
        F --> H
        G --> H
        F --> I
    end
    
    subgraph "tofu/oci/main.tf - Budget"
        J[oci_budget_budget<br/>$0.01 threshold]
        K[oci_budget_alert_rule<br/>email notification]
        
        J --> K
    end
    
    subgraph "tofu/oci/data.tf - Data Sources"
        L[data.oci_identity_availability_domains<br/>Get ADs for region]
        M[data.oci_core_images.ampere<br/>Ubuntu 22.04 ARM64]
        N[data.oci_core_images.micro<br/>Ubuntu 22.04 x86]
        
        L --> F
        L --> G
        M --> F
        N --> G
    end
    
    subgraph "tofu/oci/variables.tf - Inputs"
        O[var.compartment_ocid<br/>required]
        P[var.ssh_public_key<br/>required]
        Q[var.region<br/>default: uk-london-1]
        R[var.ampere_instance_count<br/>validation: 0-4]
        S[var.ampere_ocpus_per_instance<br/>validation: 1-4]
        T[var.budget_alert_email<br/>required]
        
        O --> F
        O --> G
        O --> J
        P --> F
        P --> G
        Q --> L
        R --> F
        S --> F
        T --> K
    end
    
    subgraph "tofu/oci/outputs.tf - Outputs"
        U[output.ampere_public_ips<br/>for Proxmox provisioning]
        V[output.micro_public_ip<br/>bastion SSH access]
        W[output.vcn_id<br/>for additional resources]
        
        F --> U
        G --> V
        A --> W
    end
    
    subgraph "tofu/proxmox-cluster/main.tf"
        X[null_resource.proxmox_cluster<br/>SSH provisioner]
        Y[null_resource.ceph_init<br/>pveceph commands]
        Z[null_resource.tailscale_lxc<br/>LXC creation script]
        AA[null_resource.test_migration<br/>qm migrate validation]
        
        U -.remote state.-> X
        X --> Y
        Y --> Z
        Z --> AA
    end
    
    subgraph "tofu/proxmox-cluster/outputs.tf"
        AB[output.proxmox_api_url<br/>https://node:8006/api2/json]
        AC[output.ceph_health<br/>HEALTH_OK status]
        
        AA --> AB
        AA --> AC
    end
    
    subgraph "tofu/talos/providers.tf"
        AD[provider.proxmox<br/>bpg/proxmox<br/>telmate/proxmox deprecated]
        AE[provider.kubernetes<br/>for SOPS secret]
        
        AB -.remote state.-> AD
    end
    
    subgraph "tofu/talos/talos-vms.tf"
        AF[proxmox_virtual_environment_download_file<br/>Talos nocloud image]
        AG[proxmox_virtual_environment_file<br/>cloud-init snippet]
        AH[proxmox_virtual_environment_vm<br/>count = 3<br/>4GB RAM, 1 OCPU, 20GB]
        
        AD --> AF
        AD --> AG
        AF --> AH
        AG --> AH
    end
    
    subgraph "tofu/talos/talos-config.yaml.tpl"
        AI[template: machine.type = controlplane]
        AJ[template: cluster.network.cni = none]
        AK[template: externalCloudProvider.manifests<br/>Cilium, Flux, flux-sync]
        
        AI --> AG
        AJ --> AG
        AK --> AG
    end
    
    subgraph "tofu/talos/flux-secrets.tf"
        AL[kubernetes_secret.sops_age<br/>namespace: flux-system<br/>age.agekey: file content]
        AM[null_resource.wait_for_flux<br/>kubectl wait]
        
        AH --> AM
        AM --> AL
    end
    
    subgraph "tofu/talos/outputs.tf"
        AN[output.kubeconfig<br/>~/.kube/config]
        AO[output.talosconfig<br/>talosctl access]
        AP[output.cluster_endpoint<br/>https://node:6443]
        
        AH --> AN
        AH --> AO
        AH --> AP
    end
    
    style A fill:#e3f2fd
    style F fill:#ffebee
    style G fill:#fff3e0
    style J fill:#f1f8e9
    style X fill:#fce4ec
    style Y fill:#e8eaf6
    style AD fill:#e0f2f1
    style AH fill:#e8f5e9
    style AL fill:#fff9c4
```

---

## Resource Dependencies

Detailed dependency flow across all three Terraform layers.

```mermaid
graph LR
    subgraph "External Inputs"
        A[~/.oci/config<br/>OCI credentials]
        B[~/.ssh/oci_key<br/>SSH keypair]
        C[age-key.txt<br/>SOPS encryption]
        D[GitHub Repo<br/>oci-free-tier-flux]
    end
    
    subgraph "Layer 1: OCI"
        E[terraform.tfvars<br/>compartment_ocid<br/>ssh_public_key<br/>budget_email]
        F[tofu/oci/main.tf]
        G[OCI Resources<br/>Created]
        H[terraform.tfstate<br/>Layer 1]
        I[outputs:<br/>ampere_ips<br/>micro_ip]
    end
    
    subgraph "Layer 2: Proxmox"
        J[tofu/proxmox-cluster/main.tf]
        K[Remote State:<br/>data.terraform_remote_state.oci]
        L[Proxmox Cluster<br/>Configured]
        M[terraform.tfstate<br/>Layer 2]
        N[outputs:<br/>proxmox_api_url<br/>ceph_health]
    end
    
    subgraph "Layer 3: Talos"
        O[tofu/talos/main.tf]
        P[Remote State:<br/>data.terraform_remote_state.proxmox]
        Q[Talos VMs<br/>+ K8s Cluster]
        R[terraform.tfstate<br/>Layer 3]
        S[outputs:<br/>kubeconfig<br/>cluster_endpoint]
    end
    
    subgraph "GitOps"
        T[Flux Reconciles]
        U[Applications<br/>Deployed]
    end
    
    A --> E
    B --> E
    E --> F
    F --> G
    G --> H
    H --> I
    
    I --> K
    K --> J
    J --> L
    L --> M
    M --> N
    
    N --> P
    P --> O
    C --> O
    O --> Q
    Q --> R
    R --> S
    
    S --> T
    D --> T
    T --> U
    
    style A fill:#e3f2fd
    style B fill:#e3f2fd
    style C fill:#e3f2fd
    style D fill:#e3f2fd
    style G fill:#ffebee
    style L fill:#fce4ec
    style Q fill:#e8f5e9
    style U fill:#fff9c4
```

---

## Cost Verification Flow

How the free tier limits are enforced and validated.

```mermaid
graph TB
    subgraph "Free Tier Limits (Constants)"
        A[Compute:<br/>4 OCPU Ampere<br/>24GB RAM<br/>2x Micro]
        B[Storage:<br/>200GB total<br/>block volumes]
        C[Network:<br/>2 reserved IPs<br/>10TB/month egress]
        D[Object Storage:<br/>20GB for images]
    end
    
    subgraph "Terraform Validations"
        E[variables.tf:<br/>validate ampere_instance_count<br/>0 <= count <= 4]
        F[variables.tf:<br/>validate total OCPUs<br/>count × ocpus <= 4]
        G[variables.tf:<br/>validate total RAM<br/>count × memory <= 24]
        H[variables.tf:<br/>validate micro_instance_count<br/>0 <= count <= 2]
        I[variables.tf:<br/>validate total storage<br/>ampere + micro <= 200GB]
        
        A --> E
        A --> F
        A --> G
        A --> H
        B --> I
    end
    
    subgraph "Pre-Deployment Checks"
        J[task build:validate<br/>Images < 20GB]
        K[tofu plan<br/>Review resources]
        L[Manual Review:<br/>No chargeable resources]
        
        D --> J
        E --> K
        F --> K
        G --> K
        H --> K
        I --> K
        K --> L
    end
    
    subgraph "Runtime Monitoring"
        M[oci_budget_budget<br/>$0.01 threshold]
        N[Email Alert<br/>on any charge]
        O[oci usage-api<br/>usage summarize-usage]
        
        L --> M
        M --> N
        L --> O
    end
    
    subgraph "Post-Deployment Validation"
        P[task validate:cost]
        Q[Check OCI billing:<br/>$0.00 usage]
        R[Check Grafana Cloud:<br/>within 10k series<br/>within 50GB logs]
        S[Verify Budget:<br/>No alerts fired]
        
        O --> P
        P --> Q
        P --> R
        P --> S
    end
    
    subgraph "Result"
        T{All $0.00?}
        U[✓ Safe to Run]
        V[❌ STOP:<br/>Unexpected Charges]
        
        Q --> T
        R --> T
        S --> T
        T -->|Yes| U
        T -->|No| V
    end
    
    style A fill:#e3f2fd
    style B fill:#e3f2fd
    style C fill:#e3f2fd
    style D fill:#e3f2fd
    style M fill:#fff9e1
    style U fill:#c8e6c9
    style V fill:#ffcdd2
```

---

## Network Topology

Physical and logical network layout.

```mermaid
graph TB
    subgraph "Internet"
        A[Public Internet]
    end
    
    subgraph "OCI VCN: 10.0.0.0/16"
        B[Internet Gateway<br/>free_tier_igw]
        C[Route Table<br/>0.0.0.0/0 → IGW]
        D[Security List<br/>SSH/HTTP/HTTPS/ICMP]
        E[Subnet: 10.0.1.0/24]
        
        B --> C
        C --> E
        D --> E
    end
    
    subgraph "Compute Instances"
        F[Ampere 1: 10.0.1.10<br/>Proxmox Node 1<br/>Public: ephemeral]
        G[Ampere 2: 10.0.1.11<br/>Proxmox Node 2<br/>Public: ephemeral]
        H[Ampere 3: 10.0.1.12<br/>Proxmox Node 3<br/>Public: ephemeral]
        I[Micro: 10.0.1.20<br/>Bastion<br/>Public: Reserved IP #1]
        
        E --> F
        E --> G
        E --> H
        E --> I
    end
    
    subgraph "Tailscale Mesh (100.x.x.x)"
        J[Tailscale LXC 1<br/>100.64.0.1]
        K[Tailscale LXC 2<br/>100.64.0.2]
        L[Tailscale LXC 3<br/>100.64.0.3]
        M[Bastion Tailscale<br/>100.64.0.4]
        
        F -.-> J
        G -.-> K
        H -.-> L
        I -.-> M
        
        J -.mesh.-> K
        K -.mesh.-> L
        L -.mesh.-> M
        M -.mesh.-> J
    end
    
    subgraph "Talos VMs (Proxmox Bridge)"
        N[Talos CP 1<br/>10.0.1.100<br/>on Proxmox 1]
        O[Talos CP 2<br/>10.0.1.101<br/>on Proxmox 2]
        P[Talos CP 3<br/>10.0.1.102<br/>on Proxmox 3]
        
        F --> N
        G --> O
        H --> P
    end
    
    subgraph "Kubernetes Services"
        Q[Cilium CNI<br/>10.244.0.0/16 pods<br/>10.96.0.0/12 services]
        R[Ingress Controller<br/>1:1 NAT via Reserved IP #2]
        
        N --> Q
        O --> Q
        P --> Q
        Q --> R
    end
    
    A --> B
    A -.SSH.-> I
    A -.HTTP/HTTPS.-> R
    
    style A fill:#e3f2fd
    style B fill:#ffe0b2
    style E fill:#c8e6c9
    style F fill:#ffebee
    style G fill:#ffebee
    style H fill:#ffebee
    style I fill:#fff3e0
    style J fill:#e1f5fe
    style K fill:#e1f5fe
    style L fill:#e1f5fe
    style M fill:#e1f5fe
    style N fill:#e8f5e9
    style O fill:#e8f5e9
    style P fill:#e8f5e9
    style Q fill:#f3e5f5
    style R fill:#fff9c4
```

---

## Deployment Timeline

Estimated time for each phase.

```mermaid
gantt
    title OCI Free Tier Deployment Timeline
    dateFormat HH:mm
    axisFormat %H:%M
    
    section Setup
    OCI CLI Config         :done, setup1, 00:00, 5m
    SSH Keys              :done, setup2, after setup1, 2m
    terraform.tfvars      :done, setup3, after setup2, 3m
    Flux Repository Setup :done, setup4, after setup3, 10m
    
    section Image Build
    Dagger Pipeline Init  :active, build1, after setup4, 5m
    Base Image Build      :build2, after build1, 25m
    Proxmox Image Build   :build3, after build2, 30m
    Validation            :build4, after build3, 2m
    Upload to OCI         :build5, after build4, 15m
    
    section OCI Infra
    tofu init             :deploy1, after build5, 2m
    tofu plan             :deploy2, after deploy1, 3m
    tofu apply            :deploy3, after deploy2, 10m
    Tailscale Setup       :deploy4, after deploy3, 5m
    
    section Proxmox
    Cluster Formation     :prox1, after deploy4, 5m
    Ceph Initialization   :prox2, after prox1, 15m
    Ceph Pool Creation    :prox3, after prox2, 5m
    Tailscale LXC         :prox4, after prox3, 5m
    Test Migration        :prox5, after prox4, 3m
    
    section Talos K8s
    Download Talos Image  :talos1, after prox5, 5m
    Create VMs            :talos2, after talos1, 10m
    Bootstrap Cluster     :talos3, after talos2, 8m
    Deploy Cilium         :talos4, after talos3, 3m
    Deploy Flux           :talos5, after talos4, 2m
    Inject SOPS Keys      :talos6, after talos5, 2m
    
    section GitOps
    Flux Reconciliation   :flux1, after talos6, 5m
    Deploy Applications   :flux2, after flux1, 10m
    
    section Validation
    All Validation Checks :valid1, after flux2, 5m
    
    section Total
    End to End           :milestone, after valid1, 0m
```

**Estimated total time:** ~3 hours (including image builds)  
**Fastest path (pre-built images):** ~1 hour

---

## Legend

### Graph Colors

- **Blue** (`#e1f5ff`, `#e3f2fd`): Setup and initialization
- **Yellow** (`#fff9e1`, `#fff3e0`): Build and validation
- **Pink** (`#ffe1f5`, `#ffebee`): OCI infrastructure
- **Purple** (`#f5e1ff`, `#f3e5f5`): Proxmox configuration
- **Green** (`#e1ffe1`, `#e8f5e9`, `#c8e6c9`): Kubernetes/Talos
- **Red** (`#ffe1e1`, `#ffcdd2`): Errors or warnings
- **Amber** (`#fff9c4`): Monitoring and observability

### Abbreviations

- **OCI**: Oracle Cloud Infrastructure
- **VCN**: Virtual Cloud Network
- **CNI**: Container Network Interface
- **CCM**: Cloud Controller Manager
- **LXC**: Linux Container
- **SOPS**: Secrets OPerationS (encryption)
- **eBPF**: Extended Berkeley Packet Filter

---

## Related Documentation

- [PLAN.md](../PLAN.md) - Detailed deployment plan
- [QUICKSTART.md](./QUICKSTART.md) - Quick start guide
- [WARP.md](../WARP.md) - Architecture overview
- [nix-dagger-analysis.md](./nix-dagger-analysis.md) - Tooling comparison
