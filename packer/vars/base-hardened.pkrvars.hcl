compartment_ocid     = "ocid1.compartment.oc1..aaaaaaaahox2upn7fvv4mhoifgbnshs42xlejatfcinkje26faq7yds3yffq"
availability_domain  = "EGzq:UK-LONDON-1-AD-1"
subnet_ocid          = "ocid1.subnet.oc1.uk-london-1.aaaaaaaaw3dw6toglzaivepv3bbhltmjyhv4va3h7i22s2ntvb4qeonbukka"
ssh_username         = "ubuntu"
ssh_private_key_path = "~/.ssh/oci_free_tier"
ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIlJA4nTzCz5FcjSxGDbzqkeWRyKGc3SW4rWnVMHYdGr oci-free-tier"

# Base image: Ubuntu 24.04 ARM64 — 22.04 libs too old for PXVIRT (need perl>=5.36, libzstd>=1.5.2)
base_image_ocid = "ocid1.image.oc1.uk-london-1.aaaaaaaarlzudoyt5g2ofuqhmkak5bcosbqstkcutdpx3eva5dc7t4v5wgpq"
