plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "oci" {
  enabled = true
  version = "0.7.0"
  source  = "github.com/terraform-linters/tflint-ruleset-oci"
}

# Naming conventions
rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

# Documentation
rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

# Code quality
rule "terraform_deprecated_interpolation" {
  enabled = true
}

rule "terraform_deprecated_index" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_unused_required_providers" {
  enabled = true
}

rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_standard_module_structure" {
  enabled = true
}

# OCI specific - prevent costly mistakes
rule "terraform_comment_syntax" {
  enabled = true
}

rule "terraform_module_pinned_source" {
  enabled = true
}

# Security
rule "terraform_workspace_remote" {
  enabled = false # We use local state for free tier
}
