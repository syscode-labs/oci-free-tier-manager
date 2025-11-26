# Security Scanning

This project uses multiple security scanning tools to detect vulnerabilities, misconfigurations, and security issues.

## Tools Used

### 🔍 Terraform/OpenTofu Security

#### 1. **tfsec** (Aqua Security)
Static analysis scanner for Terraform/OpenTofu code.

**What it checks:**
- Encryption at rest and in transit
- Network security (security groups, public access)
- IAM permissions and policies
- Logging and monitoring
- Resource configurations

**Website:** https://aquasecurity.github.io/tfsec/

#### 2. **Checkov** (Bridgecrew/Palo Alto)
Policy-as-code scanner with 1000+ built-in policies.

**What it checks:**
- Cloud security best practices (OCI, AWS, Azure, GCP)
- Kubernetes misconfigurations
- Secrets in code
- Supply chain security
- Custom policies support

**Website:** https://www.checkov.io/

#### 3. **tflint**
Linter for Terraform with OCI provider support.

**What it checks:**
- Syntax errors
- Deprecated syntax
- Naming conventions
- Unused declarations
- Provider-specific rules

**Website:** https://github.com/terraform-linters/tflint

### 🐍 Python Security

#### **Bandit** (PyCQA)
Security linter for Python code.

**What it checks:**
- SQL injection vulnerabilities
- Hardcoded passwords/secrets
- Insecure cryptography
- Shell injection
- Unsafe YAML/XML parsing

**Website:** https://bandit.readthedocs.io/

## Running Scans Locally

### All Security Scans
```bash
task security
```

### Terraform Only
```bash
task security:terraform
# Or manually:
cd tofu/oci
tfsec .
checkov -d .
```

### Python Only
```bash
task security:python
# Or manually:
bandit -r . -ll
```

## CI/CD Integration

Security scans run automatically on every push and pull request via GitHub Actions (`.github/workflows/ci.yml`):

1. **tfsec** - Fails build on MEDIUM+ severity issues
2. **Checkov** - Reports issues but doesn't fail build (soft-fail mode)
3. **tflint** - Fails on linting errors
4. **Pluto** - Warns on deprecated Kubernetes APIs

## Configuration Files

### tfsec Configuration
**File:** `tofu/oci/.tfsec.yml`

```yaml
minimum_severity: MEDIUM
exclude:
  - oracle-compute-no-public-ip  # We need public IPs
  - oracle-storage-encryption-customer-key  # Not in free tier
```

### Checkov Configuration
**File:** `tofu/oci/.checkov.yml`

```yaml
skip-check:
  - CKV_OCI_2  # Public IP (intentional)
  - CKV_OCI_5  # Customer-managed keys (not available)
```

### tflint Configuration
**File:** `tofu/oci/.tflint.hcl`

```hcl
plugin "oci" {
  enabled = true
  version = "0.7.0"
}
```

## Common Issues and Fixes

### Issue: Public IP on instances

**Finding:** `oracle-compute-no-public-ip`  
**Severity:** MEDIUM  
**Why we skip:** We need public IPs for SSH access and services

**Fix:** Added to exclusions in `.tfsec.yml`

### Issue: No encryption with customer-managed keys

**Finding:** `CKV_OCI_5`  
**Severity:** HIGH  
**Why we skip:** Customer-managed encryption keys not available in free tier

**Fix:** Added to skip list in `.checkov.yml`

### Issue: Security list allows all inbound traffic

**Finding:** `CKV2_OCI_1`  
**Severity:** MEDIUM  
**Why we skip:** We restrict to specific ports (22, 80, 443)

**Fix:** Security list already restricts ports, false positive

### Issue: No block volume backup policy

**Finding:** `CKV_OCI_7`  
**Severity:** LOW  
**Why we skip:** Optional for testing/dev environment

**Fix:** Can enable in production, skipped for now

## Security Best Practices

### ✅ What We Do

1. **Network Security**
   - Security lists restrict access to specific ports
   - HTTPS/TLS for sensitive traffic
   - Private subnets where possible

2. **Access Control**
   - SSH key authentication (no passwords)
   - Minimal IAM permissions
   - Budget alerts for anomaly detection

3. **Encryption**
   - Boot volumes encrypted by default (OCI managed keys)
   - HTTPS for web services
   - Encrypted secrets (SOPS + Age in Flux repo)

4. **Monitoring**
   - Budget alerts at $0.01 threshold
   - Grafana Cloud monitoring
   - Audit logging enabled

### 🔒 Additional Hardening (Optional)

1. **Enable OCI KMS encryption:**
```bash
oci os bucket update \
  --bucket-name tofu-state-oci-free-tier \
  --kms-key-id <kms-key-ocid>
```

2. **Enable VCN flow logs:**
```hcl
resource "oci_core_vcn_flow_log" "free_tier_flow_log" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.free_tier_vcn.id
}
```

3. **Add Cloud Guard (if available in free tier):**
```hcl
resource "oci_cloud_guard_target" "free_tier_target" {
  compartment_id       = var.compartment_ocid
  display_name         = "free-tier-target"
  target_resource_id   = var.compartment_ocid
  target_resource_type = "COMPARTMENT"
}
```

## False Positives

Some findings are expected and safe for this use case:

| Check | Reason | Safe? |
|-------|--------|-------|
| Public IPs | Need SSH/HTTP access | ✅ Yes |
| No WAF | Free tier limitation | ✅ Yes |
| No DDoS protection | Free tier limitation | ✅ Yes |
| Basic security list rules | Restricted to specific ports | ✅ Yes |

## Reporting Security Issues

If you find a security vulnerability:

1. **DO NOT** open a public issue
2. Email: security@syscode-labs.com (or your email)
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if known)

## Tool Installation

### macOS
```bash
# tfsec
brew install tfsec

# Checkov
pip install checkov

# tflint (already installed)
brew install tflint

# Bandit
pip install bandit
```

### Linux
```bash
# tfsec
curl -L https://github.com/aquasecurity/tfsec/releases/latest/download/tfsec-linux-amd64 -o tfsec
chmod +x tfsec
sudo mv tfsec /usr/local/bin/

# Checkov
pip install checkov

# Bandit
pip install bandit
```

## CI Status

Security scans are required to pass before merging:

- ✅ **tfsec**: Must pass (no MEDIUM+ issues)
- ⚠️ **Checkov**: Informational (soft-fail)
- ✅ **tflint**: Must pass
- ⚠️ **Pluto**: Informational (deprecated APIs)

## References

- [tfsec Documentation](https://aquasecurity.github.io/tfsec/latest/)
- [Checkov Documentation](https://www.checkov.io/documentation/)
- [tflint Documentation](https://github.com/terraform-linters/tflint)
- [Bandit Documentation](https://bandit.readthedocs.io/)
- [OCI Security Best Practices](https://docs.oracle.com/en-us/iaas/Content/Security/Reference/oci_security.htm)
