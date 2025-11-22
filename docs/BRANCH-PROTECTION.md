# Branch Protection Rules

This document describes the recommended branch protection rules for this repository.

## Recommended Settings

### Main Branch Protection

Navigate to: **Settings → Branches → Add branch protection rule**

**Branch name pattern:** `main`

### Required Settings

#### ✅ Require a pull request before merging
- **Require approvals:** 0 (single maintainer) or 1+ (team)
- **Dismiss stale pull request approvals when new commits are pushed:** ✅
- **Require review from Code Owners:** ❌ (optional for teams)

#### ✅ Require status checks to pass before merging
- **Require branches to be up to date before merging:** ✅
- **Required status checks:**
  - `Lint & Validate` (from CI workflow)
  - `Validate Kubernetes Manifests` (from flux repo CI)

#### ✅ Require conversation resolution before merging
Ensures all review comments are addressed

#### ✅ Require signed commits (optional, recommended)
Ensures commits are cryptographically verified

#### ✅ Require linear history (recommended)
- Prevents merge commits
- Keeps history clean
- Requires rebase or squash merges

#### ✅ Do not allow bypassing the above settings
Applies rules to administrators too

#### ❌ Allow force pushes
**Disabled** - prevents history rewriting

#### ❌ Allow deletions
**Disabled** - prevents accidental branch deletion

## Quick Setup via GitHub CLI

```bash
# Install GitHub CLI if not already installed
brew install gh

# Authenticate
gh auth login

# Create branch protection rule
gh api repos/syscode-labs/oci-free-tier-manager/branches/main/protection \
  --method PUT \
  --input - <<EOF
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["Lint & Validate"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
EOF
```

## Alternative: Manual Setup via GitHub UI

1. Go to repository **Settings**
2. Click **Branches** in the left sidebar
3. Under "Branch protection rules", click **Add rule**
4. Enter `main` as the branch name pattern
5. Enable the checkboxes as described above
6. Click **Create** or **Save changes**

## For Multi-Repository Setup

Apply the same rules to the flux repository:

```bash
# Branch protection for flux repo
gh api repos/syscode-labs/oci-free-tier-flux/branches/main/protection \
  --method PUT \
  --input - <<EOF
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["Validate Kubernetes Manifests"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
EOF
```

## Workflow

With branch protection enabled:

### Feature Development
```bash
# Create feature branch
git checkout -b feat/my-feature

# Make changes and commit
git add .
git commit -m "feat: add new feature"

# Push to GitHub
git push origin feat/my-feature

# Create PR via GitHub UI or CLI
gh pr create --title "feat: add new feature" --body "Description"

# CI runs automatically
# - If checks pass: PR can be merged
# - If checks fail: Fix issues and push again

# Merge via GitHub UI (squash recommended)
# Or via CLI:
gh pr merge --squash
```

### Hotfix (if admin bypass needed)
```bash
# Only for critical fixes when CI is broken
# Requires admin permissions and bypass setting disabled

# Make fix
git add .
git commit -m "hotfix: critical security patch"

# Push directly (will fail if protection is strict)
git push origin main

# Alternative: Use PR with admin override
gh pr create --title "hotfix: critical" --body "Emergency fix"
# Admin can force merge despite failed checks
```

## Benefits

### 🛡️ Prevents Mistakes
- No accidental force pushes
- No accidental branch deletion
- No broken code in main

### ✅ Code Quality
- All code passes CI before merge
- Terraform validates before deployment
- Python lints before commit

### 📜 Clean History
- Linear history (no merge commits)
- Easy to bisect bugs
- Clear change timeline

### 🔒 Security
- Signed commits verify author identity
- Required reviews catch vulnerabilities
- Status checks prevent broken deploys

## Troubleshooting

### CI check not appearing as required

**Cause:** Status check name mismatch

**Solution:**
1. Check exact job name in `.github/workflows/ci.yml`
2. Run workflow once to register the check
3. Update branch protection with exact name

### Can't push to main directly

**Cause:** Branch protection is working as intended

**Solution:**
1. Create feature branch: `git checkout -b feat/my-change`
2. Push branch and create PR
3. Wait for CI to pass
4. Merge via GitHub UI

### Need emergency access

**Cause:** Critical hotfix needed, CI broken

**Solution (requires admin):**
1. Temporarily disable "Do not allow bypassing"
2. Push fix directly
3. Re-enable protection immediately

### Status check stuck pending

**Cause:** CI workflow not triggered or failed

**Solution:**
```bash
# Re-trigger workflow
gh workflow run ci.yml

# Or push empty commit
git commit --allow-empty -m "chore: retrigger CI"
git push
```

## References

- [GitHub Branch Protection Docs](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
- [GitHub CLI Reference](https://cli.github.com/manual/gh_api)
- [Required Status Checks](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches#require-status-checks-before-merging)
