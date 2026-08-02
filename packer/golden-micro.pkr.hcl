packer {
  required_version = ">= 1.9.0"
  required_plugins {
    oracle = {
      source  = "github.com/hashicorp/oracle"
      version = ">= 1.0.0"
    }
  }
}

variable "compartment_ocid" {
  type = string
}
variable "availability_domain" {
  type = string
}
variable "subnet_ocid" {
  type = string
}
variable "base_image_ocid" {
  type = string
}
variable "image_name" {
  type = string
}
variable "shape" {
  type    = string
  default = "VM.Standard.E2.1.Micro"
}
variable "ssh_username" {
  type    = string
  default = "ubuntu"
}
variable "access_cfg_file" {
  type = string
}
variable "enable_monitoring" {
  type    = bool
  default = false
}

source "oracle-oci" "golden" {
  availability_domain = var.availability_domain
  access_cfg_file     = var.access_cfg_file
  base_image_ocid     = var.base_image_ocid
  compartment_ocid    = var.compartment_ocid
  image_name          = var.image_name
  shape               = var.shape
  ssh_username        = var.ssh_username
  subnet_ocid         = var.subnet_ocid
}

build {
  name    = "oci-golden-micro"
  sources = ["source.oracle-oci.golden"]

  provisioner "shell" {
    scripts = [
      "provision/01-base.sh",
      "provision/02-hardened.sh",
      "provision/03-strip.sh",
      "provision/04-monitoring.sh",
    ]
    use_sudo = true
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive",
      "ENABLE_MONITORING=${var.enable_monitoring}",
    ]
  }
}
