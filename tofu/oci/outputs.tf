/*
 * Output values for easy access to created resources
 */

output "vcn_id" {
  description = "ID of the VCN"
  value       = oci_core_vcn.free_tier_vcn.id
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = oci_core_subnet.free_tier_subnet.id
}

output "ampere_instance_ids" {
  description = "IDs of Ampere A1 instances"
  value       = oci_core_instance.ampere_instance[*].id
}

output "ampere_instance_public_ips" {
  description = "Public IP addresses of Ampere A1 instances"
  value       = oci_core_instance.ampere_instance[*].public_ip
}

output "ampere_instance_names" {
  description = "Names of Ampere A1 instances"
  value       = oci_core_instance.ampere_instance[*].display_name
}

output "micro_instance_ids" {
  description = "IDs of E2.1.Micro instances"
  value       = oci_core_instance.micro_instance[*].id
}

output "micro_instance_public_ips" {
  description = "Public IP addresses of E2.1.Micro instances"
  value       = oci_core_instance.micro_instance[*].public_ip
}

output "micro_instance_names" {
  description = "Names of E2.1.Micro instances"
  value       = oci_core_instance.micro_instance[*].display_name
}

output "budget_id" {
  description = "ID of the budget"
  value       = oci_budget_budget.free_tier_budget.id
}

output "ssh_connection_commands" {
  description = "SSH commands to connect to instances"
  value = concat(
    [for ip in oci_core_instance.ampere_instance[*].public_ip : "ssh ubuntu@${ip}"],
    [for ip in oci_core_instance.micro_instance[*].public_ip : "ssh ubuntu@${ip}"]
  )
}
