/*
 * Input variables for OCI Free Tier configuration
 */

# OCI Authentication
variable "tenancy_ocid" {
  description = "OCID of your tenancy"
  type        = string
}

variable "user_ocid" {
  description = "OCID of the user"
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of the API key"
  type        = string
}

variable "private_key_path" {
  description = "Path to your private key file"
  type        = string
  default     = "~/.oci/oci_api_key.pem"
}

variable "region" {
  description = "OCI region"
  type        = string
  default     = "us-ashburn-1"
}

variable "compartment_ocid" {
  description = "OCID of the compartment"
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
  default     = 4
  
  validation {
    condition     = var.ampere_instance_count >= 0 && var.ampere_instance_count <= 4
    error_message = "Must create between 0 and 4 Ampere instances."
  }
}

variable "ampere_ocpus_per_instance" {
  description = "OCPUs per Ampere instance (total across all instances must be ≤ 4)"
  type        = number
  default     = 1
  
  validation {
    condition     = var.ampere_ocpus_per_instance >= 1 && var.ampere_ocpus_per_instance <= 4
    error_message = "OCPUs must be between 1 and 4."
  }
}

variable "ampere_memory_per_instance" {
  description = "Memory in GB per Ampere instance (total across all instances must be ≤ 24)"
  type        = number
  default     = 6
  
  validation {
    condition     = var.ampere_memory_per_instance >= 1 && var.ampere_memory_per_instance <= 24
    error_message = "Memory must be between 1 and 24 GB."
  }
}

variable "ampere_boot_volume_size" {
  description = "Boot volume size in GB for Ampere instances (min 47GB)"
  type        = number
  default     = 47
  
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
  default     = 2
  
  validation {
    condition     = var.micro_instance_count >= 0 && var.micro_instance_count <= 2
    error_message = "Must create between 0 and 2 Micro instances."
  }
}

variable "micro_boot_volume_size" {
  description = "Boot volume size in GB for Micro instances (min 47GB)"
  type        = number
  default     = 47
  
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
