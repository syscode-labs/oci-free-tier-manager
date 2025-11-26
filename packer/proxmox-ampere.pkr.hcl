/*
 * Proxmox Ampere Image
 * 
 * Builds on base-hardened image and adds:
 * - Proxmox VE (via official installation)
 * - Ceph packages (ceph-mon, ceph-osd, ceph-mgr)
 * - tteck/Proxmox helper scripts (post-install, microcode)
 * - ARM64 optimizations
 * - Prepared for Talos VM deployment
 * 
 * Target: < 10GB
 */

packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1.0"
    }
  }
}

variable "source_image" {
  type    = string
  description = "Path to base-hardened.qcow2"
}

variable "headless" {
  type    = bool
  default = true
}

variable "output_directory" {
  type    = string
  default = "output-qemu"
}

source "qemu" "proxmox" {
  # Use base image as source
  disk_image           = true
  iso_url              = var.source_image
  iso_checksum         = "none"
  
  # VM settings
  vm_name              = "proxmox-ampere"
  output_directory     = var.output_directory
  disk_size            = "12G"
  disk_interface       = "virtio"
  format               = "qcow2"
  accelerator          = "hvf"  # macOS hypervisor
  
  # Resources (Proxmox needs more RAM during install)
  memory               = 4096
  cpus                 = 2
  
  # Network
  net_device           = "virtio-net"
  
  # Display
  headless             = var.headless
  vnc_bind_address     = "127.0.0.1"
  
  # Boot configuration (boot from disk)
  boot_wait            = "10s"
  
  # SSH settings
  ssh_username         = "root"
  ssh_password         = "packer"
  ssh_wait_timeout     = "30m"
  
  # Shutdown
  shutdown_command     = "shutdown -P now"
}

build {
  sources = ["source.qemu.proxmox"]
  
  # Update system first
  provisioner "shell" {
    inline = [
      "apt-get update",
      "apt-get upgrade -y"
    ]
  }
  
  # Add Proxmox repositories and install
  provisioner "shell" {
    script = "scripts/install-proxmox.sh"
  }
  
  # Run tteck helper scripts
  provisioner "shell" {
    script = "scripts/tteck-post-install.sh"
  }
  
  # Install Ceph packages (don't configure yet)
  provisioner "shell" {
    inline = [
      "apt-get install -y ceph ceph-mon ceph-osd ceph-mgr ceph-mds",
      "systemctl disable ceph.target",  # Don't start yet
      "systemctl disable ceph-mon.target",
      "systemctl disable ceph-osd.target",
      "systemctl disable ceph-mgr.target"
    ]
  }
  
  # Install additional tools for Talos/K8s
  provisioner "shell" {
    inline = [
      "apt-get install -y qemu-guest-agent cloud-init",
      "systemctl enable qemu-guest-agent"
    ]
  }
  
  # Configure for OCI (enable serial console)
  provisioner "shell" {
    inline = [
      "sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"quiet\"/GRUB_CMDLINE_LINUX_DEFAULT=\"quiet console=tty0 console=ttyS0,115200n8\"/' /etc/default/grub",
      "update-grub"
    ]
  }

  # Copy goss tests and runner
  provisioner "file" {
    source      = "goss/base.goss.yaml"
    destination = "/tmp/base.goss.yaml"
  }

  provisioner "file" {
    source      = "scripts/run-goss.sh"
    destination = "/tmp/run-goss.sh"
  }
  
  # Cleanup
  provisioner "shell" {
    inline = [
      "chmod +x /tmp/run-goss.sh",
      "/tmp/run-goss.sh /tmp/base.goss.yaml",
      "apt-get autoremove -y",
      "apt-get clean",
      "rm -rf /tmp/*",
      "rm -rf /var/tmp/*",
      "rm -rf /var/cache/apt/archives/*.deb",
      "history -c"
    ]
  }
}
