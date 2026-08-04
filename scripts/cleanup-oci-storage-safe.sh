#!/usr/bin/env bash
set -euo pipefail

: "${OCI_PROFILE:=DEFAULT}"
: "${OCI_COMPARTMENT:?OCI_COMPARTMENT is required}"
: "${OCI_NAMESPACE:?OCI_NAMESPACE is required}"
: "${OCI_BUCKET:?OCI_BUCKET is required}"
: "${DRY_RUN:=true}"
: "${KEEP_DAYS:=2}"
: "${BOOTVOL_GRACE_HOURS:=6}"
: "${OCI_TIMEOUT_SEC:=60}"
: "${OCI_RETRIES:=5}"
: "${TALOS_VERSIONS_URL:=https://raw.githubusercontent.com/syscode-labs/syscode-homelab-gitops-apps/main/omni/versions.yaml}"
: "${TALOS_LEDGER_URL:=https://raw.githubusercontent.com/syscode-labs/syscode-homelab-gitops-apps/main/omni/talos-image.yaml}"
TALOS_KEEP_ALL_FORCED=false

log() {
  printf '%s\n' "$*"
}

to_epoch() {
  # GNU and BSD date disagree; a wrong answer here silently disables the
  # age floor, so fail loudly rather than returning an empty string.
  local ts="$1" out=""
  if out=$(date -d "$ts" +%s 2>/dev/null); then
    printf '%s\n' "$out"; return 0
  fi
  if out=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${ts:0:19}" +%s 2>/dev/null); then
    printf '%s\n' "$out"; return 0
  fi
  log "ERROR: cannot parse timestamp ${ts} with either GNU or BSD date" >&2
  return 1
}

age_days() {
  local ts="$1"
  local now epoch
  now=$(date +%s)
  epoch=$(to_epoch "$ts")
  echo $(((now - epoch) / 86400))
}

age_hours() {
  local ts="$1"
  local now epoch
  now=$(date +%s)
  epoch=$(to_epoch "$ts")
  echo $(((now - epoch) / 3600))
}

run_or_echo() {
  if [[ "$DRY_RUN" == "true" ]]; then
    printf '[DRY-RUN]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

oci_retry_json() {
  local out=""
  local err_file=""
  local rc=0
  err_file="$(mktemp)"
  for attempt in $(seq 1 "$OCI_RETRIES"); do
    if out=$(timeout "$OCI_TIMEOUT_SEC" oci --profile "$OCI_PROFILE" "$@" --output json 2>"$err_file"); then
      rm -f "$err_file"
      printf '%s\n' "$out"
      return 0
    fi
    rc=$?
    log "OCI call failed attempt ${attempt}/${OCI_RETRIES} rc=${rc}: oci $*" >&2
    sed -n '1,6p' "$err_file" >&2 || true
    sleep 2
  done
  rm -f "$err_file"
  return 1
}

curl_retry() {
  local url="$1"
  local out=""
  for attempt in $(seq 1 "$OCI_RETRIES"); do
    if out=$(timeout "$OCI_TIMEOUT_SEC" curl -fsSL "$url" 2>/dev/null); then
      printf '%s\n' "$out"
      return 0
    fi
    log "curl fetch failed attempt ${attempt}/${OCI_RETRIES}: ${url}" >&2
    sleep 2
  done
  return 1
}

# Prints the set of pinned Talos versions (global + per-cluster overrides),
# one per line, deduplicated. Returns non-zero if the versions file could
# not be fetched. Callers MUST treat both a non-zero return and an empty
# result as "fail closed" (keep every talos image/object).
fetch_pinned_talos_versions() {
  local yaml
  if ! yaml=$(curl_retry "$TALOS_VERSIONS_URL"); then
    return 1
  fi
  if command -v yq >/dev/null 2>&1; then
    printf '%s\n' "$yaml" | yq eval '(.talos // ""), (.clusters[].talos // "")' - 2>/dev/null \
      | sed -e '/^$/d' -e '/^null$/d' | sort -u
  else
    printf '%s\n' "$yaml" | grep -oE 'talos:[[:space:]]*[^,}[:space:]]+' \
      | awk -F: '{gsub(/[[:space:]]/,"",$2); print $2}' \
      | sed '/^$/d' | sort -u
  fi
}

family_for_image() {
  local name="$1"
  case "$name" in
    oci-freetier-ampere-a1flex-proxmox-*) echo "proxmox" ;;
    oci-freetier-ampere-a1flex-debian-base-*) echo "debian-base" ;;
    oci-freetier-ampere-a1flex-base-*) echo "base" ;;
    oci-base-hardened-arm64-*) echo "hardened" ;;
    Debian-12-bookworm-genericcloud-aarch64) echo "debian-genericcloud" ;;
    Debian-12-bookworm-aarch64) echo "debian-nocloud" ;;
    talos-*) echo "talos" ;;
    *) echo "other" ;;
  esac
}

