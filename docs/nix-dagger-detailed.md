# Nix + Dagger Implementation - Detailed Plan

## Architecture Overview

**Separation of Concerns:**
- **Nix Flake**: Dev environment, tool versioning, CLI orchestration
- **Dagger**: Complex builds (Packer images), upload to OCI
- **OpenTofu**: Infrastructure state management
- **Flux**: Kubernetes GitOps

## Directory Structure

```
oci-free-tier-manager/
├── flake.nix                    # Nix flake (dev env + apps)
├── flake.lock                   # Locked dependencies
├── .envrc                       # direnv integration (optional)
│
├── dagger/                      # Dagger pipeline code
│   ├── pyproject.toml          # Python dependencies
│   ├── uv.lock                 # Locked Python deps
│   └── src/
│       └── main/
│           ├── __init__.py
│           └── pipeline.py     # Image building logic
│
├── dagger.json                  # Dagger configuration
│
├── packer/                      # Packer templates
│   ├── base-hardened.pkr.hcl
│   ├── proxmox-ampere.pkr.hcl
│   ├── scripts/
│   │   ├── harden-base.sh
│   │   └── install-proxmox.sh
│   └── files/
│       ├── sshd_config
│       └── firewall.rules
│
├── tofu/                        # OpenTofu modules
│   ├── oci/                    # Layer 1: Bare metal
│   ├── proxmox-cluster/        # Layer 2: Proxmox + Ceph
│   └── talos/                  # Layer 3: K8s
│
├── scripts/                     # Helper utilities only
│   └── validate-*.sh
│
├── devbox.json                  # Keep for backward compat
├── devbox.lock
│
└── docs/
    └── nix-dagger-detailed.md  # This file
```

## Phase 1: Nix Flake Setup

### 1.1 Create flake.nix

