omni_ready         = true
omni_endpoint      = "omni.wind-bearded.ts.net:8090"
oci_config_profile = "syscode-homelab"

# 4x Ampere nodes (1 OCPU / 6 GB each = 4 OCPU / 24 GB total — full free tier)
ampere_nodes = [
  { name = "syscode-1", ocpus = 1, memory_gb = 6, boot_vol_gb = 50 },
  { name = "syscode-2", ocpus = 1, memory_gb = 6, boot_vol_gb = 50 },
  { name = "syscode-3", ocpus = 1, memory_gb = 6, boot_vol_gb = 50 },
  { name = "syscode-4", ocpus = 1, memory_gb = 6, boot_vol_gb = 50 },
]

# talos_image_ocid   — fetched from oci-talos-gitops-apps/omni/talos-image.yaml in CI
# omni_join_token    — passed via CI secret OMNI_JOIN_TOKEN
# tailscale_auth_key — passed via CI secret TAILSCALE_AUTH_KEY
# tenancy_ocid       — passed via CI secret OCI_TENANCY_OCID
# compartment_ocid   — passed via CI secret OCI_COMPARTMENT_OCID