family_for_object() {
  local name="$1"
  case "$name" in
    proxmox-ampere-arm64-*.qcow2) echo "proxmox-qcow2" ;;
    debian-base-arm64-*.qcow2) echo "debian-base-qcow2" ;;
    debian-12-genericcloud-arm64.qcow2) echo "debian-genericcloud-qcow2" ;;
    debian-12-nocloud-arm64.qcow2) echo "debian-nocloud-qcow2" ;;
    talos-*-oracle-arm64.oci) echo "talos-oci" ;;
    *) echo "other" ;;
  esac
}

log "Cleanup start: profile=${OCI_PROFILE} compartment=${OCI_COMPARTMENT} bucket=${OCI_BUCKET} dry_run=${DRY_RUN}"

INST_JSON=$(oci_retry_json compute instance list --all --compartment-id "$OCI_COMPARTMENT")
ACTIVE_INSTANCE_IDS=$(echo "$INST_JSON" | jq -r '.data[] | select(."lifecycle-state" != "TERMINATED") | .id')
ACTIVE_IMAGE_IDS=$(echo "$INST_JSON" | jq -r '.data[] | select(."lifecycle-state" != "TERMINATED") | ."image-id"' | sort -u)

log "Active instances: $(printf '%s\n' "$ACTIVE_INSTANCE_IDS" | sed '/^$/d' | wc -l | tr -d ' ')"
log "Active image references: $(printf '%s\n' "$ACTIVE_IMAGE_IDS" | sed '/^$/d' | wc -l | tr -d ' ')"

# An image can be referenced by Terraform without any instance running from it
# — terraform.tfvars takes TF_VAR_talos_image_ocid from the build ledger. The
# running-instance check above cannot see that, and the ledger's OCID is not
# guaranteed to belong to a pinned version (as of 2026-08-03 it pointed at a
# v1.13.6 image while the ledger claimed v1.14.0-beta.1). Deleting it would
# leave Terraform referencing a dead OCID, so protect it explicitly.
LEDGER_IMAGE_ID=""
if ledger_yaml=$(curl_retry "${TALOS_LEDGER_URL}"); then
  LEDGER_IMAGE_ID=$(printf '%s' "$ledger_yaml" \
    | grep '^oci_image_ocid:' | awk '{print $2}' | head -n1)
  [[ -n "$LEDGER_IMAGE_ID" ]] && log "Ledger image reference: ${LEDGER_IMAGE_ID}"
else
  log "WARNING: could not fetch ${TALOS_LEDGER_URL}; cannot protect the ledger's"
  log "         image reference. Failing closed on the talos family."
  TALOS_KEEP_ALL_FORCED=true
fi

log "Step 1/3: prune terminated boot volumes"
BV_JSON=$(oci_retry_json bv boot-volume list --all --compartment-id "$OCI_COMPARTMENT")
while IFS=$'\t' read -r id name state created; do
  [[ -z "$id" ]] && continue
  [[ "$state" != "TERMINATED" ]] && continue
  ah=$(age_hours "$created")
  if (( ah < BOOTVOL_GRACE_HOURS )); then
    log "skip boot-volume (too new ${ah}h): ${name} ${id}"
    continue
  fi
  run_or_echo oci --profile "$OCI_PROFILE" bv boot-volume delete --boot-volume-id "$id" --force
done < <(echo "$BV_JSON" | jq -r '.data[] | [.id, ."display-name", ."lifecycle-state", ."time-created"] | @tsv')