```nix
# flake.nix
{
  description = "OCI Free Tier Infrastructure with Proxmox and Talos K8s";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Python environment for Dagger
        pythonEnv = pkgs.python312.withPackages (ps: with ps; [
          dagger-io
          requests
          pyyaml
        ]);
        
      in {
        # Development shell (replaces/augments devbox)
        devShells.default = pkgs.mkShell {
          name = "oci-free-tier-dev";
          
          buildInputs = with pkgs; [
            # Infrastructure tools
            opentofu
            kubectl
            helm
            talosctl
            
            # Security tools
            sops
            age
            
            # Image building
            packer
            qemu
            
            # Dagger
            dagger
            pythonEnv
            
            # Utilities
            jq
            yq
            gh
            git
            curl
            
            # OCI CLI
            oci-cli
            
            # Linting/formatting
            terraform-ls
            tflint
            shellcheck
            yamllint
            
            # Pre-commit
            pre-commit
          ];
          
          shellHook = ''
            echo "🚀 OCI Free Tier Manager Development Environment"
            echo ""
            echo "Available commands:"
            echo "  nix run .#build-images     - Build Packer images with Dagger"
            echo "  nix run .#deploy-oci       - Deploy OCI infrastructure"
            echo "  nix run .#deploy-proxmox   - Setup Proxmox cluster"
            echo "  nix run .#deploy-talos     - Deploy Talos Kubernetes"
            echo "  nix run .#deploy-all       - Full deployment (all phases)"
            echo "  nix run .#validate         - Run validation checks"
            echo ""
            
            # Initialize pre-commit hooks
            if [ -f .git/hooks/pre-commit ]; then
              echo "✓ Pre-commit hooks installed"
            else
              echo "Installing pre-commit hooks..."
              pre-commit install
            fi
          '';
        };
        
        # Nix apps (CLI commands)
        apps = {
          # Build images with Dagger
          build-images = {
            type = "app";
            program = toString (pkgs.writeShellScript "build-images" ''
              set -euo pipefail
              echo "Building custom images with Dagger..."
              ${pkgs.dagger}/bin/dagger call \
                --source=. \
                build-all-images
            '');
          };
          
          # Deploy OCI infrastructure
          deploy-oci = {
            type = "app";
            program = toString (pkgs.writeShellScript "deploy-oci" ''
              set -euo pipefail
              echo "Deploying OCI infrastructure (Layer 1)..."
              cd tofu/oci
              ${pkgs.opentofu}/bin/tofu init -upgrade
              ${pkgs.opentofu}/bin/tofu apply
            '');
          };
          
          # Setup Proxmox cluster
          deploy-proxmox = {
            type = "app";
            program = toString (pkgs.writeShellScript "deploy-proxmox" ''
              set -euo pipefail
              echo "Setting up Proxmox cluster (Layer 2)..."
              cd tofu/proxmox-cluster
              ${pkgs.opentofu}/bin/tofu init -upgrade
              ${pkgs.opentofu}/bin/tofu apply
            '');
          };
          
          # Deploy Talos Kubernetes
          deploy-talos = {
            type = "app";
            program = toString (pkgs.writeShellScript "deploy-talos" ''
              set -euo pipefail
              echo "Deploying Talos Kubernetes (Layer 3)..."
              cd tofu/talos
              ${pkgs.opentofu}/bin/tofu init -upgrade
              ${pkgs.opentofu}/bin/tofu apply
            '');
          };
          
          # Full deployment
          deploy-all = {
            type = "app";
            program = toString (pkgs.writeShellScript "deploy-all" ''
              set -euo pipefail
              
              echo "╔═══════════════════════════════════════════╗"
              echo "║  OCI Free Tier Full Stack Deployment     ║"
              echo "╚═══════════════════════════════════════════╝"
              echo ""
              
              # Phase 1: Build images
              echo "==> Phase 1: Building custom images..."
              nix run .#build-images
              echo ""
              
              # Phase 2: Deploy OCI
              echo "==> Phase 2: Deploying OCI infrastructure..."
              nix run .#deploy-oci
              echo ""
              
              # Phase 3: Setup Proxmox
              echo "==> Phase 3: Setting up Proxmox cluster..."
              nix run .#deploy-proxmox
              echo ""
              
              # Phase 4: Deploy Talos
              echo "==> Phase 4: Deploying Talos Kubernetes..."
              nix run .#deploy-talos
              echo ""
              
              echo "✓ Full deployment complete!"
              echo ""
              echo "Run 'nix run .#validate' to verify the deployment."
            '');
          };
          
          # Validation
          validate = {
            type = "app";
            program = toString (pkgs.writeShellScript "validate" ''
              set -euo pipefail
              
              echo "Running validation checks..."
              
              # Validate images
              if [ -f scripts/validate-phase1.sh ]; then
                bash scripts/validate-phase1.sh
              fi
              
              # Validate OCI
              if [ -f scripts/validate-phase2.sh ]; then
                bash scripts/validate-phase2.sh
              fi
              
              # Validate Proxmox
              if [ -f scripts/validate-phase3.sh ]; then
                bash scripts/validate-phase3.sh
              fi
              
              # Validate Talos
              if [ -f scripts/validate-phase4.sh ]; then
                bash scripts/validate-phase4.sh
              fi
              
              # Validate cost
              if [ -f scripts/validate-cost.sh ]; then
                bash scripts/validate-cost.sh
              fi
              
              echo "✓ All validation checks passed!"
            '');
          };
          
          # Destroy everything (for testing)
          destroy-all = {
            type = "app";
            program = toString (pkgs.writeShellScript "destroy-all" ''
              set -euo pipefail
              
              echo "⚠️  WARNING: This will destroy ALL infrastructure!"
              read -p "Are you sure? (type 'yes' to confirm): " confirm
              
              if [ "$confirm" != "yes" ]; then
                echo "Aborted."
                exit 1
              fi
              
              # Destroy in reverse order
              echo "Destroying Talos cluster..."
              cd tofu/talos && ${pkgs.opentofu}/bin/tofu destroy -auto-approve
              
              echo "Destroying Proxmox cluster..."
              cd ../proxmox-cluster && ${pkgs.opentofu}/bin/tofu destroy -auto-approve
              
              echo "Destroying OCI infrastructure..."
              cd ../oci && ${pkgs.opentofu}/bin/tofu destroy -auto-approve
              
              echo "✓ All infrastructure destroyed"
            '');
          };
        };
        
        # Packages (for nix build)
        packages = {
          # Could add packages here if needed
          # e.g., custom scripts as derivations
        };
      }
    );
}
```

