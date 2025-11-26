# AGENTS.md

> Context file for AI coding agents (OpenAI Codex, Claude Code, Cursor, Gemini CLI, Aider, etc.)
>
> This file provides essential context, commands, and conventions for working with this codebase.
> For detailed architectural information, see [WARP.md](WARP.md) and [docs/](docs/).

## Project Summary

**OCI Free Tier Manager** - Production-ready Kubernetes on Oracle Cloud's Always Free tier ($0 cost).

- **Stack**: OpenTofu + Proxmox VE + Talos Linux + Flux CD
- **Compute**: 3× Ampere A1 (ARM64, 4 OCPUs/24GB total) + 1× E2.1.Micro (x86, bastion)
- **Architecture**: 3-layer OpenTofu (OCI → Proxmox → Talos K8s)
- **GitOps**: Flux CD with SOPS-encrypted secrets
- **Networking**: Tailscale mesh, Cilium CNI (kube-proxy-free)
- **Cost**: $0 (budget alert at $0.01 threshold)

**Status**: Layer 1 (OCI) ✅ Implemented | Layers 2-3 (Proxmox/Talos) 🚧 Planned

## Essential Commands

### Development Environment

```bash
# Enter devbox shell (installs all tools automatically)
devbox shell

# Run setup (OCI CLI + SSH keys + tfvars)
task setup

# Setup Flux repository
task setup:flux
```

### Build & Deploy

```bash
# Build custom images (one-time)
task build:images      # Builds base-hardened + proxmox-ampere
task build:validate    # Validates < 20GB total
task build:upload      # Uploads to OCI Object Storage

# Deploy infrastructure (3 layers)
task deploy:oci        # Layer 1: OCI instances ✅
task deploy:proxmox    # Layer 2: Proxmox + Ceph 🚧
task deploy:talos      # Layer 3: Talos K8s 🚧

# Deploy all layers
task deploy:all
```

### OpenTofu Workflow

```bash
# ALWAYS run these before committing Terraform changes
cd tofu/oci
tofu fmt              # Format files
tofu validate         # Validate syntax
tflint                # Lint
tfsec .               # Security scan
checkov -d .          # Policy scan

# Standard workflow
tofu init             # Initialize
tofu plan             # Preview
tofu apply            # Deploy
tofu destroy          # Destroy
```

### Security Scans

```bash
# Run all security scans
task security

# Individual scans
task security:terraform  # tfsec + Checkov
task security:python     # Bandit

# CI runs these automatically
```

### State Management

```bash
# Setup OCI Object Storage backend (one-time)
task state:setup

# Migrate local state to remote
task state:migrate

# Backup state
task state:backup

# List resources
task state:list
```

### Validation

```bash
# Run all validation checks
task validate

# Check OCI capacity
./check_availability.py

# Validate specific phases
task validate:images
task validate:oci
task validate:cost
```

## File Structure

```
.
├── AGENTS.md                 # ← You are here (AI agent context)
├── WARP.md                   # Detailed architecture reference
├── README.md                 # Human-facing documentation
├── Taskfile.yml              # Task automation (use `task` not raw commands)
├── devbox.json               # Nix-based dev environment
│
├── check_availability.py     # OCI capacity checker
│
├── tofu/                     # OpenTofu infrastructure (3 layers)
│   ├── oci/                  # Layer 1: OCI compute/network ✅
│   │   ├── main.tf           # VCN, instances, storage, budgets
│   │   ├── variables.tf      # With validation blocks
│   │   ├── data.tf           # Availability domains, images
│   │   ├── outputs.tf        # IPs, SSH commands
│   │   ├── backend.tf        # OCI Object Storage state backend
│   │   ├── .tflint.hcl       # tflint configuration
│   │   ├── .tfsec.yml        # tfsec security config
│   │   └── .checkov.yml      # Checkov policy config
│   ├── proxmox-cluster/      # Layer 2: Proxmox + Ceph 🚧
│   └── talos/                # Layer 3: Talos VMs + K8s 🚧
│
├── scripts/                  # Automation scripts
│   ├── setup.sh              # Initial OCI setup
│   ├── bootstrap-state-backend.sh  # State backend setup
│   └── setup-branch-protection.sh  # GitHub protection
│
└── docs/                     # Documentation
    ├── ARCHITECTURE-DIAGRAMS.md    # Mermaid diagrams
    ├── STATE-BACKEND.md           # Remote state guide
    ├── SECURITY-SCANNING.md       # Security tools
    └── BRANCH-PROTECTION.md       # Git workflow
```

## Coding Conventions

