/*
 * OpenTofu Backend Configuration - OCI Object Storage
 *
 * This configures remote state storage using OCI Object Storage (free tier).
 * The backend uses OCI's S3-compatible API with native OpenTofu lockfiles.
 *
 * Benefits:
 * - Free tier: 20GB storage (state files typically <1MB)
 * - Versioning: Object Storage versioning enabled for rollback
 * - Durability: 99.999999999% (11 9's) durability
 * - Locking: OpenTofu native S3 lockfile (`use_lockfile = true`)
 *
 * Setup required before use:
 * 1. Ensure the state bucket exists and versioning is enabled.
 * 2. Provide private S3-compatible backend config out-of-repo.
 * 3. Run: tofu init -reconfigure -backend-config=/path/to/backend-s3.tfvars
 */

terraform {
  backend "s3" {}
}
