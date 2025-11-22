plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "oci" {
  enabled = true
  version = "0.7.0"
  source  = "github.com/terraform-linters/tflint-ruleset-oci"
}

rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_deprecated_interpolation" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}