### Terraform/OpenTofu

**CRITICAL**: Always run before committing:
```bash
tofu fmt && tofu validate && tflint && tfsec .
```

- **Style**: Use `snake_case` for all resource names
- **Comments**: File-level comment blocks (`/* */`) explaining purpose
- **Variables**: All variables must have:
  - `description`
  - `type` constraint
  - `validation` block (where applicable)
- **Locals**: Use `locals.tf` for complex expressions
- **Data**: Use `data.tf` for data sources
- **Outputs**: Document all outputs with `description`
- **State**: Backend configured in `backend.tf` (commented out by default)

**Example variable:**
```hcl
variable "ampere_instance_count" {
  description = "Number of Ampere A1 instances (ARM64)"
  type        = number
  default     = 3
  
  validation {
    condition     = var.ampere_instance_count >= 0 && var.ampere_instance_count <= 4
    error_message = "Must be between 0 and 4 (free tier limit: 4 OCPUs total)."
  }
}
```

### Python

- **Linting**: `black` (formatter) + `flake8` (linter) + `bandit` (security)
- **Line length**: 120 characters max
- **Docstrings**: Required for all functions
- **Exit codes**: 0 = success, non-zero = failure
- **OCI paths**: Use `~/.oci/config` (hardcoded path in `check_availability.py:149`)

### Shell Scripts

- **Shebang**: `#!/usr/bin/env bash`
- **Strict mode**: `set -euo pipefail`
- **Linting**: `shellcheck` required
- **Colors**: Use ANSI escape codes (see `scripts/bootstrap-state-backend.sh`)

### Git Workflow

**Branch protection is ENABLED on main**. You MUST use feature branches:

```bash
# Create feature branch
git checkout -b feat/my-feature

# Commit with conventional commits
git commit -m "feat: add something" -m "Detailed description"

# Push and create PR
git push origin feat/my-feature
gh pr create

# Wait for CI to pass (required: Lint & Validate)
# Merge via GitHub UI (squash merge recommended)
```

**Conventional commits format:**
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation
- `chore:` - Maintenance
- `refactor:` - Code refactoring
- `test:` - Tests
- `ci:` - CI/CD changes

**Commit structure:**
```bash
git commit -m "type: short summary" \
  -m "Detailed explanation line 1" \
  -m "Detailed explanation line 2"
```

### Markdown

- **Diagrams**: Use Mermaid with explicit white text styling:
  ```markdown
  %%{init: {'theme':'base', 'themeVariables': {'textColor':'#fff'}}}%%
  ```
- **Code blocks**: Always specify language
- **Links**: Use relative paths for internal docs
- **Line width**: 120 characters (soft limit)

## Testing

### Terraform Tests

```bash
# Format check
tofu fmt -check -recursive

# Validate
tofu init -backend=false
tofu validate

# Lint
tflint --init
tflint --format compact

# Security scan
tfsec . --minimum-severity MEDIUM

# Policy scan
checkov -d . --framework terraform --compact
```

### Python Tests

```bash
# Lint
black --check check_availability.py
flake8 check_availability.py --max-line-length=120

# Security scan
bandit -r . -ll
```

### Integration Tests

```bash
# Validate infrastructure (after deployment)
task validate:oci
task validate:cost
```

## Security

### Sensitive Files (Never Commit)

```
*.pem
*.key
terraform.tfvars
backend-config.tfvars
age-key.txt
.env*
secrets/
```

### Security Scanning (CI Enforced)

- **tfsec**: Fails on MEDIUM+ severity
- **Checkov**: Informational (soft-fail)
- **tflint**: Fails on errors
- **Bandit**: Informational

### Known Exclusions

These security findings are **intentional** and safe:
- Public IPs on instances (needed for SSH/HTTP)
- No customer-managed encryption keys (not in free tier)
- Security list allows specific ports (22, 80, 443, ICMP)

See `tofu/oci/.tfsec.yml` and `.checkov.yml` for configurations.

## Free Tier Limits (NEVER EXCEED)

### Compute
- **Ampere A1**: 4 OCPUs + 24GB RAM total (flexible distribution)
- **E2.1.Micro**: 2 instances × 1/8 OCPU + 1GB RAM (fixed)

### Storage
- **Block volumes**: 200GB total (includes ALL boot volumes)
- **Object storage**: 20GB
- **Archive storage**: 10GB

### Networking
- **VCNs**: 2
- **Load balancer**: 1 (10 Mbps)
- **Reserved IPs**: 2
- **Egress**: 10TB/month

### Safety Checks

