# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Devbox configuration for reproducible development environment
- Pre-commit hooks for automated linting (OpenTofu, Python, YAML, Markdown)
- MIT LICENSE file
- Comprehensive DEVELOPMENT.md with devbox setup guide
- GitHub Actions CI workflow for automated testing
- Three-layer OpenTofu structure (oci, proxmox-cluster, talos)
- Flux CD integration with SOPS encryption
- Separate Flux repository: [syscode-labs/oci-free-tier-flux](https://github.com/syscode-labs/oci-free-tier-flux)

### Changed
- Migrated from Terraform to OpenTofu
- Renamed `terraform/` to `tofu/oci/` for clearer structure
- Updated all documentation to reflect OpenTofu and 3-layer architecture
- Rewrote README.md with current quick start and architecture
- Consolidated and cleaned up documentation

### Removed
- Obsolete `k8s/` directory (Flux repository is now source of truth)
- Outdated Packer references from README
- Duplicate information across documentation files

### Fixed
- Documentation now accurately reflects actual code structure
- Consistent path references across all docs
- LICENSE file matches README claim

## [0.1.0] - 2024-11-13

### Added
- Initial release
- OCI availability checker Python script
- Basic Terraform configuration for OCI free tier
- Documentation for OCI Always Free resources
- Budget alert configuration

[Unreleased]: https://github.com/syscod3/oci-free-tier-manager/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/syscod3/oci-free-tier-manager/releases/tag/v0.1.0
