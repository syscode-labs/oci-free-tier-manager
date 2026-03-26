omni_ready = true

# 4x Ampere nodes: 3 control-plane + 1 worker (1 OCPU / 6 GB each = 4 OCPU / 24 GB total)
ampere_nodes = [
  { name = "oci-talos-cp-1", ocpus = 1, memory_gb = 6, boot_vol_gb = 50 },
  { name = "oci-talos-cp-2", ocpus = 1, memory_gb = 6, boot_vol_gb = 50 },
  { name = "oci-talos-cp-3", ocpus = 1, memory_gb = 6, boot_vol_gb = 50 },
  { name = "oci-talos-worker-1", ocpus = 1, memory_gb = 6, boot_vol_gb = 50 },
]

# The following must be set via TF_VAR_ environment variables or -var flags:
#
#   TF_VAR_oci_config_profile   — OCI CLI profile name (local runs); not needed in CI
#   TF_VAR_omni_endpoint        — Omni SideroLink endpoint, e.g. "omni.example.com:8090"
#   TF_VAR_talos_image_ocid     — fetched from oci-talos-gitops-apps/omni/talos-image.yaml in CI
#   TF_VAR_omni_join_token      — CI secret OMNI_JOIN_TOKEN
#   TF_VAR_tailscale_auth_key   — CI secret TAILSCALE_AUTH_KEY
#   TF_VAR_tenancy_ocid         — CI secret OCI_TENANCY_OCID
#   TF_VAR_compartment_ocid     — CI secret OCI_COMPARTMENT_OCID
