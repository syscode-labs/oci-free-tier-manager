# OCI Authentication
oci_config_profile = "syscode-homelab"

# Compartment and region
tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaaaa45jhs3edfw2yvwzdqrb4pibry4j4yc7t3u34uo6443xlvasdrshq"
compartment_ocid = "ocid1.compartment.oc1..aaaaaaaahox2upn7fvv4mhoifgbnshs42xlejatfcinkje26faq7yds3yffq"
region           = "uk-london-1"

# Budget alert
budget_alert_email = "giovanni@syscode.uk"

# Omni-ready mode — 4x Ampere Talos cluster
omni_ready    = true
omni_endpoint = "omni.wind-bearded.ts.net:8090"

# talos_image_ocid, omni_join_token, tailscale_auth_key passed via CI secrets:
#   tofu apply -var="talos_image_ocid=$TALOS_IMAGE_OCID" \
#              -var="omni_join_token=$OMNI_JOIN_TOKEN" \
#              -var="tailscale_auth_key=$TAILSCALE_AUTH_KEY"

ampere_nodes = [
  { name = "oci-talos-cp-1", ocpus = 1, memory_gb = 6, boot_vol_gb = 50 },
  { name = "oci-talos-cp-2", ocpus = 1, memory_gb = 6, boot_vol_gb = 50 },
  { name = "oci-talos-cp-3", ocpus = 1, memory_gb = 6, boot_vol_gb = 50 },
  { name = "oci-talos-worker-1", ocpus = 1, memory_gb = 6, boot_vol_gb = 50 },
]
micro_nodes = []
