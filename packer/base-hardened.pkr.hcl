/*
 * Base Hardened Image
 * 
 * Builds a minimal, hardened Debian 12 base image with:
 * - SSH server (hardened configuration)
 * - Tailscale (for mesh networking)
 * - Essential system utilities
 * - Firewall configured
 * - Automatic security updates
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

variable "headless" {
  type    = bool
  default = true
}

variable "output_directory" {
  type    = string
  default = "output-qemu"
}

variable "ssh_authorized_key" {
  description = "SSH public key to add to root authorized_keys (optional)"
  type        = string
  default     = ""
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key to persist in /etc/default/tailscaled for first-boot join (optional)"
  type        = string
  default     = ""
}

source "qemu" "debian12" {
  # Debian 12 netinstall ISO
  iso_url      = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.8.0-amd64-netinst.iso"
  iso_checksum = "sha512:33c08e56c83d13007e4a5511b9bf2c4926c4aa12fd5dd56d493c0653aecbab380988c5bf1671dbaea75c582827797d98c4a611f7fb2b131fbde2c677d5258ec9"
  
  # VM settings
  vm_name              = "base-hardened"
  output_directory     = var.output_directory
  disk_size            = "8G"
  disk_interface       = "virtio"
  format               = "qcow2"
  accelerator          = "hvf"  # macOS hypervisor
  
  # Resources
  memory               = 2048
  cpus                 = 2
  
  # Network
  net_device           = "virtio-net"
  
  # Display
  headless             = var.headless
  vnc_bind_address     = "127.0.0.1"
  
  # Boot configuration
  boot_wait            = "5s"
  boot_command         = [
    "<esc><wait>",
    "auto <wait>",
    "console-setup/ask_detect=false <wait>",
    "console-keymaps-at/keymap=us <wait>",
    "debconf/frontend=noninteractive <wait>",
    "debian-installer=en_US.UTF-8 <wait>",
    "fb=false <wait>",
    "kbd-chooser/method=us <wait>",
    "keyboard-configuration/xkb-keymap=us <wait>",
    "locale=en_US.UTF-8 <wait>",
    "netcfg/get_hostname=base-hardened <wait>",
    "netcfg/get_domain=localdomain <wait>",
    "preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg <wait>",
    "<enter><wait>"
  ]
  
  # HTTP server for preseed
  http_directory       = "files"
  
  # SSH settings
  ssh_username         = "root"
  ssh_password         = "packer"
  ssh_wait_timeout     = "30m"
  ssh_handshake_attempts = 20
  
  # Shutdown
  shutdown_command     = "shutdown -P now"
}

build {
  sources = ["source.qemu.debian12"]
  
  # Wait for cloud-init to finish
  provisioner "shell" {
    inline = [
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done"
    ]
  }
  
  # Update system
  provisioner "shell" {
    inline = [
      "apt-get update",
      "apt-get upgrade -y",
      "apt-get install -y curl wget gnupg2 ca-certificates apt-transport-https"
    ]
  }
  
  # Install Tailscale
  provisioner "shell" {
    script = "scripts/install-tailscale.sh"
  }
  
  # Harden SSH and system
  provisioner "shell" {
    script = "scripts/harden-base.sh"
  }
  
  # Copy hardened SSH config
  provisioner "file" {
    source      = "files/sshd_config"
    destination = "/etc/ssh/sshd_config"
  }
  
  # Setup firewall
  provisioner "file" {
    source      = "files/firewall.rules"
    destination = "/etc/iptables/rules.v4"
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

  # Enable automatic security updates
  provisioner "shell" {
    inline = [
      "apt-get install -y unattended-upgrades apt-listchanges",
      "dpkg-reconfigure -plow unattended-upgrades"
    ]
  }

  # Inject SSH authorized key if provided
  provisioner "shell" {
    inline = [
      "if [ -n \"${var.ssh_authorized_key}\" ]; then mkdir -p /root/.ssh; echo \"${var.ssh_authorized_key}\" > /root/.ssh/authorized_keys; chmod 700 /root/.ssh; chmod 600 /root/.ssh/authorized_keys; fi"
    ]
  }

  # Persist Tailscale auth key (optional)
  provisioner "shell" {
    inline = [
      "if [ -n \"${var.tailscale_auth_key}\" ]; then install -m 600 /dev/null /etc/default/tailscaled; echo \"TS_AUTHKEY=${var.tailscale_auth_key}\" > /etc/default/tailscaled; fi"
    ]
  }

  # Validate with goss
  provisioner "shell" {
    inline = [
      "chmod +x /tmp/run-goss.sh",
      "/tmp/run-goss.sh /tmp/base.goss.yaml"
    ]
  }
  
  # Cleanup
  provisioner "shell" {
    inline = [
      "apt-get autoremove -y",
      "apt-get clean",
      "rm -rf /tmp/*",
      "rm -rf /var/tmp/*",
      "history -c"
    ]
  }
}