### 1.2 Create .envrc (optional, for direnv users)

```bash
# .envrc
use flake
```

This automatically enters the Nix shell when you `cd` into the directory.

## Phase 2: Dagger Pipeline

### 2.1 Initialize Dagger

```bash
# In project root
dagger init --sdk=python --source=dagger
```

### 2.2 Create Dagger pipeline (Python)

```python
# dagger/src/main/__init__.py
"""
OCI Free Tier Infrastructure Pipeline

Handles:
- Building Packer images (base + Proxmox)
- Uploading to OCI Object Storage
- Creating OCI custom images
"""

import dagger
from dagger import dag, function, object_type
from typing import Annotated
import os


@object_type
class Main:
    """Main pipeline for OCI Free Tier infrastructure"""
    
    @function
    async def build_base_image(
        self,
        source: Annotated[
            dagger.Directory,
            dagger.Doc("Source directory with Packer configs")
        ]
    ) -> dagger.Directory:
        """
        Build base hardened image with Packer
        
        Returns directory with base-hardened.qcow2
        """
        return await (
            dag.container()
            .from_("hashicorp/packer:latest")
            
            # Install dependencies
            .with_exec(["apk", "add", "--no-cache", "qemu-img", "qemu-system-x86_64"])
            
            # Copy Packer configs
            .with_directory("/work", source.directory("packer"))
            .with_workdir("/work")
            
            # Initialize Packer
            .with_exec(["packer", "init", "."])
            
            # Build base image
            .with_exec([
                "packer", "build",
                "-force",
                "-var", "headless=true",
                "base-hardened.pkr.hcl"
            ])
            
            # Return output directory
            .directory("/work/output-qemu")
        )
    
    @function
    async def build_proxmox_image(
        self,
        source: Annotated[dagger.Directory, dagger.Doc("Source directory")],
        base_image: Annotated[dagger.Directory, dagger.Doc("Base image directory")]
    ) -> dagger.Directory:
        """
        Build Proxmox image from base
        
        Returns directory with proxmox-ampere.qcow2
        """
        return await (
            dag.container()
            .from_("hashicorp/packer:latest")
            
            # Install dependencies
            .with_exec(["apk", "add", "--no-cache", "qemu-img", "qemu-system-x86_64"])
            
            # Copy Packer configs
            .with_directory("/work", source.directory("packer"))
            
            # Copy base image
            .with_directory("/work/base", base_image)
            
            .with_workdir("/work")
            
            # Initialize Packer
            .with_exec(["packer", "init", "."])
            
            # Build Proxmox image
            .with_exec([
                "packer", "build",
                "-force",
                "-var", "headless=true",
                "-var", "source_image=/work/base/base-hardened.qcow2",
                "proxmox-ampere.pkr.hcl"
            ])
            
            # Return output directory
            .directory("/work/output-qemu")
        )
    
    @function
    async def build_all_images(
        self,
        source: Annotated[
            dagger.Directory,
            dagger.Doc("Source directory with Packer configs")
        ] = None
    ) -> str:
        """
        Build both images sequentially and export to host
        
        Returns success message with artifact locations
        """
        # Use current directory if not provided
        if source is None:
            source = dag.host().directory(".")
        
        print("Building base image...")
        base = await self.build_base_image(source)
        
        print("Building Proxmox image...")
        proxmox = await self.build_proxmox_image(source, base)
        
        # Export to host
        print("Exporting images to ./artifacts/...")
        await base.export("./artifacts/base-hardened")
        await proxmox.export("./artifacts/proxmox-ampere")
        
        # Get image sizes
        base_files = await base.entries()
        proxmox_files = await proxmox.entries()
        
        return f"""
✓ Images built successfully!

Artifacts:
  - Base image: ./artifacts/base-hardened/{base_files[0]}
  - Proxmox image: ./artifacts/proxmox-ampere/{proxmox_files[0]}

Next steps:
  1. Upload to OCI: dagger call upload-to-oci
  2. Deploy infrastructure: nix run .#deploy-oci
"""
    
    @function
    async def upload_to_oci(
        self,
        bucket: Annotated[str, dagger.Doc("OCI Object Storage bucket name")],
        compartment_id: Annotated[str, dagger.Doc("OCI compartment OCID")],
        region: Annotated[str, dagger.Doc("OCI region")] = "uk-london-1",
        oci_config: Annotated[
            dagger.Secret,
            dagger.Doc("OCI CLI config file content")
        ] = None
    ) -> str:
        """
        Upload images to OCI Object Storage and create custom images
        
        Requires OCI CLI authentication (via config file or env vars)
        """
        # Read artifacts from host
        artifacts = dag.host().directory("./artifacts")
        
        container = (
            dag.container()
            .from_("ghcr.io/oracle/oci-cli:latest")
            .with_directory("/artifacts", artifacts)
        )
        
        # Configure OCI CLI if config provided
        if oci_config:
            container = container.with_secret_variable("OCI_CONFIG", oci_config)
        
        # Upload base image
        result = await (
            container
            .with_exec([
                "oci", "os", "object", "put",
                "--bucket-name", bucket,
                "--file", "/artifacts/base-hardened/base-hardened.qcow2",
                "--name", "base-hardened.qcow2",
                "--force"
            ])
            
            # Upload Proxmox image
            .with_exec([
                "oci", "os", "object", "put",
                "--bucket-name", bucket,
                "--file", "/artifacts/proxmox-ampere/proxmox-ampere.qcow2",
                "--name", "proxmox-ampere.qcow2",
                "--force"
            ])
            
            # Verify total size < 20GB
            .with_exec([
                "sh", "-c",
                f"oci os object list --bucket-name {bucket} "
                "--query 'data[].\"size\"' | "
                "jq 'add' | "
                "awk '{if ($1 > 21474836480) exit 1}'"
            ])
            
            # Create custom images
            .with_exec([
                "oci", "compute", "image", "create",
                "--compartment-id", compartment_id,
                "--display-name", "base-hardened",
                "--bucket-name", bucket,
                "--object-name", "base-hardened.qcow2",
                "--region", region
            ])
            
            .with_exec([
                "oci", "compute", "image", "create",
                "--compartment-id", compartment_id,
                "--display-name", "proxmox-ampere",
                "--bucket-name", bucket,
                "--object-name", "proxmox-ampere.qcow2",
                "--region", region
            ])
            
            .stdout()
        )
        
        return f"✓ Images uploaded to OCI Object Storage and custom images created\n{result}"
    
    @function
    async def validate_images(
        self,
        max_size_gb: Annotated[int, dagger.Doc("Max size per image in GB")] = 10
    ) -> str:
        """
        Validate that built images meet size requirements
        
        Returns validation report
        """
        artifacts = dag.host().directory("./artifacts")
        
        result = await (
            dag.container()
            .from_("alpine:latest")
            .with_exec(["apk", "add", "--no-cache", "qemu-img", "jq"])
            .with_directory("/artifacts", artifacts)
            .with_exec([
                "sh", "-c",
                f"""
                set -e
                echo "Validating image sizes..."
                
                BASE_SIZE=$(qemu-img info --output=json /artifacts/base-hardened/*.qcow2 | jq '.["virtual-size"]')
                PROXMOX_SIZE=$(qemu-img info --output=json /artifacts/proxmox-ampere/*.qcow2 | jq '.["virtual-size"]')
                TOTAL_SIZE=$((BASE_SIZE + PROXMOX_SIZE))
                MAX_SIZE=$((21474836480))  # 20GB in bytes
                
                echo "Base image: $(($BASE_SIZE / 1024 / 1024 / 1024))GB"
                echo "Proxmox image: $(($PROXMOX_SIZE / 1024 / 1024 / 1024))GB"
                echo "Total: $(($TOTAL_SIZE / 1024 / 1024 / 1024))GB / 20GB"
                
                if [ $TOTAL_SIZE -gt $MAX_SIZE ]; then
                    echo "ERROR: Total size exceeds 20GB OCI free tier limit!"
                    exit 1
                fi
                
                echo "✓ Images within size limits"
                """
            ])
            .stdout()
        )
        
        return result
```

