omni_ready       = true
talos_image_ocid = "ocid1.image.oc1.uk-london-1.aaaaaaaainhjkquyd5le6eo4n3thk6axjcmn6leqnga5i7g2qvxn2p5mslpq"

# Golden Micro image for workload nodes and bastion. Update after each image build.
micro_golden_image_ocid = "ocid1.image.oc1.uk-london-1.aaaaaaaafhydgy4jzxvi47pp2cniwlqfhzprm76gzhuvfme6zl2b6hu47vla"

# 2x Ampere nodes: cp-1 early-Tailscale proof + worker (1 OCPU / 6 GB each = 2 OCPU / 12 GB total)
ampere_nodes = [
  { name = "oci-talos-cp-1", ocpus = 1, memory_gb = 6, boot_vol_gb = 50, vpn_subnet = true },
  { name = "oci-talos-worker-1", ocpus = 1, memory_gb = 6, boot_vol_gb = 50, vpn_subnet = true },
]

# Always Free entitlement is 2x E2.1.Micro total.
# Slot 1: self-managed bastion (create_bastion=true, default).
# Slot 2: workload Micro node (oci-micro-01).
# Storage budget: 2x50 (Ampere) + 1x50 (bastion) + 1x50 (micro) = 200 GB.
micro_nodes = [
  { name = "oci-micro-01", boot_vol_gb = 50 },
]

# Site-to-site VPN is required because the live VCN already includes the VPN
# secondary CIDR and subnet. Setting this to false would attempt to remove the
# secondary CIDR, which fails while VPN resources are attached.
enable_oci_vpn = true

# The following must be set via TF_VAR_ environment variables or -var flags:
#
#   TF_VAR_oci_config_profile      — OCI CLI profile name (local runs); not needed in CI
#   TF_VAR_omni_machine_config    — CI secret OMNI_MACHINE_CONFIG from `omnictl jointoken machine-config`
#   TF_VAR_talos_image_ocid       — fetched from oci-talos-gitops-apps/omni/talos-image.yaml in CI
#   TF_VAR_tailscale_auth_key     — CI secret NODES_TAILSCALE_AUTHKEY
#   TF_VAR_tenancy_ocid           — CI secret OCI_TENANCY_OCID
#   TF_VAR_compartment_ocid       — CI secret OCI_COMPARTMENT_OCID
#   TF_VAR_ssh_public_key         — primary SSH public key for bastion + micro
#   TF_VAR_ssh_extra_public_keys  — additional SSH keys (e.g. personal + syscode)
