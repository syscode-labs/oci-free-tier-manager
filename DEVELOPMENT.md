# Development Environment Setup

This project uses **Devbox** with Nix for reproducible development environments. All tools are versioned and isolated.

## Prerequisites

Install Devbox (one-time setup):

```bash
# macOS/Linux
curl -fsSL https://get.jetpack.io/devbox | bash

# Or with Homebrew
brew install jetpack-io/tap/devbox
```

## Quick Start

```bash
# Enter development environment (automatically installs all tools)
devbox shell

# That's it! All tools are now available:
#   - opentofu, kubectl, helm, sops, age
#   - pre-commit, yamllint, tflint, shellcheck
#   - python, jq, yq, gh
```

## Available Tools

All tools are automatically installed when you run `devbox shell`:

| Tool | Version | Purpose |
|------|---------|---------|
| `opentofu` | latest | Infrastructure as Code |
| `kubectl` | latest | Kubernetes CLI |
| `helm` | latest | Kubernetes package manager |
| `sops` | latest | Secrets encryption |
| `age` | latest | Encryption for SOPS |
| `pre-commit` | latest | Git hooks for linting |
| `tflint` | latest | OpenTofu linter |
| `terraform-docs` | latest | Generate OpenTofu docs |
| `yamllint` | latest | YAML linter |
| `shellcheck` | latest | Shell script linter |
| `markdownlint-cli` | latest | Markdown linter |
| `python312` | 3.12 | Python runtime |
| `jq` | latest | JSON processor |
| `yq` | latest | YAML processor |
| `gh` | latest | GitHub CLI |

## Pre-commit Hooks

Pre-commit hooks are automatically installed when you enter the devbox shell.

### Manual Installation

```bash
# Install hooks
pre-commit install

# Run hooks on all files
pre-commit run --all-files

# Run hooks on staged files only
pre-commit run
```

### Available Hooks

- **OpenTofu**: formatting, validation, linting, documentation
- **Python**: Black formatting, Flake8 linting
- **YAML**: yamllint
- **Markdown**: markdownlint
- **Shell**: shellcheck
- **Secrets**: detect-secrets
- **Commit messages**: Conventional Commits format

## Devbox Commands

Devbox provides convenient commands for common tasks:

```bash
# Format all code
devbox run fmt

# Run all linters
devbox run lint

# Validate OpenTofu
devbox run check
```

## Manual Tool Usage

### OpenTofu

```bash
cd tofu/oci
tofu init
tofu plan
tofu apply
```

### SOPS + Age

```bash
# Generate Age key
age-keygen -o secrets/age-key.txt

# Encrypt file
sops --encrypt secret.yaml > secret.enc.yaml

# Decrypt file
sops --decrypt secret.enc.yaml

# Edit encrypted file
sops secret.enc.yaml
```

### Helm

```bash
# Add repo
helm repo add cilium https://helm.cilium.io/
helm repo update

# Generate manifest
helm template cilium cilium/cilium \
  --version 1.16.5 \
  --namespace kube-system \
  --values values.yaml \
  > manifest.yaml
```

## Environment Variables

Devbox automatically sets:

- `KUBECONFIG=$PWD/.kube/config` - Kubernetes config path
- `SOPS_AGE_KEY_FILE=$PWD/secrets/age-key.txt` - SOPS encryption key

## Directory Structure

```
.
├── devbox.json                 # Devbox configuration
├── .pre-commit-config.yaml     # Pre-commit hooks
├── .tflint.hcl                 # OpenTofu linting rules
├── .terraform-docs.yml         # Documentation generator config
├── .markdownlint.json          # Markdown linting rules
├── .secrets.baseline           # Secrets detection baseline
├── tofu/                       # OpenTofu infrastructure
│   ├── oci/                    # Layer 1: OCI resources
│   ├── proxmox-cluster/        # Layer 2: Proxmox cluster
│   └── talos/                  # Layer 3: Talos K8s
└── secrets/                    # Local secrets (gitignored)
    └── age-key.txt             # SOPS encryption key
```

## Updating Tools

```bash
# Update all tools to latest versions
devbox update

# Update specific tool
devbox add opentofu@latest --force
```

## Troubleshooting

### "Command not found" after entering devbox shell

Exit and re-enter the shell:

```bash
exit
devbox shell
```

### Pre-commit hooks failing

Update pre-commit hooks:

```bash
pre-commit autoupdate
pre-commit install --install-hooks
```

### OpenTofu/Terraform issues

Ensure you're using OpenTofu, not Terraform:

```bash
which tofu  # Should show: /nix/store/.../bin/tofu
tofu version
```

## IDE Integration

### VS Code

Install the Dev Containers extension and Devbox will work automatically.

### JetBrains IDEs

1. Enter devbox shell
2. Launch IDE from within the shell: `code .` or `idea .`

## CI/CD Integration

Pre-commit hooks run automatically on commit. GitHub Actions can also use devbox:

```yaml
- name: Setup Devbox
  uses: jetpack-io/devbox-install-action@v0.7.0

- name: Run linters
  run: devbox run lint
```

## Why Devbox + Nix?

- ✅ **Reproducible**: Same tools, same versions, everywhere
- ✅ **Isolated**: No conflicts with system packages
- ✅ **Fast**: Tools are cached, no repeated downloads
- ✅ **Cross-platform**: Works on macOS, Linux, WSL
- ✅ **No Docker**: Lighter than devcontainers
- ✅ **Declarative**: Tools defined in `devbox.json`

## Alternative: Without Devbox

If you prefer manual installation:

```bash
brew install opentofu kubectl helm sops age pre-commit \
  tflint terraform-docs yamllint shellcheck markdownlint-cli \
  python@3.12 jq yq gh
```

But you'll need to manage versions manually.

## References

- [Devbox Documentation](https://www.jetpack.io/devbox/docs/)
- [Pre-commit Documentation](https://pre-commit.com/)
- [OpenTofu Documentation](https://opentofu.org/)
- [SOPS Documentation](https://github.com/getsops/sops)