### 2.3 Dagger configuration

```json
// dagger.json
{
  "name": "oci-free-tier",
  "sdk": "python",
  "source": "dagger"
}
```

## Phase 3: Integration

### 3.1 Update .gitignore

```gitignore
# Nix
result
result-*
.direnv/

# Dagger
.dagger/

# Artifacts
artifacts/
*.qcow2

# Packer
output-qemu/
packer_cache/
```

### 3.2 Transition from devbox

**Option A: Keep both** (backward compatible)
- Keep `devbox.json` for users who prefer devbox
- Add `flake.nix` for Nix flake users
- Both work, user chooses

**Option B: Migrate fully to Nix flakes**
- Remove `devbox.json` and `devbox.lock`
- Update docs to use `nix develop`
- Cleaner but breaks existing workflow

**Recommended: Option A** (keep both initially)

## Workflow Examples

### Developer Workflow

```bash
# Enter dev environment (pick one)
nix develop              # Nix flakes
devbox shell             # devbox (still works)

# OR use direnv (automatic)
cd oci-free-tier-manager  # Auto-enters nix shell

# Build images
nix run .#build-images

# Deploy infrastructure
nix run .#deploy-all

# Or deploy layer by layer
nix run .#deploy-oci
nix run .#deploy-proxmox
nix run .#deploy-talos

# Validate
nix run .#validate

# Destroy (for testing)
nix run .#destroy-all
```

