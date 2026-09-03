output "management_public_ip" {
  description = <<-EOT
    Public address of nic0, the SMC contact address and SSH target.
  EOT
  value       = module.engine.management_external_ip
}

output "wan_public_ip" {
  description = <<-EOT
    Public address of nic2, the WAN interface. For example the local VPN
    endpoint.
  EOT
  value       = module.engine.external_ips["nic2"]
}

output "network_interfaces" {
  description = "Per-interface index, subnetwork, network and addresses."
  value       = module.engine.network_interfaces
}

output "networks" {
  description = "Self-links of the three VPC networks."
  value       = { for key, network in google_compute_network.this : key => network.self_link }
}

output "subnetworks" {
  description = "Self-links of the three subnetworks."
  value       = { for key, subnetwork in google_compute_subnetwork.this : key => subnetwork.self_link }
}

output "server_internal_ip" {
  description = "Private address of the protected test server."
  value       = google_compute_instance.server.network_interface[0].network_ip
}

output "server_ssh_command" {
  description = <<-EOT
    SSH to the protected server through IAP. It has no public address.
  EOT
  value = join(" ", [
    "gcloud compute ssh",
    google_compute_instance.server.name,
    "--zone", var.zone,
    "--tunnel-through-iap",
  ])
}

output "ssh_command" {
  description = "SSH command for the engine."
  value       = "ssh gencloud@${module.engine.management_external_ip}"
}
