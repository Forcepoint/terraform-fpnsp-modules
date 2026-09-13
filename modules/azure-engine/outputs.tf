output "id" {
  description = "Fully qualified resource identifier of the engine virtual machine."
  value       = azurerm_linux_virtual_machine.engine.id
}

output "name" {
  description = "Name of the engine virtual machine."
  value       = azurerm_linux_virtual_machine.engine.name
}

output "resource_group_name" {
  description = "Resource group the engine runs in."
  value       = azurerm_linux_virtual_machine.engine.resource_group_name
}

output "location" {
  description = "Location the engine runs in."
  value       = azurerm_linux_virtual_machine.engine.location
}

output "instance" {
  description = <<-EOT
    The full `azurerm_linux_virtual_machine` object, for attributes this
    module does not surface.
  EOT
  value       = azurerm_linux_virtual_machine.engine
  sensitive   = true
}

output "private_ips" {
  description = <<-EOT
    Private IPv4 address per interface, keyed `nic0`, `nic1`, and so on.
  EOT
  value = {
    for key, interface in azurerm_network_interface.engine :
    key => interface.private_ip_address
  }
}

output "public_ips" {
  description = <<-EOT
    Public IPv4 address per IP configuration the module gave a public IP,
    keyed `nic<N>` for an interface's first configuration and
    `nic<N>-<number>` for the others. Existing public IPs are absent.
  EOT
  value = {
    for key, public_ip in azurerm_public_ip.engine :
    key => public_ip.ip_address
  }
}

output "public_ip_ids" {
  description = <<-EOT
    Resource ID of the public IP attached to each IP configuration that has
    one, keyed like `public_ips`.
  EOT
  value       = local.public_ip_ids
}

output "management_private_ip" {
  description = "Private IPv4 address of `nic0`, the SMC management address."
  value       = azurerm_network_interface.engine["nic0"].private_ip_address
}

output "management_public_ip" {
  description = <<-EOT
    Public IPv4 address of `nic0`'s first IP configuration, or `null` when it
    has none.
  EOT
  value       = try(azurerm_public_ip.engine["nic0"].ip_address, null)
}

output "network_interfaces" {
  description = <<-EOT
    Per-interface `index`, `name`, `subnet_id`, `private_ip`, `public_ip`
    and `ip_configurations`, keyed by NIC name.
  EOT
  value = {
    for index, nic in var.network_interfaces :
    format("nic%d", index) => {
      index      = index
      name       = azurerm_network_interface.engine[format("nic%d", index)].name
      subnet_id  = nic.ip_configuration[0].subnet_id
      private_ip = azurerm_network_interface.engine[format("nic%d", index)].private_ip_address
      public_ip  = try(azurerm_public_ip.engine[format("nic%d", index)].ip_address, null)
      ip_configurations = [
        for s, config in nic.ip_configuration : {
          name       = azurerm_network_interface.engine[format("nic%d", index)].ip_configuration[s].name
          subnet_id  = config.subnet_id
          private_ip = azurerm_network_interface.engine[format("nic%d", index)].ip_configuration[s].private_ip_address
          public_ip = try(
            azurerm_public_ip.engine[s == 0 ? format("nic%d", index) : format("nic%d-%d", index, s + 1)].ip_address,
            null
          )
        }
      ]
    }
  }
}
