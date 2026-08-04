omni_ready       = true
talos_image_ocid = "ocid1.image.oc1.uk-london-1.aaaaaaaaxti4ckz7p7gxgc2fbu23naiqqb4xggaluujgjofwscnfmufxq5dq"

# 2x Ampere nodes: cp-1 early-Tailscale proof + worker (1 OCPU / 6 GB each = 2 OCPU / 12 GB total)
ampere_nodes = [
  { name = "oci-talos-cp-1", ocpus = 1, memory_gb = 6, boot_vol_gb = 50, vpn_subnet = true },
  { name = "oci-talos-worker-1", ocpus = 1, memory_gb = 6, boot_vol_gb = 50, vpn_subnet = true },
]

# The following must be set via TF_VAR_ environment variables or -var flags:
#
#   TF_VAR_oci_config_profile   — OCI CLI profile name (local runs); not needed in CI
#   TF_VAR_omni_machine_config — CI secret OMNI_MACHINE_CONFIG from `omnictl jointoken machine-config`
#   TF_VAR_talos_image_ocid     — resolved in CI by querying OCI for the image
#                                 matching oci-lab's Talos pin in
#                                 syscode-homelab-gitops-apps/omni/versions.yaml.
#                                 NOT taken from the build ledger: that holds one
#                                 OCID for whatever was built last, which need not
#                                 be the version oci-lab is pinned to.
#   TF_VAR_tailscale_auth_key   — CI secret NODES_TAILSCALE_AUTHKEY
#   TF_VAR_tenancy_ocid         — CI secret OCI_TENANCY_OCID
#   TF_VAR_compartment_ocid     — CI secret OCI_COMPARTMENT_OCID
