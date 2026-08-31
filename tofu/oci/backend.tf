/*
 * OpenTofu Backend Configuration - OCI Object Storage
 *
 * This configures remote state storage using OCI Object Storage (free tier).
 * The backend uses HTTP protocol with OCI pre-authenticated requests.
 *
 * Benefits:
 * - Free tier: 20GB storage (state files typically <1MB)
 * - Versioning: Object Storage versioning enabled for rollback
 * - Durability: 99.999999999% (11 9's) durability
 * - No lock file: Single-user workflow (add locking if needed)
 *
 * Setup required before use:
 * 1. Run bootstrap script: ./scripts/bootstrap-state-backend.sh
 * 2. Uncomment the backend block below
 * 3. Run: tofu init -migrate-state
 */

terraform {
  backend "s3" {}
}
