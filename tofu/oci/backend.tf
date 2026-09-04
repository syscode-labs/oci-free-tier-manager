/*
 * OpenTofu Backend Configuration - OCI Object Storage
 *
 * This configures remote state storage using OCI Object Storage's
 * S3-compatible API (free tier).
 *
 * Benefits:
 * - Free tier: 20GB storage (state files typically <1MB)
 * - Versioning: Object Storage versioning enabled for rollback
 * - Durability: 99.999999999% (11 9's) durability
 * - Locking: S3 lockfile support prevents concurrent state changes
 *
 * Setup required before use:
 * 1. Run bootstrap script: ./scripts/bootstrap-state-backend.sh
 * 2. Run: tofu init -backend-config=/private/path/backend-config.tfvars
 */

terraform {
  backend "s3" {}
}
