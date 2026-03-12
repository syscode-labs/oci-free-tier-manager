/*
 * Proxmox Ampere Image — QEMU builder (GitHub Actions ARM64 runner)
 *
 * Builds a Proxmox VE ARM64 image using QEMU with KVM acceleration.
 * Runs on GitHub Actions ubuntu-24.04-arm runners (native KVM, fast).
 *
 * Input:  Debian 12 ARM64 genericcloud QCOW2
 * Output: QCOW2 image with Proxmox VE installed, ready for OCI import
 *
 * Usage (GitHub Actions or local ARM64 with KVM):
 *   packer build -var-file=vars/proxmox-ampere-qemu.pkrvars.hcl proxmox-ampere-qemu.pkr.hcl
 */

packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.1.0"
    }
  }
}

variable "debian_image_url" {
  description = "URL or local path to Debian 12 ARM64 genericcloud QCOW2"
  type        = string
  default     = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-arm64.qcow2"
}

variable "debian_image_checksum" {
  description = "SHA512 checksum of the Debian 12 image (empty to skip)"
  type        = string
  default     = "none"
}

variable "ssh_public_key" {
  description = "SSH public key to inject via cloud-init NoCloud"
  type        = string
  validation {
    condition     = length(var.ssh_public_key) > 0
    error_message = "The ssh_public_key variable is required."
  }
}

variable "disk_size" {
  description = "Output disk size (must be >= Debian base image size)"
  type        = string
  default     = "20G"
}

variable "memory" {
  description = "RAM for build VM in MB"
  type        = number
  default     = 4096
}

variable "cpus" {
  description = "CPUs for build VM"
  type        = number
  default     = 2
}

variable "output_directory" {
  description = "Directory for the output QCOW2"
  type        = string
  default     = "output-proxmox-qemu"
}

source "qemu" "proxmox" {
  # Debian 12 ARM64 cloud image as base
  iso_url      = var.debian_image_url
  iso_checksum = var.debian_image_checksum
  disk_image   = true

  # VM settings
  vm_name          = "proxmox-ampere-arm64"
  output_directory = var.output_directory
  disk_size        = var.disk_size
  disk_interface   = "virtio"
  format           = "qcow2"
  machine_type     = "virt"

  # ARM64 + KVM acceleration (GitHub ubuntu-24.04-arm runner has KVM)
  accelerator  = "kvm"
  qemu_binary  = "qemu-system-aarch64"
  net_device   = "virtio-net"
  memory       = var.memory
  cpus         = var.cpus

  # UEFI firmware for ARM64
  qemuargs = [
    ["-bios", "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"],
    ["-device", "virtio-rng-pci"],
  ]

  # Cloud-init NoCloud seed: Packer creates a CD-ROM labeled "cidata"
  # Debian 12 cloud-init reads from this to get the SSH public key
  cd_label = "cidata"
  cd_files = [
    "/tmp/packer-cidata/user-data",
    "/tmp/packer-cidata/meta-data",
  ]

  # SSH settings (cloud-init injects the key from the seed)
  ssh_username         = "debian"
  ssh_timeout          = "20m"
  ssh_private_key_file = "~/.ssh/id_ed25519"

  headless         = true
  shutdown_command = "sudo shutdown -P now"
}

build {
  name    = "proxmox-ampere-qemu"
  sources = ["source.qemu.proxmox"]

  # Prepare cloud-init seed files before the VM boots
  provisioner "shell-local" {
    inline = [
      "mkdir -p /tmp/packer-cidata",
      "printf '#cloud-config\\nssh_authorized_keys:\\n  - ${var.ssh_public_key}\\n' > /tmp/packer-cidata/user-data",
      "printf 'instance-id: proxmox-build\\nlocal-hostname: proxmox-build\\n' > /tmp/packer-cidata/meta-data",
    ]
  }

  # Wait for cloud-init to complete SSH key setup
  provisioner "shell" {
    inline            = ["cloud-init status --wait 2>/dev/null || true"]
    valid_exit_codes  = [0, 1]
  }

  # Stage 1: Install Proxmox VE
  provisioner "file" {
    source      = "scripts/install-proxmox.sh"
    destination = "/tmp/install-proxmox.sh"
  }

  provisioner "shell" {
    inline = ["sudo chmod +x /tmp/install-proxmox.sh && sudo /tmp/install-proxmox.sh"]
  }

  # Stage 2: Community post-install hardening
  provisioner "file" {
    source      = "scripts/community-post-install.sh"
    destination = "/tmp/community-post-install.sh"
  }

  provisioner "shell" {
    inline = ["sudo chmod +x /tmp/community-post-install.sh && sudo /tmp/community-post-install.sh"]
  }

  # Stage 3: Goss validation
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

  # Stage 4: Cleanup
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
