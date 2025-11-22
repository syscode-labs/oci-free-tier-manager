#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Setup Branch Protection Rules
#
# This script configures branch protection for the main branch using GitHub CLI.
#
# Prerequisites:
# - GitHub CLI installed (brew install gh)
# - Authenticated with GitHub (gh auth login)
# - Admin access to the repository
#
# Usage:
#   ./scripts/setup-branch-protection.sh
###############################################################################

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    log_error "GitHub CLI not found. Install it: brew install gh"
    exit 1
fi

# Check if authenticated
if ! gh auth status &>/dev/null; then
    log_error "Not authenticated with GitHub. Run: gh auth login"
    exit 1
fi

REPO="syscode-labs/oci-free-tier-manager"

log_info "Setting up branch protection for $REPO"
echo

# Create branch protection rule for main
log_info "Configuring main branch protection..."

gh api "repos/$REPO/branches/main/protection" \
  --method PUT \
  --input - <<'EOF'
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
  "required_conversation_resolution": true,
  "block_creations": false,
  "lock_branch": false,
  "allow_fork_syncing": true
}
EOF

if [ $? -eq 0 ]; then
    log_info "✓ Branch protection configured for main"
else
    log_error "Failed to configure branch protection"
    exit 1
fi

echo
log_info "Branch protection summary:"
log_info "  ✓ Force push: BLOCKED"
log_info "  ✓ Branch deletion: BLOCKED"
log_info "  ✓ Required CI checks: Lint & Validate"
log_info "  ✓ Linear history: REQUIRED"
log_info "  ✓ Conversation resolution: REQUIRED"
log_info "  ✓ Admin bypass: DISABLED"
echo

log_info "Setup complete! 🎉"
log_info ""
log_info "From now on:"
log_info "  1. Create feature branches for changes"
log_info "  2. Push and create pull requests"
log_info "  3. Wait for CI to pass"
log_info "  4. Merge via GitHub UI (squash recommended)"
echo

log_warn "Note: You cannot push directly to main anymore"
log_warn "Use: git checkout -b feat/my-feature && git push origin feat/my-feature"
