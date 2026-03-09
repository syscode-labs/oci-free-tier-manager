/*
 * Proxmox Ampere Image (ARM64)
 *
 * Builds on top of the hardened base image (oci-ampere-base).
 * Installs Proxmox VE ARM64 (unofficial port), hardens with
 * community-scripts steps, and snapshots as an OCI custom image.
 *
 * Prerequisites:
 *   1. Build oci-ampere-base first → note its image OCID
 *   2. Set base_image_ocid to that OCID in vars file
 *   3. Refresh syscode token: oci session authenticate --profile syscode
 */

packer {
  required_plugins {
    oracle = {
      source  = "github.com/hashicorp/oracle"
      version = ">= 1.0.5"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = ">= 1.1.1"
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

variable "availability_domain" {
  description = "Availability domain name (e.g. UK-LONDON-1-AD-1)"
  type        = string
  validation {
    condition     = length(var.availability_domain) > 0
    error_message = "The availability_domain variable is required."
  }
}

variable "subnet_ocid" {
  description = "Subnet OCID (public subnet from Layer 1 Terraform output)"
  type        = string
  validation {
    condition     = length(var.subnet_ocid) > 0
    error_message = "The subnet_ocid variable is required."
  }
}

variable "base_image_ocid" {
  description = "OCID of the hardened base image (output of oci-ampere-base build)"
  type        = string
  validation {
    condition     = length(var.base_image_ocid) > 0
    error_message = "The base_image_ocid variable is required."
  }
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for builder instance access"
  type        = string
  validation {
    condition     = length(var.ssh_private_key_path) > 0
    error_message = "The ssh_private_key_path variable is required."
  }
}

variable "ssh_public_key" {
  description = "SSH public key to authorize on the builder instance"
  type        = string
  validation {
    condition     = length(var.ssh_public_key) > 0
    error_message = "The ssh_public_key variable is required."
  }
}

variable "image_name_prefix" {
  description = "Prefix for the resulting OCI custom image name"
  type        = string
  default     = "proxmox-ampere-arm64"
}

variable "region" {
  description = "OCI region"
  type        = string
  default     = "uk-london-1"
}

source "oracle-oci" "proxmox" {
  access_cfg_file_account = "syscode"
  availability_domain     = var.availability_domain
  base_image_ocid         = var.base_image_ocid
  compartment_ocid        = var.compartment_ocid
  image_name              = "${var.image_name_prefix}-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  region                  = var.region
  shape                   = "VM.Standard.A1.Flex"
  subnet_ocid             = var.subnet_ocid

  assign_public_ip     = true
  ssh_username         = "debian"
  ssh_timeout          = "30m"
  ssh_private_key_file = var.ssh_private_key_path

  shape_config {
    ocpus         = 2
    memory_in_gbs = 12
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }

  state_timeout = "60m"
}

build {
  name    = "proxmox-ampere"
  sources = ["source.oracle-oci.proxmox"]

  # Stage 1: Proxmox VE installation
  provisioner "file" {
    source      = "scripts/install-proxmox.sh"
    destination = "/tmp/install-proxmox.sh"
  }

  provisioner "shell" {
    inline = ["sudo chmod +x /tmp/install-proxmox.sh && sudo /tmp/install-proxmox.sh"]
  }

  # Stage 2: Community-scripts post-install hardening (non-interactive)
  provisioner "file" {
    source      = "scripts/community-post-install.sh"
    destination = "/tmp/community-post-install.sh"
  }

  provisioner "shell" {
    inline = ["sudo chmod +x /tmp/community-post-install.sh && sudo /tmp/community-post-install.sh"]
  }

  # Stage 3: Ansible hardening (ZFS tuning, Proxmox-specific sysctl, fail2ban jail)
  provisioner "ansible" {
    playbook_file = "ansible/packer-harden-proxmox.yml"
    user          = "debian"
    use_proxy     = false
    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_NOCOLOR=True",
    ]
    extra_arguments = ["--become"]
  }

  # Stage 4: Goss validation
  provisioner "file" {
    source      = "goss/proxmox.goss.yaml"
    destination = "/tmp/proxmox.goss.yaml"
  }

  provisioner "file" {
    source      = "scripts/run-goss.sh"
    destination = "/tmp/run-goss.sh"
  }

  provisioner "shell" {
    inline = [
      "sudo chmod +x /tmp/run-goss.sh",
      "sudo /tmp/run-goss.sh /tmp/proxmox.goss.yaml",
    ]
  }

  # Stage 5: Cleanup
  provisioner "shell" {
    inline = [
      "sudo apt-get autoremove -y",
      "sudo apt-get clean",
      "sudo rm -rf /tmp/* /var/tmp/* /var/cache/apt/archives/*.deb",
      "sudo truncate -s 0 /etc/machine-id",
      "history -c || true",
    ]
  }
}
