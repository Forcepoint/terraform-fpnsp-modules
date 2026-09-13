output "management_public_ip" {
  description = <<-EOT
    Public address of nic0, the SMC contact address and SSH target.
  EOT
  value       = module.engine.management_public_ip
}

output "wan_public_ip" {
  description = <<-EOT
    Public address of nic2, the WAN interface. For example the local VPN
    endpoint.
  EOT
  value       = try(module.engine.public_ips["nic2"], null)
}

output "network_interfaces" {
  description = "Per-interface index, subnet and addresses."
  value       = module.engine.network_interfaces
}

output "resource_group_id" {
  description = "ID of the resource group."
  value       = azurerm_resource_group.this.id
}

output "virtual_network_id" {
  description = "ID of the virtual network."
  value       = azurerm_virtual_network.this.id
}

output "subnets" {
  description = "IDs of the three subnets, keyed by role."
  value       = { for key, subnet in azurerm_subnet.this : key => subnet.id }
}

output "server_internal_ip" {
  description = "Private address of the protected test server."
  value       = azurerm_network_interface.server.private_ip_address
}

output "server_ssh_command" {
  description = "SSH command for the protected test server."
  value       = "ssh ${var.server_user}@${azurerm_public_ip.server.ip_address}"
}

output "bastion_ssh_command" {
  description = <<-EOT
    SSH to the protected test server over Bastion. This path does not go
    through the engine: the LAN route table keeps the Bastion subnet
    reachable directly, so it works when the engine is down. null unless
    `enable_bastion` is set.
  EOT
  value = var.enable_bastion ? (
    "az network bastion ssh --name ${azurerm_bastion_host.this[0].name} --resource-group ${azurerm_resource_group.this.name} --target-resource-id ${azurerm_resource_group.this.id}/providers/Microsoft.Compute/virtualMachines/${azurerm_linux_virtual_machine.server.name} --username ${var.server_user} --auth-type ssh-key"
  ) : null
}

output "ssh_command" {
  description = "SSH command for the engine."
  value       = "ssh ${var.admin_username}@${module.engine.management_public_ip}"
}
