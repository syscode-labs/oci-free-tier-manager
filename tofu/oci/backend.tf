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

# UNCOMMENT AFTER RUNNING BOOTSTRAP SCRIPT
# terraform {
#   backend "http" {
#     address        = "https://objectstorage.${var.region}.oraclecloud.com/n/${var.namespace}/b/${var.state_bucket_name}/o/terraform.tfstate"
#     update_method  = "PUT"
#     lock_address   = "https://objectstorage.${var.region}.oraclecloud.com/n/${var.namespace}/b/${var.state_bucket_name}/o/terraform.tfstate.lock"
#     lock_method    = "PUT"
#     unlock_address = "https://objectstorage.${var.region}.oraclecloud.com/n/${var.namespace}/b/${var.state_bucket_name}/o/terraform.tfstate.lock"
#     unlock_method  = "DELETE"
#   }
# }

# Alternative: S3-compatible backend (requires pre-authenticated request)
# terraform {
#   backend "s3" {
#     bucket                      = "tofu-state"
#     key                         = "oci/terraform.tfstate"
#     region                      = "us-phoenix-1"
#     skip_region_validation      = true
#     skip_credentials_validation = true
#     skip_metadata_api_check     = true
#     endpoint                    = "https://NAMESPACE.compat.objectstorage.REGION.oraclecloud.com"
#
#     # Uses AWS signature V4 with OCI Customer Secret Keys
#     access_key = var.oci_s3_access_key
#     secret_key = var.oci_s3_secret_key
#   }
# }
