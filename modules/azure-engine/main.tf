locals {
  interfaces = {
    for index, nic in var.network_interfaces : format("nic%d", index) => nic
  }

  # Keyed nic<N> for an interface's first configuration, nic<N>-<number> for
  # the others.
  ip_configurations = merge([
    for nic_key, nic in local.interfaces : {
      for index, config in nic.ip_configuration :
      (index == 0 ? nic_key : format("%s-%d", nic_key, index + 1)) => config
    }
  ]...)

  public_ip_configurations = {
    for key, config in local.ip_configurations : key => config
    if config.public_ip != null
  }

  module_public_ips = {
    for key, config in local.public_ip_configurations : key => azurerm_public_ip.engine[key].id
  }

  # A zonal virtual machine needs zonal public IPs.
  public_ip_zones = {
    for key, config in local.public_ip_configurations :
    key => (
      config.public_ip.zone != null ?
      config.public_ip.zone :
      (var.zone != null ? tostring(var.zone) : null)
    )
  }

  public_ip_ids = {
    for key, config in local.ip_configurations :
    key => lookup(local.module_public_ips, key, config.public_ip_address_id)
    if config.public_ip != null || config.public_ip_address_id != null
  }
}

resource "azurerm_public_ip" "engine" {
  for_each = local.public_ip_configurations

  name                    = coalesce(each.value.public_ip.name, format("%s-%s-pip", var.name, each.key))
  location                = var.location
  resource_group_name     = var.resource_group_name
  allocation_method       = each.value.public_ip.allocation_method
  sku                     = each.value.public_ip.sku
  ip_version              = each.value.public_ip.ip_version
  zones                   = local.public_ip_zones[each.key] == null ? null : [local.public_ip_zones[each.key]]
  domain_name_label       = each.value.public_ip.domain_name_label
  idle_timeout_in_minutes = each.value.public_ip.idle_timeout_in_minutes
  ddos_protection_plan_id = each.value.public_ip.ddos_protection_plan_id
}

resource "azurerm_network_interface" "engine" {
  for_each              = local.interfaces
  name                  = coalesce(each.value.name, format("%s-%s", var.name, each.key))
  location              = var.location
  resource_group_name   = var.resource_group_name
  ip_forwarding_enabled = each.value.ip_forwarding
  dns_servers           = each.value.dns_servers

  dynamic "ip_configuration" {
    for_each = each.value.ip_configuration

    content {
      name = coalesce(
        ip_configuration.value.name,
        ip_configuration.key == 0 ?
        format("ip-%s", each.key) :
        format("ip-%s-%d", each.key, ip_configuration.key + 1)
      )
      primary                       = ip_configuration.value.primary
      subnet_id                     = ip_configuration.value.subnet_id
      private_ip_address_allocation = ip_configuration.value.private_ip_address_allocation
      private_ip_address            = ip_configuration.value.private_ip_address
      private_ip_address_version    = ip_configuration.value.private_ip_address_version
      public_ip_address_id = lookup(
        local.public_ip_ids,
        ip_configuration.key == 0 ? each.key : format("%s-%d", each.key, ip_configuration.key + 1),
        null
      )
    }
  }
}

resource "azurerm_network_interface_security_group_association" "engine" {
  for_each = {
    for key, nic in local.interfaces : key => nic
    if nic.network_security_group_id != null
  }

  network_interface_id      = azurerm_network_interface.engine[each.key].id
  network_security_group_id = each.value.network_security_group_id
}

resource "azurerm_linux_virtual_machine" "engine" {
  name                            = var.name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  size                            = var.size
  zone                            = var.zone
  computer_name                   = var.computer_name
  admin_username                  = var.admin_username
  priority                        = var.priority
  eviction_policy                 = var.eviction_policy
  max_bid_price                   = var.max_bid_price
  availability_set_id             = var.availability_set_id
  capacity_reservation_group_id   = var.capacity_reservation_group_id
  dedicated_host_id               = var.dedicated_host_id
  dedicated_host_group_id         = var.dedicated_host_group_id
  disk_controller_type            = var.disk_controller_type
  disable_password_authentication = true

  # List order is guest interface order: the first ID is nic0.
  network_interface_ids = [
    for index, nic in var.network_interfaces :
    azurerm_network_interface.engine[format("nic%d", index)].id
  ]

  # Azure decodes the custom data before the guest reads it. A change
  # replaces the virtual machine.
  custom_data = var.initial_contact == null ? null : base64encode(var.initial_contact)

  # A marketplace image requires the plan; a custom image carries none.
  dynamic "plan" {
    for_each = var.source_image.image_id == null ? [var.source_image] : []

    content {
      publisher = plan.value.publisher
      product   = plan.value.offer
      name      = plan.value.sku
    }
  }

  dynamic "source_image_reference" {
    for_each = var.source_image.image_id == null ? [var.source_image] : []

    content {
      publisher = source_image_reference.value.publisher
      offer     = source_image_reference.value.offer
      sku       = source_image_reference.value.sku
      version   = source_image_reference.value.version
    }
  }

  source_image_id = var.source_image.image_id

  dynamic "admin_ssh_key" {
    for_each = var.ssh_public_keys

    content {
      username   = var.admin_username
      public_key = trimspace(admin_ssh_key.value)
    }
  }

  dynamic "identity" {
    for_each = var.identity == null ? [] : [var.identity]

    content {
      type         = identity.value.type
      identity_ids = identity.value.identity_ids
    }
  }

  dynamic "boot_diagnostics" {
    for_each = var.boot_diagnostics.enabled ? [var.boot_diagnostics] : []

    content {
      storage_account_uri = boot_diagnostics.value.storage_account_uri
    }
  }

  os_disk {
    caching                = var.os_disk.caching
    disk_size_gb           = var.os_disk.disk_size_gb
    storage_account_type   = var.os_disk.storage_account_type
    disk_encryption_set_id = var.os_disk.disk_encryption_set_id
  }

  tags = var.tags
}
