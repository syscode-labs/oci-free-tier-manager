/*
 * AWS ARM64 Base Image (Graviton / t4g)
 *
 * Builds a hardened Debian 12 ARM64 AMI using an ephemeral Graviton instance.
 * Target: free-tier friendly (t4g.micro, 10GB gp3 root).
 */

packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.3.0"
    }
  }
}

variable "region" {
  description = "AWS region (e.g. eu-west-1)"
  type        = string

  validation {
    condition     = length(var.region) > 0
    error_message = "region is required."
  }
}

variable "source_ami" {
  description = "Base Debian 12 ARM64 AMI ID in the target region"
  type        = string

  validation {
    condition     = length(var.source_ami) > 0
    error_message = "source_ami is required."
  }
}

variable "ssh_username" {
  description = "SSH username for the base AMI (Debian images use 'admin')"
  type        = string
  default     = "admin"
}

variable "instance_type" {
  description = "Instance type for the builder (t4g.micro fits free tier credits)"
  type        = string
  default     = "t4g.micro"
}

variable "subnet_id" {
  description = "Subnet ID to place the builder (use a public subnet or attach NAT)"
  type        = string
  default     = ""
}

variable "associate_public_ip" {
  description = "Assign public IP to builder (set false if subnet has NAT)"
  type        = bool
  default     = true
}

variable "ssh_keypair_name" {
  description = "Existing EC2 key pair name to use for SSH"
  type        = string

  validation {
    condition     = length(var.ssh_keypair_name) > 0
    error_message = "ssh_keypair_name is required."
  }
}

variable "ssh_private_key_path" {
  description = "Path to the private key for ssh_keypair_name"
  type        = string

  validation {
    condition     = length(var.ssh_private_key_path) > 0
    error_message = "ssh_private_key_path is required."
  }
}

variable "ami_name_prefix" {
  description = "Prefix for the generated AMI"
  type        = string
  default     = "aws-base-hardened-arm64"
}

variable "tailscale_auth_key" {
  description = "Optional Tailscale auth key to preload"
  type        = string
  default     = ""
}

source "amazon-ebs" "arm" {
  region                  = var.region
  ami_name                = "${var.ami_name_prefix}-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  ami_description         = "Hardened Debian 12 ARM64 base image"
  ami_virtualization_type = "hvm"
  ami_architecture        = "arm64"
  source_ami              = var.source_ami
  instance_type           = var.instance_type
  ssh_username            = var.ssh_username
  ssh_timeout             = "30m"
  ssh_interface           = "public_ip"
  ssh_private_key_file    = var.ssh_private_key_path
  ssh_keypair_name        = var.ssh_keypair_name
  associate_public_ip_address = var.associate_public_ip
  subnet_id               = var.subnet_id != "" ? var.subnet_id : null
  temporary_security_group_source_cidr = "0.0.0.0/0"
  ena_support             = true
  force_deregister        = true
  force_delete_snapshot   = true
  run_tags = {
    Name = "packer-aws-arm-builder"
    Owner = "ci"
    Purpose = "arm-image-build"
    Ephemeral = "true"
  }
  tags = {
    Name    = "aws-base-hardened-arm64"
    Purpose = "arm-image-build"
  }
  launch_block_device_mappings {
    device_name = "/dev/xvda"
    volume_size = 10
    volume_type = "gp3"
    delete_on_termination = true
  }
}

build {
  name    = "aws-arm-base"
  sources = ["source.amazon-ebs.arm"]

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