log "Step 2/3: prune old custom images not in use"
IMG_JSON=$(oci_retry_json compute image list --all --compartment-id "$OCI_COMPARTMENT")
# Custom vs platform image: OCI has no `created-by` field on Image at all, so
# the old `select(."created-by" != null)` matched nothing and this whole step
# has always been a no-op — which is how 12 custom images accumulated against
# a 10-image limit. Platform images (Oracle Linux, CentOS, Windows) come back
# with a null compartment-id because they are global; anything imported or
# captured into this tenancy carries one.
CANDIDATE_IMAGES=$(echo "$IMG_JSON" | jq -r '.data[]
  | select(."compartment-id" != null)
  | [.id, ."display-name", ."lifecycle-state", ."time-created"]
  | @tsv')

if [[ -z "$CANDIDATE_IMAGES" ]]; then
  log "WARNING: no custom images matched. If this compartment does have custom"
  log "         images, the discriminator above is wrong again — do not assume"
  log "         'nothing to prune' means 'nothing is there'."
fi

TALOS_KEEP_ALL="$TALOS_KEEP_ALL_FORCED"
TALOS_VERSIONS=""
if TALOS_VERSIONS=$(fetch_pinned_talos_versions); then
  if [[ -z "$TALOS_VERSIONS" ]]; then
    log "WARNING: pinned Talos version set from ${TALOS_VERSIONS_URL} is empty; failing closed and keeping ALL talos images/objects"
    TALOS_KEEP_ALL=true
  else
    log "Pinned Talos versions: $(printf '%s' "$TALOS_VERSIONS" | tr '\n' ' ')"
  fi
else
  log "WARNING: failed to fetch pinned Talos versions from ${TALOS_VERSIONS_URL}; failing closed and keeping ALL talos images/objects"
  TALOS_KEEP_ALL=true
fi

KEEP_IDS=""
for fam in proxmox debian-base base hardened debian-genericcloud debian-nocloud talos; do
  if [[ "$fam" == "talos" ]]; then
    if [[ "$TALOS_KEEP_ALL" == "true" ]]; then
      ids=$(echo "$CANDIDATE_IMAGES" | awk -F'\t' '$2 ~ /^talos-/ {print $1}')
    else
      ids=""
      while IFS= read -r ver; do
        [[ -z "$ver" ]] && continue
        found=$(echo "$CANDIDATE_IMAGES" | awk -F'\t' -v p="talos-${ver}-" 'index($2,p)==1 {print $1}')
        [[ -n "$found" ]] && ids+="$found"$'\n'
      done <<< "$TALOS_VERSIONS"
    fi
    [[ -n "$ids" ]] && KEEP_IDS+="$ids"$'\n'
    continue
  fi
  id=$(echo "$CANDIDATE_IMAGES" | awk -F'\t' -v f="$fam" '
    function fam_of(n) {
      if (n ~ /^oci-freetier-ampere-a1flex-proxmox-/) return "proxmox"
      if (n ~ /^oci-freetier-ampere-a1flex-debian-base-/) return "debian-base"
      if (n ~ /^oci-freetier-ampere-a1flex-base-/) return "base"
      if (n ~ /^oci-base-hardened-arm64-/) return "hardened"
      if (n == "Debian-12-bookworm-genericcloud-aarch64") return "debian-genericcloud"
      if (n == "Debian-12-bookworm-aarch64") return "debian-nocloud"
      if (n ~ /^talos-/) return "talos"
      return "other"
    }
    fam_of($2)==f {print $0}
  ' | sort -t$'\t' -k4 | tail -n1 | cut -f1)
  [[ -n "$id" ]] && KEEP_IDS+="$id"$'\n'
done

while IFS=$'\t' read -r id name state created; do
  [[ -z "$id" ]] && continue
  [[ "$state" == "DELETED" ]] && continue

  fam=$(family_for_image "$name")
  [[ "$fam" == "other" ]] && continue

  if [[ -n "$LEDGER_IMAGE_ID" && "$id" == "$LEDGER_IMAGE_ID" ]]; then
    log "skip image (referenced by the build ledger / Terraform): ${name} ${id}"
    continue
  fi
  if printf '%s\n' "$ACTIVE_IMAGE_IDS" | grep -q "^${id}$"; then
    log "skip image (in use): ${name} ${id}"
    continue
  fi
  if printf '%s\n' "$KEEP_IDS" | grep -q "^${id}$"; then
    if [[ "$fam" == "talos" ]]; then
      log "keep pinned image family=${fam}: ${name} ${id}"
    else
      log "keep latest image family=${fam}: ${name} ${id}"
    fi
    continue
  fi

  ad=$(age_days "$created")
  if (( ad < KEEP_DAYS )); then
    log "skip image (too new ${ad}d): ${name} ${id}"
    continue
  fi

  run_or_echo oci --profile "$OCI_PROFILE" compute image delete --image-id "$id" --force
done < <(echo "$CANDIDATE_IMAGES")

log "Step 3/3: prune old qcow2 and talos oci objects"
OBJ_JSON=$(oci_retry_json os object list --namespace-name "$OCI_NAMESPACE" --bucket-name "$OCI_BUCKET" --all)
CANDIDATE_OBJS=$(echo "$OBJ_JSON" | jq -r '.data[] | select((.name|endswith(".qcow2")) or (.name|endswith(".oci"))) | [.name, ."time-created"] | @tsv')

KEEP_OBJS=""
for fam in proxmox-qcow2 debian-base-qcow2 debian-genericcloud-qcow2 debian-nocloud-qcow2 talos-oci; do
  if [[ "$fam" == "talos-oci" ]]; then
    if [[ "$TALOS_KEEP_ALL" == "true" ]]; then
      objs=$(echo "$CANDIDATE_OBJS" | awk -F'\t' '$1 ~ /^talos-.*-oracle-arm64\.oci$/ {print $1}')
    else
      objs=""
      while IFS= read -r ver; do
        [[ -z "$ver" ]] && continue
        found=$(echo "$CANDIDATE_OBJS" | awk -F'\t' -v n="talos-${ver}-oracle-arm64.oci" '$1==n {print $1}')
        [[ -n "$found" ]] && objs+="$found"$'\n'
      done <<< "$TALOS_VERSIONS"
    fi
    [[ -n "$objs" ]] && KEEP_OBJS+="$objs"$'\n'
    continue
  fi
  obj=$(echo "$CANDIDATE_OBJS" | awk -F'\t' -v f="$fam" '
    function fam_of(n) {
      if (n ~ /^proxmox-ampere-arm64-.*\.qcow2$/) return "proxmox-qcow2"
      if (n ~ /^debian-base-arm64-.*\.qcow2$/) return "debian-base-qcow2"
      if (n == "debian-12-genericcloud-arm64.qcow2") return "debian-genericcloud-qcow2"
      if (n == "debian-12-nocloud-arm64.qcow2") return "debian-nocloud-qcow2"
      if (n ~ /^talos-.*-oracle-arm64\.oci$/) return "talos-oci"
      return "other"
    }
    fam_of($1)==f {print $0}
  ' | sort -t$'\t' -k2 | tail -n1 | cut -f1)
  [[ -n "$obj" ]] && KEEP_OBJS+="$obj"$'\n'
done

while IFS=$'\t' read -r name created; do
  [[ -z "$name" ]] && continue
  fam=$(family_for_object "$name")
  [[ "$fam" == "other" ]] && continue

  if printf '%s\n' "$KEEP_OBJS" | grep -q "^${name}$"; then
    if [[ "$fam" == "talos-oci" ]]; then
      log "keep pinned object family=${fam}: ${name}"
    else
      log "keep latest object family=${fam}: ${name}"
    fi
    continue
  fi

  ad=$(age_days "$created")
  if (( ad < KEEP_DAYS )); then
    log "skip object (too new ${ad}d): ${name}"
    continue
  fi

  run_or_echo oci --profile "$OCI_PROFILE" os object delete --namespace-name "$OCI_NAMESPACE" --bucket-name "$OCI_BUCKET" --object-name "$name" --force
done < <(echo "$CANDIDATE_OBJS")

TOTAL_BYTES=$(oci_retry_json os object list --namespace-name "$OCI_NAMESPACE" --bucket-name "$OCI_BUCKET" --all | jq '[.data[].size] | add // 0')
TOTAL_GB=$(awk -v b="$TOTAL_BYTES" 'BEGIN {printf "%.2f", b/1024/1024/1024}')
log "Cleanup complete. bucket_total_bytes=${TOTAL_BYTES} bucket_total_gb=${TOTAL_GB}"