### CI/CD Workflow (GitHub Actions)

```yaml
# .github/workflows/deploy.yml
name: Deploy Infrastructure

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  build-images:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - uses: DeterminateSystems/nix-installer-action@v9
      - uses: DeterminateSystems/magic-nix-cache-action@v2
      
      - uses: dagger/dagger-for-github@v5
        with:
          verb: call
          args: build-all-images
      
      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: images
          path: artifacts/
  
  deploy:
    needs: build-images
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
      
      - uses: DeterminateSystems/nix-installer-action@v9
      
      - name: Configure OCI CLI
        env:
          OCI_CONFIG: ${{ secrets.OCI_CONFIG }}
        run: |
          mkdir -p ~/.oci
          echo "$OCI_CONFIG" > ~/.oci/config
      
      - name: Deploy infrastructure
        run: nix run .#deploy-all
```

## Benefits of This Approach

1. **Reproducible**: Nix ensures exact tool versions
2. **Portable**: Dagger runs same locally and CI
3. **Type-safe**: Python Dagger code is testable
4. **Cacheable**: Both Nix and Dagger have intelligent caching
5. **Maintainable**: Clear separation of concerns
6. **Backward compatible**: Can keep devbox for transition

## Migration Path

1. ✅ Create `flake.nix` alongside existing `devbox.json`
2. ✅ Initialize Dagger with Python SDK
3. ✅ Implement Phase 1 (image building) in Dagger
4. ✅ Test both workflows work (nix + devbox)
5. ✅ Update docs to show both options
6. ✅ Gradually migrate users to Nix flakes
7. ✅ Eventually remove devbox (optional)

## Next Steps

Ready to implement this? I can:
1. Create the `flake.nix`
2. Initialize Dagger
3. Implement the Packer pipeline in Dagger
4. Update documentation

Or would you like to adjust the approach first?
