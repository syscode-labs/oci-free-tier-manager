/*
 * Cross-resource validation using Terraform check blocks (requires Terraform/OpenTofu 1.5+)
 *
 * These checks enforce OCI free-tier budget constraints.
 * In normal apply/plan runs they produce warnings. In `terraform test` runs they
 * cause test failures unless the test uses `expect_failures`.
 *
 * Budget limits:
 *   Total Ampere OCPUs  ≤ 4
 *   Total Ampere RAM    ≤ 24 GB
 *   Total boot storage  ≤ 200 GB (ampere + micro combined)
 *
 * OCPU constraint (all account types):
 *   OCPUs must be integers (1, 2, 3, or 4) — the OCI API enforces min=1, step=1
 *
 * Minimum sizes:
 *   Each boot volume ≥ 47 GB (OCI minimum)
 */

# ---------------------------------------------------------------------------
# Budget checks
# ---------------------------------------------------------------------------

check "ocpu_budget" {
  assert {
    condition     = local.total_ocpus <= 4
    error_message = "Total Ampere OCPUs (${local.total_ocpus}) exceeds free tier limit of 4. Reduce node count or OCPUs per node."
  }
}

check "ram_budget" {
  assert {
    condition     = local.total_ram_gb <= 24
    error_message = "Total Ampere RAM (${local.total_ram_gb} GB) exceeds free tier limit of 24 GB. Reduce node count or memory_gb per node."
  }
}

check "storage_budget" {
  assert {
    condition     = local.total_storage_gb <= 200
    error_message = "Total boot volume storage (${local.total_storage_gb} GB) exceeds free tier limit of 200 GB. Reduce node count or boot_vol_gb."
  }
}

# ---------------------------------------------------------------------------
# OCPU constraint (applies to all account types)
# ---------------------------------------------------------------------------

check "integer_ocpus" {
  assert {
    condition = alltrue([
      for n in local._ampere_nodes : n.ocpus == floor(n.ocpus)
    ])
    error_message = "OCPUs must be integers (1, 2, 3, or 4). Fractional values (e.g. 1.33) are not accepted by the OCI API."
  }
}

# ---------------------------------------------------------------------------
# Minimum boot volume sizes
# ---------------------------------------------------------------------------

check "ampere_min_boot_vol" {
  assert {
    condition     = alltrue([for n in local._ampere_nodes : n.boot_vol_gb >= 47])
    error_message = "All Ampere boot volumes must be at least 47 GB (OCI minimum). Check boot_vol_gb in ampere_nodes."
  }
}

check "micro_min_boot_vol" {
  assert {
    condition     = length(local._micro_nodes) == 0 || alltrue([for n in local._micro_nodes : n.boot_vol_gb >= 47])
    error_message = "All Micro boot volumes must be at least 47 GB (OCI minimum). Check boot_vol_gb in micro_nodes."
  }
}

# ---------------------------------------------------------------------------
# omni_ready prerequisite checks
# ---------------------------------------------------------------------------

check "omni_ready_requires_talos_image" {
  assert {
    condition     = !var.omni_ready || var.talos_image_ocid != null
    error_message = "omni_ready = true requires talos_image_ocid. Import the Talos+Tailscale Image Factory image and set talos_image_ocid."
  }
}

check "omni_ready_requires_endpoint" {
  assert {
    condition     = !var.omni_ready || var.omni_endpoint != null
    error_message = "omni_ready = true requires omni_endpoint (e.g. omni.example.com:8090)."
  }
}

check "omni_ready_requires_join_token" {
  assert {
    condition     = !var.omni_ready || var.omni_join_token != null
    error_message = "omni_ready = true requires omni_join_token. Get from: omnictl get connections -o yaml | grep joinToken."
  }
}

check "omni_ready_requires_tailscale_key" {
  assert {
    condition     = !var.omni_ready || var.tailscale_auth_key != null
    error_message = "omni_ready = true requires tailscale_auth_key with tag:oci applied."
  }
}

# ---------------------------------------------------------------------------
# Compartment/IAM preconditions
# ---------------------------------------------------------------------------

check "compartment_name_required" {
  assert {
    condition     = !var.create_compartment || var.compartment_name != null
    error_message = "compartment_name is required when create_compartment = true."
  }
}

check "iam_key_requires_compartment" {
  assert {
    condition     = var.iam_api_public_key == null || var.create_compartment
    error_message = "iam_api_public_key is only used when create_compartment = true. Set create_compartment = true or remove iam_api_public_key."
  }
}
