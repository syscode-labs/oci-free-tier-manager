/*
 * Input variables for OCI Free Tier configuration
 */

# OCI Authentication
# These variables are optional if you have ~/.oci/config configured
# The OCI provider will automatically read from that file

variable "tenancy_ocid" {
  description = "OCID of your tenancy (optional if using ~/.oci/config)"
  type        = string
  default     = ""  # Will be read from ~/.oci/config if empty
}

variable "user_ocid" {
  description = "OCID of the user (optional if using ~/.oci/config)"
  type        = string
  default     = ""  # Will be read from ~/.oci/config if empty
}

variable "fingerprint" {
  description = "Fingerprint of the API key (optional if using ~/.oci/config)"
  type        = string
  default     = ""  # Will be read from ~/.oci/config if empty
}

variable "private_key_path" {
  description = "Path to your private key file (optional if using ~/.oci/config)"
  type        = string
  default     = ""  # Will be read from ~/.oci/config if empty
}

variable "region" {
  description = "OCI region"
  type        = string
  default     = "uk-london-1"  # Closest to UK
}

variable "compartment_ocid" {
  description = "OCID of the compartment (required - cannot be auto-detected)"
  type        = string
}

# SSH Configuration
variable "ssh_public_key" {
  description = "SSH public key for instance access"
  type        = string
}

# Ampere A1 Configuration (ARM-based)
# Free tier allows: 4 OCPUs and 24GB RAM total
variable "ampere_instance_count" {
  description = "Number of Ampere A1 instances (0-4)"
  type        = number
  default     = 3  # Recommended: 3 for Proxmox cluster quorum
  
  validation {
    condition     = var.ampere_instance_count >= 0 && var.ampere_instance_count <= 4
    error_message = "Must create between 0 and 4 Ampere instances."
  }
}

variable "ampere_ocpus_per_instance" {
  description = "OCPUs per Ampere instance (total across all instances must be ≤ 4)"
  type        = number
  default     = 1.33  # With 3 instances = 3.99 OCPUs total
  
  validation {
    condition     = var.ampere_ocpus_per_instance >= 1 && var.ampere_ocpus_per_instance <= 4
    error_message = "OCPUs must be between 1 and 4."
  }
}

variable "ampere_memory_per_instance" {
  description = "Memory in GB per Ampere instance (total across all instances must be ≤ 24)"
  type        = number
  default     = 8  # With 3 instances = 24GB total
  
  validation {
    condition     = var.ampere_memory_per_instance >= 1 && var.ampere_memory_per_instance <= 24
    error_message = "Memory must be between 1 and 24 GB."
  }
}

variable "ampere_boot_volume_size" {
  description = "Boot volume size in GB for Ampere instances (min 47GB)"
  type        = number
  default     = 50  # Recommended: 50GB per instance
  
  validation {
    condition     = var.ampere_boot_volume_size >= 47 && var.ampere_boot_volume_size <= 200
    error_message = "Boot volume must be between 47 and 200 GB."
  }
}

# AMD E2.1.Micro Configuration (x86-based)
# Free tier allows: 2 instances max
variable "micro_instance_count" {
  description = "Number of E2.1.Micro instances (0-2)"
  type        = number
  default     = 1  # Recommended: 1 for bastion/jump host
  
  validation {
    condition     = var.micro_instance_count >= 0 && var.micro_instance_count <= 2
    error_message = "Must create between 0 and 2 Micro instances."
  }
}

variable "micro_boot_volume_size" {
  description = "Boot volume size in GB for Micro instances (min 47GB)"
  type        = number
  default     = 50  # Recommended: 50GB
  
  validation {
    condition     = var.micro_boot_volume_size >= 47 && var.micro_boot_volume_size <= 200
    error_message = "Boot volume must be between 47 and 200 GB."
  }
}

# Storage Configuration
# Free tier allows: 200GB total (including boot volumes)
variable "create_additional_volume" {
  description = "Whether to create additional block volume"
  type        = bool
  default     = false
}

variable "additional_volume_size" {
  description = "Size of additional volume in GB"
  type        = number
  default     = 50
}

# Budget Alert Configuration
variable "budget_alert_email" {
  description = "Email address for budget alerts (comma-separated for multiple)"
  type        = string
}