Before deploying, verify:
```bash
# Total storage calculation
(ampere_count × ampere_boot_size) + (micro_count × micro_boot_size) ≤ 200GB

# Total compute
ampere_count × ampere_ocpus ≤ 4
ampere_count × ampere_memory ≤ 24GB
micro_count ≤ 2
```

**Budget alert at $0.01** will catch any charges immediately.

## Common Tasks

### Add New Terraform Resource

1. Add resource to appropriate file in `tofu/oci/`
2. Run `tofu fmt`
3. Run `tofu validate`
4. Run `tflint` and fix issues
5. Run `tfsec .` and fix/exclude issues
6. Run `checkov -d .` and review findings
7. Commit with conventional format
8. Create PR (branch protection enforced)

### Modify Python Script

1. Make changes to `check_availability.py`
2. Run `black check_availability.py`
3. Run `flake8 check_availability.py`
4. Run `bandit -r .`
5. Test manually: `./check_availability.py`
6. Commit and create PR

### Add Documentation

1. Create/edit Markdown file in `docs/`
2. Add Mermaid diagrams with white text styling
3. Link from README.md or AGENTS.md
4. Commit with `docs:` prefix

### Deploy Infrastructure

1. Check capacity: `./check_availability.py`
2. Review plan: `task deploy:oci:plan`
3. Deploy: `task deploy:oci`
4. Validate: `task validate:oci`
5. Check costs: `task validate:cost`

## Troubleshooting

### "Can't push to main"
Branch protection is enabled. Use feature branches:
```bash
git checkout -b feat/my-feature
git push origin feat/my-feature
gh pr create
```

### "tfsec failing in CI"
Run locally first:
```bash
cd tofu/oci
tfsec . --minimum-severity MEDIUM
```
Fix issues or add exclusions to `.tfsec.yml`.

### "Ampere instances unavailable"
This is normal. Run availability checker:
```bash
./check_availability.py
# Or automate with cron
```

### "State backend error"
Setup remote state backend:
```bash
task state:setup
# Edit tofu/oci/backend.tf (uncomment backend block)
task state:migrate
```

### "Budget alert triggered"
Investigate immediately:
```bash
# Check OCI billing
oci usage api-usage summarize-usages --tenant-id <id>

# Review resources
cd tofu/oci && tofu state list
```

## Related Files

- **[WARP.md](WARP.md)**: Complete architecture reference (comprehensive)
- **[README.md](README.md)**: Human-facing project documentation
- **[DEVELOPMENT.md](DEVELOPMENT.md)**: Dev environment setup
- **[docs/ARCHITECTURE-DIAGRAMS.md](docs/ARCHITECTURE-DIAGRAMS.md)**: Visual diagrams
- **[docs/SECURITY-SCANNING.md](docs/SECURITY-SCANNING.md)**: Security tools guide
- **[docs/STATE-BACKEND.md](docs/STATE-BACKEND.md)**: Remote state setup
- **[docs/BRANCH-PROTECTION.md](docs/BRANCH-PROTECTION.md)**: Git workflow

## External Resources

- **Flux Repository**: https://github.com/syscode-labs/oci-free-tier-flux
- **OCI Free Tier**: https://www.oracle.com/cloud/free/
- **OpenTofu Docs**: https://opentofu.org/docs/
- **Talos Linux**: https://www.talos.dev/
- **Flux CD**: https://fluxcd.io/

## Agent-Specific Notes

### For all agents

- Use `task <command>` instead of raw bash/tofu commands
- Always run fmt/validate before committing Terraform
- Follow conventional commits format
- Branch protection enforced - use feature branches
- Security scans run in CI - check locally first

### Context hierarchy

1. Explicit user prompt (highest priority)
2. This AGENTS.md file
3. WARP.md (detailed architecture)
4. Files in working directory
5. docs/ directory

### When editing Terraform

Run this sequence BEFORE committing:
```bash
cd tofu/oci
tofu fmt
tofu validate
tflint
tfsec . --minimum-severity MEDIUM
checkov -d . --framework terraform --compact
```

### When creating PRs

CI enforces these checks:
- Lint & Validate (required to merge)
- Python linting (flake8, black)
- Terraform validation (fmt, validate, tflint)
- Security scanning (tfsec, Checkov)
- Deprecated API checks (Pluto)

All checks must pass before merge.

---

**Last updated**: 2025-11-22
**Format**: AGENTS.md standard (agents.md, agentsmd.io)
**Compatible with**: OpenAI Codex, Claude Code, Cursor, Gemini CLI, Aider, Google Jules
