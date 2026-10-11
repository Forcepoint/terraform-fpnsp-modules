output "resource_group_id" {
  description = "Resource ID of the resource group."
  value       = azurerm_resource_group.this.id
}

output "virtual_networks" {
  description = "Resource ID of the hub and the spoke virtual network."
  value = {
    hub   = azurerm_virtual_network.hub.id
    spoke = azurerm_virtual_network.spoke.id
  }
}

output "subnets" {
  description = "Resource ID of each subnet, keyed `hub-management`, `hub-lan`, `hub-wan`, `spoke-a` and `spoke-b`."
  value = merge(
    { for key, subnet in azurerm_subnet.hub : "hub-${key}" => subnet.id },
    { for key, subnet in azurerm_subnet.spoke : "spoke-${key}" => subnet.id },
  )
}

output "route_table" {
  description = "Resource ID of the servers' shared route table."
  value       = azurerm_route_table.spoke.id
}

output "engine_ids" {
  description = "Resource ID of each engine virtual machine."
  value = {
    primary   = module.primary.id
    secondary = module.secondary.id
  }
}

output "management_public_ips" {
  description = "Public IPv4 address of each engine's management interface."
  value = {
    primary   = module.primary.management_public_ip
    secondary = module.secondary.management_public_ip
  }
}

output "reserved_public_ips" {
  description = "Public IPv4 address of each reserved public IP, keyed `vpn`, `weba` and `webb` when `wan_floating_ip` is set."
  value = {
    for key, pip in azurerm_public_ip.ha : key => pip.ip_address
  }
}

output "reserved_public_ip_ids" {
  description = "Resource ID of each reserved public IP, keyed `vpn`, `weba` and `webb` when `wan_floating_ip` is set."
  value = {
    for key, pip in azurerm_public_ip.ha : key => pip.id
  }
}

output "wan_public_ips" {
  description = <<-EOT
    Public IPv4 address of each engine's WAN interface, keyed `primary` and
    `secondary`, when `wan_floating_ip` is off.
  EOT
  value = var.wan_floating_ip ? null : {
    primary   = module.primary.public_ips["nic2"]
    secondary = module.secondary.public_ips["nic2"]
  }
}

output "ha_tags" {
  description = <<-EOT
    The `FP_HA_` tags the cloud HA failover script reads from the engines'
    tags.
  EOT
  value       = local.ha_tags
}

output "identity" {
  description = <<-EOT
    The failover identity, its client ID and its principal ID, when
    `enable_ha_identity` is set.
  EOT
  value = var.enable_ha_identity ? {
    id           = azurerm_user_assigned_identity.ha[0].id
    client_id    = azurerm_user_assigned_identity.ha[0].client_id
    principal_id = azurerm_user_assigned_identity.ha[0].principal_id
  } : null
}

output "server_internal_ips" {
  description = "Private IPv4 address of each server, keyed `a` and `b`."
  value = {
    for key, server in local.servers : key => server.ip
  }
}

output "ssh_commands" {
  description = "SSH to the engines' management interfaces."
  value = {
    primary   = "ssh ${var.admin_username}@${module.primary.management_public_ip}"
    secondary = "ssh ${var.admin_username}@${module.secondary.management_public_ip}"
  }
}

output "server_ssh_commands" {
  description = "SSH to the servers."
  value = {
    for key, pip in azurerm_public_ip.server : key => "ssh ${var.server_user}@${pip.ip_address}"
  }
}
