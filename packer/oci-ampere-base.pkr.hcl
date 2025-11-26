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

variable "tenancy_ocid" {
  description = "OCI tenancy OCID"
  type        = string

  validation {
    condition     = length(var.tenancy_ocid) > 0
    error_message = "tenancy_ocid is required."
  }
}

variable "user_ocid" {
  description = "OCI user OCID used for API authentication"
  type        = string

  validation {
    condition     = length(var.user_ocid) > 0
    error_message = "user_ocid is required."
  }
}

variable "compartment_ocid" {
  description = "Compartment OCID for the temporary builder and resulting image"
  type        = string

  validation {
    condition     = length(var.compartment_ocid) > 0
    error_message = "compartment_ocid is required."
  }
}

variable "fingerprint" {
  description = "API signing key fingerprint"
  type        = string

  validation {
    condition     = length(var.fingerprint) > 0
    error_message = "fingerprint is required."
  }
}

variable "region" {
  description = "OCI region (e.g. uk-london-1)"
  type        = string
  default     = "uk-london-1"

  validation {
    condition     = length(var.region) > 0
    error_message = "region is required."
  }
}

variable "availability_domain" {
  description = "Availability domain name for the builder instance"
  type        = string

  validation {
    condition     = length(var.availability_domain) > 0
    error_message = "availability_domain is required."
  }
}

variable "subnet_ocid" {
  description = "Subnet OCID for the builder instance (should allow outbound internet)"
  type        = string

  validation {
    condition     = length(var.subnet_ocid) > 0
    error_message = "subnet_ocid is required."
  }
}

variable "base_image_ocid" {
  description = "Base image OCID (Debian 12 ARM64 in the chosen region)"
  type        = string

  validation {
    condition     = length(var.base_image_ocid) > 0
    error_message = "base_image_ocid is required."
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
    error_message = "ssh_private_key_path is required."
  }
}

variable "ssh_public_key" {
  description = "Public key to authorize on the builder instance (single-line OpenSSH format)"
  type        = string

  validation {
    condition     = length(var.ssh_public_key) > 0
    error_message = "ssh_public_key is required."
  }
}

variable "api_private_key_path" {
  description = "Path to the OCI API signing private key (PEM file)"
  type        = string

  validation {
    condition     = length(var.api_private_key_path) > 0
    error_message = "api_private_key_path is required."
  }
}

variable "assign_public_ip" {
  description = "Whether to assign a public IP to the builder (enable if subnet has no egress NAT)"
  type        = bool
  default     = true
}

variable "image_name_prefix" {
  description = "Prefix for the generated custom image"
  type        = string
  default     = "oci-base-hardened-arm64"
}

variable "tailscale_auth_key" {
  description = "Optional Tailscale auth key to preload (leave empty to skip)"
  type        = string
  default     = ""
}

source "oracle-oci" "ampere" {
  availability_domain = var.availability_domain
  base_image_ocid     = var.base_image_ocid
  compartment_ocid    = var.compartment_ocid
  fingerprint         = var.fingerprint
  image_name          = "${var.image_name_prefix}-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  region              = var.region
  shape               = "VM.Standard.A1.Flex"
  subnet_ocid         = var.subnet_ocid
  tenancy_ocid        = var.tenancy_ocid
  user_ocid           = var.user_ocid

  assign_public_ip   = var.assign_public_ip
  ssh_username       = var.ssh_username
  ssh_timeout        = "30m"
  ssh_private_key_file = var.ssh_private_key_path

  private_key_path = var.api_private_key_path

  shape_config {
    ocpus         = 1
    memory_in_gbs = 6
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }

  state_timeout = "45m"
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
    source      = "files/firewall.rules"
    destination = "/tmp/firewall.rules"
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
      "sudo apt-get update",
      "sudo apt-get upgrade -y",
      "sudo apt-get install -y curl wget gnupg2 ca-certificates apt-transport-https qemu-guest-agent cloud-init",
      "sudo systemctl enable qemu-guest-agent",
      "sudo /tmp/install-tailscale.sh",
      "sudo /tmp/harden-base.sh",
      "sudo mv /tmp/sshd_config /etc/ssh/sshd_config",
      "sudo mv /tmp/firewall.rules /etc/iptables/rules.v4",
      "sudo systemctl restart ssh || sudo systemctl restart sshd",
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
