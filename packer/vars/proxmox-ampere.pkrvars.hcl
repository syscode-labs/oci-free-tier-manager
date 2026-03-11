compartment_ocid     = "ocid1.compartment.oc1..aaaaaaaahox2upn7fvv4mhoifgbnshs42xlejatfcinkje26faq7yds3yffq"
availability_domain  = "EGzq:UK-LONDON-1-AD-1"
subnet_ocid          = "ocid1.subnet.oc1.uk-london-1.aaaaaaaaw3dw6toglzaivepv3bbhltmjyhv4va3h7i22s2ntvb4qeonbukka"
ssh_private_key_path = "~/.ssh/oci_free_tier"
ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIlJA4nTzCz5FcjSxGDbzqkeWRyKGc3SW4rWnVMHYdGr oci-free-tier"

# Base image: oci-freetier-ampere-a1flex-base (hardened Ubuntu 22.04 ARM64)
# Built by oci-ampere-base.pkr.hcl — run that first if this image is missing.
base_image_ocid = "ocid1.image.oc1.uk-london-1.aaaaaaaallq23bk4hob3fevrvk3dmzhkomlsyzy3j75idxyt44jyzkaexbma"
