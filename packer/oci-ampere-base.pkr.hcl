/*
 * OCI Ampere Base Image (ARM64)
 *
 * Builds a hardened Debian 12 ARM64 image on OCI using the Always Free
 * VM.Standard.A1.Flex shape. Packer launches an ephemeral builder instance,
 * provisions it, and creates a custom image; all build resources are destroyed
 * automatically after completion.
 */

packer {
  required_plugins {
    oracle = {
      source  = "github.com/hashicorp/oracle"
      version = ">= 1.0.5"
    }
  }
}

variable "compartment_ocid" {
  description = "Compartment OCID for the temporary builder and resulting image"
  type        = string

  validation {
    condition     = length(var.compartment_ocid) > 0
    error_message = "The compartment_ocid variable is required."
  }
}

variable "region" {
  description = "OCI region (e.g. uk-london-1)"
  type        = string
  default     = "uk-london-1"

  validation {
    condition     = length(var.region) > 0
    error_message = "The region variable is required."
  }
}

variable "availability_domain" {
  description = "Availability domain name for the builder instance"
  type        = string

  validation {
    condition     = length(var.availability_domain) > 0
    error_message = "The availability_domain variable is required."
  }
}

variable "subnet_ocid" {
  description = "Subnet OCID for the builder instance (should allow outbound internet)"
  type        = string

  validation {
    condition     = length(var.subnet_ocid) > 0
    error_message = "The subnet_ocid variable is required."
  }
}

variable "base_image_ocid" {
  description = "Base image OCID (Debian 12 ARM64 in the chosen region)"
  type        = string

  validation {
    condition     = length(var.base_image_ocid) > 0
    error_message = "The base_image_ocid variable is required."
  }
}

variable "ssh_username" {
  description = "SSH username for the base image (e.g. debian or ubuntu)"
  type        = string
  default     = "debian"
}

variable "ssh_private_key_path" {
  description = "Path to the SSH private key used to connect to the builder instance"
  type        = string

  validation {
    condition     = length(var.ssh_private_key_path) > 0
    error_message = "The ssh_private_key_path variable is required."
  }
}

variable "ssh_public_key" {
  description = "Public key to authorize on the builder instance (single-line OpenSSH format)"
  type        = string

  validation {
    condition     = length(var.ssh_public_key) > 0
    error_message = "The ssh_public_key variable is required."
  }
}

variable "assign_public_ip" {
  description = "Whether to assign a public IP to the builder (enable if subnet has no egress NAT)"
  type        = bool
  default     = true
}

variable "machine_type" {
  description = "Machine type identifier for the image name (e.g. a1flex, e2micro)"
  type        = string
  default     = "a1flex"
}

variable "tailscale_auth_key" {
  description = "Optional Tailscale auth key to preload (leave empty to skip)"
  type        = string
  default     = ""
}

source "oracle-oci" "ampere" {
  access_cfg_file_account = "syscode-homelab"
  availability_domain     = var.availability_domain
  base_image_ocid         = var.base_image_ocid
  compartment_ocid        = var.compartment_ocid
  image_name              = "oci-freetier-ampere-${var.machine_type}-base-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  region                  = var.region
  shape                   = "VM.Standard.A1.Flex"
  subnet_ocid             = var.subnet_ocid

  ssh_username         = var.ssh_username
  ssh_timeout          = "30m"
  ssh_private_key_file = var.ssh_private_key_path

  create_vnic_details {
    assign_public_ip = var.assign_public_ip
    subnet_id        = var.subnet_ocid
  }

  shape_config {
    ocpus         = 1
    memory_in_gbs = 6
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }
}

build {
  name    = "oci-ampere-base"
  sources = ["source.oracle-oci.ampere"]

  provisioner "file" {
    source      = "scripts/install-tailscale.sh"
    destination = "/tmp/install-tailscale.sh"
  }

  provisioner "file" {
    source      = "scripts/harden-base.sh"
    destination = "/tmp/harden-base.sh"
  }

  provisioner "file" {
    source      = "files/sshd_config"
    destination = "/tmp/sshd_config"
  }

  provisioner "file" {
    source      = "goss/base.goss.yaml"
    destination = "/tmp/base.goss.yaml"
  }

  provisioner "file" {
    source      = "scripts/run-goss.sh"
    destination = "/tmp/run-goss.sh"
  }

  provisioner "shell" {
    inline = [
      "sudo chmod +x /tmp/install-tailscale.sh /tmp/harden-base.sh",
      "sudo rm -f /etc/apt/apt.conf.d/50command-not-found || true",
      "sudo apt-get update || true",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget gnupg2 ca-certificates apt-transport-https cloud-init",
      "sudo /tmp/install-tailscale.sh",
      "sudo /tmp/harden-base.sh",
      "sudo mv /tmp/sshd_config /etc/ssh/sshd_config && sudo chown root:root /etc/ssh/sshd_config && sudo chmod 0600 /etc/ssh/sshd_config",
      "sudo systemctl enable ssh || sudo systemctl enable sshd || true",
      "sudo systemctl restart ssh || sudo systemctl restart sshd",
      # Bake SSH public key and prevent cloud-init from overwriting it on instance launch
      "sudo mkdir -p /home/ubuntu/.ssh && echo '${var.ssh_public_key}' | sudo tee /home/ubuntu/.ssh/authorized_keys && sudo chown -R ubuntu:ubuntu /home/ubuntu/.ssh && sudo chmod 700 /home/ubuntu/.ssh && sudo chmod 600 /home/ubuntu/.ssh/authorized_keys",
      # cloud-init: no additional SSH key overrides (baked key is the only one needed)
      "sudo touch /etc/cloud/cloud.cfg.d/99-custom.cfg",
      "if [ -n \"${var.tailscale_auth_key}\" ]; then echo \"TS_AUTHKEY=${var.tailscale_auth_key}\" | sudo tee /etc/default/tailscaled >/dev/null; fi",
      "sudo apt-get autoremove -y",
      "sudo apt-get clean",
      "sudo chmod +x /tmp/run-goss.sh",
      "sudo /tmp/run-goss.sh /tmp/base.goss.yaml",
      "sudo rm -rf /tmp/* /var/tmp/* /var/cache/apt/archives/*.deb",
      "history -c || true"
    ]
  }
}
