# OpenTofu State Backend - OCI Object Storage

This document explains the remote state backend configuration using OCI Object Storage (free tier).

## Why Remote State?

**Problem with local state:**
- Lost if machine crashes or repo deleted
- No collaboration (can't share state)
- No locking (concurrent modifications risk)

**OCI Object Storage benefits:**
- ✅ **Free tier**: 20GB storage (state files typically <1MB)
- ✅ **Versioning**: Built-in versioning for rollback
- ✅ **Durability**: 99.999999999% (11 9's) durability
- ✅ **Already using OCI**: No additional cloud providers
- ✅ **Cost**: $0 within free tier

## Setup Process

### Step 1: Bootstrap Backend

Run the bootstrap script to create the Object Storage bucket:

```bash
task state:setup
# Or manually:
./scripts/bootstrap-state-backend.sh
```

This will:
1. Create OCI Object Storage bucket: `tofu-state-oci-free-tier`
2. Enable versioning on the bucket
3. Generate pre-authenticated request (PAR) for access
4. Create `tofu/oci/backend-config.tfvars` with configuration

### Step 2: Configure Backend

Edit `tofu/oci/backend.tf` and uncomment the backend block:

```hcl
terraform {
  backend "http" {
    address        = "https://objectstorage.${var.region}.oraclecloud.com/n/${var.namespace}/b/tofu-state-oci-free-tier/o/terraform.tfstate"
    update_method  = "PUT"
    lock_address   = "https://objectstorage.${var.region}.oraclecloud.com/n/${var.namespace}/b/tofu-state-oci-free-tier/o/terraform.tfstate.lock"
    lock_method    = "PUT"
    unlock_address = "https://objectstorage.${var.region}.oraclecloud.com/n/${var.namespace}/b/tofu-state-oci-free-tier/o/terraform.tfstate.lock"
    unlock_method  = "DELETE"
  }
}
```

### Step 3: Migrate State

Migrate your existing local state to OCI Object Storage:

```bash
task state:migrate
# Or manually:
cd tofu/oci
tofu init -migrate-state
```

OpenTofu will prompt you to confirm the migration. Type `yes` to proceed.

## State Management Tasks

### View State

```bash
# List all resources
task state:list

# Show specific resource
cd tofu/oci
tofu state show oci_core_instance.ampere_instance[0]
```

### Backup State

```bash
# Create timestamped backup
task state:backup

# Download current state
task state:pull
```

### Restore State

If you need to restore from a backup:

```bash
cd tofu/oci

# Upload backup to replace current state
oci os object put \
  --bucket-name tofu-state-oci-free-tier \
  --file state-backup-20251122-120000.tfstate \
  --name terraform.tfstate \
  --force
```

## State Versioning

OCI Object Storage versioning is enabled, allowing you to recover previous state versions:

```bash
# List state versions
oci os object list-object-versions \
  --bucket-name tofu-state-oci-free-tier \
  --prefix terraform.tfstate

# Restore specific version
oci os object restore \
  --bucket-name tofu-state-oci-free-tier \
  --object-name terraform.tfstate \
  --version-id <version-id>
```

## State Locking

The HTTP backend provides basic locking using a lock file:
- Lock file: `terraform.tfstate.lock`
- Method: Create lock file before operations
- Cleanup: Delete lock file after operations

**Note:** This is optimistic locking (not distributed). For team collaboration, consider:
- Using OCI DynamoDB-compatible service for distributed locks
- Setting up Terraform Cloud/Enterprise
- Manual coordination (single operator)

## Pre-Authenticated Request (PAR) Expiry

PARs expire after 1 year. To regenerate:

```bash
task state:setup
# This creates a new PAR and updates backend-config.tfvars
```

## Troubleshooting

### Error: Failed to get state lock

**Cause:** Lock file exists from previous interrupted operation

**Solution:**
```bash
# Manually delete lock file
oci os object delete \
  --bucket-name tofu-state-oci-free-tier \
  --object-name terraform.tfstate.lock \
  --force

# Or force unlock via OpenTofu
cd tofu/oci
tofu force-unlock <lock-id>
```

### Error: Backend initialization failed

**Cause:** Backend configuration not uncommented or PAR expired

**Solution:**
1. Verify `backend.tf` is uncommented
2. Regenerate PAR: `task state:setup`
3. Re-initialize: `tofu init -reconfigure`

### State divergence detected

**Cause:** Local state differs from remote state

**Solution:**
```bash
# Pull latest state
task state:pull

# Or force refresh
cd tofu/oci
tofu init -reconfigure
tofu refresh
```

## Backup Strategy

**Automated backups:**
- OCI Object Storage versioning (automatic)
- Retention: Indefinite (within 20GB free tier)

**Manual backups:**
```bash
# Before major changes
task state:backup

# Store backup off-site (optional)
scp tofu/oci/state-backup-*.tfstate backup-server:/backups/
```

## Security Considerations

**State contains sensitive data:**
- Resource IDs
- Private IPs
- Configuration values (potentially secrets)

**Security measures:**
- Bucket is private (NoPublicAccess)
- Access via PAR (no public API keys)
- Versioning enabled (prevent data loss)
- Consider encrypting state at rest (OCI KMS)

**To enable encryption:**
```bash
oci os bucket update \
  --bucket-name tofu-state-oci-free-tier \
  --kms-key-id <kms-key-ocid>
```

## Migration Back to Local State

If you need to move back to local state:

```bash
cd tofu/oci

# Comment out backend block in backend.tf
# Then:
tofu init -migrate-state

# Confirm migration to local backend
```

## Cost Monitoring

State storage is within free tier, but monitor usage:

```bash
# Check bucket size
oci os bucket get \
  --bucket-name tofu-state-oci-free-tier \
  --query 'data."approximate-size"'

# List all objects and sizes
oci os object list \
  --bucket-name tofu-state-oci-free-tier \
  --fields size,timeCreated
```

**Free tier limit:** 20GB (state files + versions)  
**Typical usage:** <10MB total (including all versions)

## References

- [OCI Object Storage Docs](https://docs.oracle.com/en-us/iaas/Content/Object/home.htm)
- [OpenTofu HTTP Backend](https://opentofu.org/docs/language/settings/backends/http/)
- [OCI Free Tier Details](https://www.oracle.com/cloud/free/)
