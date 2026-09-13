# The provider is mocked, so every assertion must hold at plan time.
#
# The resource IDs below are not real: they exist only to satisfy the
# provider's plan-time ID parsing, so they must keep the Azure resource ID
# shape.

mock_provider "azurerm" {}

variables {
  name                = "engine-test"
  resource_group_name = "engine-test-rg"
  location            = "westeurope"
  size                = "Standard_B4ms"
  ssh_public_keys     = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHH6MBe8CCHwOgcBIIy6rE6F8A5SpJvYyOtwhEXWNOLH me@example"]

  network_interfaces = [
    {
      ip_configuration = [
        {
          subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/mgmt"
          public_ip = {}
        },
      ]
    },
    {
      ip_configuration = [
        {
          subnet_id                     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/lan"
          private_ip_address_allocation = "Static"
          private_ip_address            = "10.0.1.10"
        },
      ]
    },
    {
      ip_configuration = [
        {
          subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/wan"
          public_ip = {}
        },
      ]
    },
  ]
}

run "the_template_is_the_default_image" {
  command = plan

  assert {
    condition     = azurerm_linux_virtual_machine.engine.plan[0].publisher == "forcepoint-llc"
    error_message = "The marketplace plan must default to the Forcepoint publisher."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.engine.plan[0].product == "forcepoint-ngfw"
    error_message = "The marketplace plan must default to the Forcepoint product."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.engine.plan[0].name == "ngfw_payg"
    error_message = "The marketplace plan must default to the pay-as-you-go plan."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.engine.source_image_reference[0].offer == "forcepoint-ngfw"
    error_message = "The image reference must point at the template."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.engine.source_image_reference[0].sku == "ngfw_payg"
    error_message = "The image reference must point at the pay-as-you-go plan."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.engine.source_image_reference[0].version == "7.3.5"
    error_message = "The template version must default to the pinned revision."
  }
}

run "a_custom_image_replaces_the_template" {
  command = plan

  variables {
    source_image = {
      image_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Compute/images/engine-7-5-1"
    }
  }

  assert {
    condition     = length(azurerm_linux_virtual_machine.engine.plan) == 0
    error_message = "A custom image must not carry a marketplace plan."
  }

  assert {
    condition     = length(azurerm_linux_virtual_machine.engine.source_image_reference) == 0
    error_message = "A custom image must not reference the marketplace."
  }

  assert {
    condition     = endswith(azurerm_linux_virtual_machine.engine.source_image_id, "/images/engine-7-5-1")
    error_message = "The custom image ID must reach the virtual machine."
  }
}

run "a_template_version_can_be_pinned" {
  command = plan

  variables {
    source_image = { version = "7.5.1" }
  }

  assert {
    condition     = azurerm_linux_virtual_machine.engine.source_image_reference[0].version == "7.5.1"
    error_message = "A pinned template version must reach the image reference."
  }
}

run "interfaces_follow_guest_order" {
  command = plan

  assert {
    condition     = keys(azurerm_network_interface.engine) == ["nic0", "nic1", "nic2"]
    error_message = "The per-interface resources must be keyed in guest order, nic0 first."
  }

  assert {
    condition     = azurerm_network_interface.engine["nic0"].ip_configuration[0].subnet_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/mgmt"
    error_message = "The management interface must sit in the first subnet."
  }

  assert {
    condition     = azurerm_network_interface.engine["nic1"].ip_configuration[0].subnet_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/lan"
    error_message = "The second interface must sit in the LAN subnet."
  }

  assert {
    condition     = azurerm_network_interface.engine["nic1"].ip_configuration[0].private_ip_address == "10.0.1.10"
    error_message = "A pinned private address must reach the NIC unchanged."
  }

  assert {
    condition     = keys(azurerm_public_ip.engine) == ["nic0", "nic2"]
    error_message = "Only the interfaces that ask for a public IP may get one."
  }

  assert {
    condition     = keys(output.network_interfaces) == ["nic0", "nic1", "nic2"]
    error_message = "The per-interface outputs must be keyed in guest order, nic0 first."
  }
}

run "a_module_created_public_ip_is_attached" {
  command = plan

  # The attachment itself references the public IP's ID, unknown at plan;
  # assert on the names instead, which are derived from the inputs.
  assert {
    condition     = azurerm_public_ip.engine["nic0"].name == "engine-test-nic0-pip"
    error_message = "A module-created public IP must be named after the machine and the interface."
  }

  assert {
    condition     = azurerm_network_interface.engine["nic0"].name == "engine-test-nic0"
    error_message = "The network interface must default to the name <name>-<nic>."
  }

  assert {
    condition     = azurerm_public_ip.engine["nic0"].sku == "Standard"
    error_message = "The public IP must default to the Standard SKU."
  }

  assert {
    condition     = azurerm_public_ip.engine["nic0"].allocation_method == "Static"
    error_message = "The public IP must default to a static allocation."
  }
}

run "a_public_ip_object_reaches_the_public_ip" {
  command = plan

  variables {
    network_interfaces = [
      {
        ip_configuration = [
          {
            subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/mgmt"
            public_ip = {
              name                    = "my-pip"
              domain_name_label       = "engine-a"
              idle_timeout_in_minutes = 30
            }
          },
        ]
      },
    ]
  }

  assert {
    condition     = azurerm_public_ip.engine["nic0"].name == "my-pip"
    error_message = "A named public IP must use the given name."
  }

  assert {
    condition     = azurerm_public_ip.engine["nic0"].domain_name_label == "engine-a"
    error_message = "The domain name label must reach the public IP."
  }

  assert {
    condition     = azurerm_public_ip.engine["nic0"].idle_timeout_in_minutes == 30
    error_message = "The idle timeout must reach the public IP."
  }
}

run "a_zoned_vm_gives_its_zone_to_the_public_ip" {
  command = plan

  variables {
    zone = 1
  }

  assert {
    condition     = contains(azurerm_public_ip.engine["nic0"].zones, "1")
    error_message = "A public IP on a zonal virtual machine must inherit the zone."
  }
}

run "a_customer_public_ip_is_attached_unmodified" {
  command = plan

  variables {
    network_interfaces = [
      {
        ip_configuration = [
          {
            subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/mgmt"
            public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/publicIPAddresses/mine"
          },
        ]
      },
    ]
  }

  assert {
    condition     = length(azurerm_public_ip.engine) == 0
    error_message = "The module must not create a public IP when one is given."
  }

  assert {
    condition     = endswith(azurerm_network_interface.engine["nic0"].ip_configuration[0].public_ip_address_id, "/publicIPAddresses/mine")
    error_message = "The customer's public IP must be attached unmodified."
  }

  assert {
    condition     = output.public_ip_ids["nic0"] == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/publicIPAddresses/mine"
    error_message = "The customer's public IP ID must be surfaced in public_ip_ids."
  }
}

run "initial_contact_becomes_custom_data" {
  command = plan

  variables {
    initial_contact = "stonegate/system/hostname string engine-test\n"
  }

  assert {
    condition     = azurerm_linux_virtual_machine.engine.custom_data == base64encode("stonegate/system/hostname string engine-test\n")
    error_message = "initial_contact must reach the custom data base64-encoded, unmodified otherwise."
  }
}

run "a_cloud_contact_document_is_accepted" {
  command = plan

  variables {
    initial_contact = "{\"smc-contact\":{\"address\":\"smc.example.com\",\"apikey\":\"secret\"},\"type\":\"single-firewall\"}"
  }

  assert {
    condition     = can(jsondecode(base64decode(azurerm_linux_virtual_machine.engine.custom_data)))
    error_message = "A cloud contact document must pass through the custom data unmodified."
  }
}

run "no_custom_data_without_initial_contact" {
  command = plan

  assert {
    condition     = azurerm_linux_virtual_machine.engine.custom_data == null
    error_message = "Without initial_contact there must be no custom data at all."
  }
}

run "ssh_keys_reach_the_virtual_machine" {
  command = plan

  assert {
    condition     = length(azurerm_linux_virtual_machine.engine.admin_ssh_key) == 1
    error_message = "Every public key must reach the virtual machine."
  }

  assert {
    condition     = [for key in azurerm_linux_virtual_machine.engine.admin_ssh_key : key.username] == ["azure"]
    error_message = "The keys must be installed for admin_username."
  }

  assert {
    condition     = alltrue([for key in azurerm_linux_virtual_machine.engine.admin_ssh_key : endswith(key.public_key, "me@example")])
    error_message = "The key material must reach the virtual machine unchanged."
  }
}

run "password_authentication_is_disabled" {
  command = plan

  assert {
    condition     = azurerm_linux_virtual_machine.engine.disable_password_authentication
    error_message = "The engine virtual machine must never take a password."
  }
}

run "ip_forwarding_is_on_by_default" {
  command = plan

  assert {
    condition     = alltrue([for nic in azurerm_network_interface.engine : nic.ip_forwarding_enabled])
    error_message = "An engine must be allowed to forward packets on every interface."
  }
}

run "ip_forwarding_can_be_disabled_per_interface" {
  command = plan

  variables {
    network_interfaces = [
      {
        ip_forwarding = false
        ip_configuration = [
          {
            subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/lan"
          },
        ]
      },
    ]
  }

  assert {
    condition     = !azurerm_network_interface.engine["nic0"].ip_forwarding_enabled
    error_message = "A per-interface ip_forwarding = false must reach the NIC."
  }
}

run "nic_attributes_reach_the_network_interface" {
  command = plan

  variables {
    network_interfaces = [
      {
        name                      = "my-nic"
        dns_servers               = ["10.0.0.53"]
        network_security_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/networkSecurityGroups/nsg1"
        ip_configuration = [
          {
            subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/mgmt"
          },
        ]
      },
    ]
  }

  assert {
    condition     = azurerm_network_interface.engine["nic0"].name == "my-nic"
    error_message = "A named network interface must use the given name."
  }

  assert {
    condition     = contains(azurerm_network_interface.engine["nic0"].dns_servers, "10.0.0.53")
    error_message = "The DNS servers must reach the network interface."
  }

  assert {
    condition     = endswith(azurerm_network_interface_security_group_association.engine["nic0"].network_security_group_id, "/networkSecurityGroups/nsg1")
    error_message = "The network security group must attach to the network interface."
  }
}

run "an_ipv6_allocation_is_accepted" {
  command = plan

  variables {
    network_interfaces = [
      {
        ip_configuration = [
          {
            subnet_id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/mgmt"
            private_ip_address_version = "IPv6"
          },
        ]
      },
    ]
  }

  assert {
    condition     = azurerm_network_interface.engine["nic0"].ip_configuration[0].private_ip_address_version == "IPv6"
    error_message = "The IP version must reach the IP configuration."
  }
}

run "os_disk_defaults" {
  command = plan

  # disk_size_gb is computed from the image's minimum when unset, so it is
  # unknown at plan; assert on the configured attributes instead.
  assert {
    condition     = azurerm_linux_virtual_machine.engine.os_disk[0].caching == "ReadWrite"
    error_message = "The caching setting must default to ReadWrite."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.engine.os_disk[0].storage_account_type == "StandardSSD_LRS"
    error_message = "The storage account type must default to StandardSSD_LRS."
  }
}

run "os_disk_settings_reach_the_virtual_machine" {
  command = plan

  variables {
    os_disk = {
      caching              = "None"
      disk_size_gb         = 128
      storage_account_type = "Premium_LRS"
    }
  }

  assert {
    condition     = azurerm_linux_virtual_machine.engine.os_disk[0].caching == "None"
    error_message = "The caching setting must reach the os_disk block."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.engine.os_disk[0].disk_size_gb == 128
    error_message = "The disk size must reach the os_disk block."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.engine.os_disk[0].storage_account_type == "Premium_LRS"
    error_message = "The storage account type must reach the os_disk block."
  }
}

run "an_os_disk_encryption_set_reaches_the_os_disk" {
  command = plan

  variables {
    os_disk = {
      disk_encryption_set_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Compute/diskEncryptionSets/des1"
    }
  }

  assert {
    condition     = endswith(azurerm_linux_virtual_machine.engine.os_disk[0].disk_encryption_set_id, "/diskEncryptionSets/des1")
    error_message = "The disk encryption set must reach the os_disk block."
  }
}

run "the_zone_reaches_the_virtual_machine" {
  command = plan

  variables {
    zone = 2
  }

  assert {
    condition     = tostring(azurerm_linux_virtual_machine.engine.zone) == "2"
    error_message = "The availability zone must reach the virtual machine."
  }
}

run "no_zone_by_default" {
  command = plan

  assert {
    condition     = azurerm_linux_virtual_machine.engine.zone == null
    error_message = "Without a zone the attribute must be omitted."
  }
}

run "vm_attributes_reach_the_virtual_machine" {
  command = plan

  variables {
    computer_name                 = "engine-a.example.com"
    capacity_reservation_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Compute/capacityReservationGroups/crg1"
    dedicated_host_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Compute/hostGroups/host-group1/hosts/host1"
    disk_controller_type          = "NVMe"
  }

  assert {
    condition     = azurerm_linux_virtual_machine.engine.computer_name == "engine-a.example.com"
    error_message = "The computer name must reach the virtual machine."
  }

  assert {
    condition     = endswith(azurerm_linux_virtual_machine.engine.capacity_reservation_group_id, "/capacityReservationGroups/crg1")
    error_message = "The capacity reservation group must reach the virtual machine."
  }

  assert {
    condition     = endswith(azurerm_linux_virtual_machine.engine.dedicated_host_id, "/hosts/host1")
    error_message = "The dedicated host must reach the virtual machine."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.engine.disk_controller_type == "NVMe"
    error_message = "The disk controller type must reach the virtual machine."
  }
}

run "spot_settings_reach_the_virtual_machine" {
  command = plan

  variables {
    priority        = "Spot"
    eviction_policy = "Deallocate"
    max_bid_price   = 0.5
  }

  assert {
    condition     = azurerm_linux_virtual_machine.engine.priority == "Spot"
    error_message = "The spot priority must reach the virtual machine."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.engine.eviction_policy == "Deallocate"
    error_message = "The eviction policy must reach the virtual machine."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.engine.max_bid_price == 0.5
    error_message = "The maximum bid price must reach the virtual machine."
  }
}

run "an_availability_set_reaches_the_virtual_machine" {
  command = plan

  variables {
    availability_set_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Compute/availabilitySets/as1"
  }

  assert {
    condition     = endswith(azurerm_linux_virtual_machine.engine.availability_set_id, "/availabilitySets/as1")
    error_message = "The availability set must reach the virtual machine."
  }
}

run "an_identity_reaches_the_virtual_machine" {
  command = plan

  variables {
    identity = {
      type         = "UserAssigned"
      identity_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/identity1"]
    }
  }

  assert {
    condition     = azurerm_linux_virtual_machine.engine.identity[0].type == "UserAssigned"
    error_message = "The identity type must reach the virtual machine."
  }

  assert {
    condition     = length(azurerm_linux_virtual_machine.engine.identity[0].identity_ids) == 1
    error_message = "The user-assigned identity must reach the virtual machine."
  }
}

run "boot_diagnostics_are_enabled_by_default" {
  command = plan

  assert {
    condition     = length(azurerm_linux_virtual_machine.engine.boot_diagnostics) == 1
    error_message = "Boot diagnostics must be enabled by default: the first boot is the one you cannot watch."
  }
}

run "a_boot_diagnostics_storage_uri_reaches_the_block" {
  command = plan

  variables {
    boot_diagnostics = {
      storage_account_uri = "https://stgacct.blob.core.windows.net"
    }
  }

  assert {
    condition     = azurerm_linux_virtual_machine.engine.boot_diagnostics[0].storage_account_uri == "https://stgacct.blob.core.windows.net"
    error_message = "The storage account URI must reach the boot diagnostics block."
  }
}

run "an_invalid_name_is_rejected" {
  command = plan

  variables {
    name = "Engine_Test"
  }

  expect_failures = [var.name]
}

run "a_long_name_is_rejected" {
  command = plan

  variables {
    name = "abcdefghijklmnopqrstuvwxyz-abcdefghijklmnopqrstuvwxyz-abcde"
  }

  expect_failures = [var.name]
}

run "an_invalid_location_is_rejected" {
  command = plan

  variables {
    location = "West Europe"
  }

  expect_failures = [var.location]
}

run "a_long_location_is_accepted" {
  command = plan

  variables {
    # 18 characters: the longest Azure region name (Germany West Central).
    location = "germanywestcentral"
  }

  assert {
    condition     = azurerm_linux_virtual_machine.engine.location == "germanywestcentral"
    error_message = "A long region name must reach the virtual machine unchanged."
  }
}

run "an_invalid_zone_is_rejected" {
  command = plan

  variables {
    zone = 4
  }

  expect_failures = [var.zone]
}

run "an_interface_is_required" {
  command = plan

  variables {
    network_interfaces = []
  }

  expect_failures = [var.network_interfaces]
}

run "nine_interfaces_are_rejected" {
  command = plan

  variables {
    network_interfaces = [
      for i in range(9) : { ip_configuration = [{ subnet_id = format("subnet-%d", i) }] }
    ]
  }

  expect_failures = [var.network_interfaces]
}

run "duplicate_subnets_are_rejected" {
  command = plan

  variables {
    network_interfaces = [
      { ip_configuration = [{ subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/mgmt" }] },
      { ip_configuration = [{ subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/mgmt" }] },
    ]

  }

  expect_failures = [var.network_interfaces]
}

run "a_static_private_ip_requires_an_address" {
  command = plan

  variables {
    network_interfaces = [
      {
        ip_configuration = [
          {
            subnet_id                     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/mgmt"
            private_ip_address_allocation = "Static"
          },
        ]
      },
    ]
  }

  expect_failures = [var.network_interfaces]
}

run "a_private_ip_requires_static_allocation" {
  command = plan

  variables {
    network_interfaces = [
      { ip_configuration = [{ subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/mgmt", private_ip_address = "10.0.0.10" }] },
    ]

  }

  expect_failures = [var.network_interfaces]
}

run "both_public_ip_options_are_rejected" {
  command = plan

  variables {
    network_interfaces = [
      {
        ip_configuration = [
          {
            subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/mgmt"
            public_ip            = {}
            public_ip_address_id = "an-existing-id"
          },
        ]
      },
    ]
  }

  expect_failures = [var.network_interfaces]
}

run "a_standard_public_ip_requires_static_allocation" {
  command = plan

  variables {
    network_interfaces = [
      {
        ip_configuration = [
          {
            subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/mgmt"
            public_ip = { allocation_method = "Dynamic" }
          },
        ]
      },
    ]
  }

  expect_failures = [var.network_interfaces]
}

run "a_basic_public_ip_cannot_be_zonal" {
  command = plan

  variables {
    network_interfaces = [
      {
        ip_configuration = [
          {
            subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/mgmt"
            public_ip = { sku = "Basic", zone = "1" }
          },
        ]
      },
    ]
  }

  expect_failures = [var.network_interfaces]
}

run "secondary_ip_configurations_reach_the_network_interface" {
  command = plan

  variables {
    network_interfaces = [
      {
        ip_configuration = [
          {
            primary                       = true
            subnet_id                     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/wan"
            private_ip_address_allocation = "Static"
            private_ip_address            = "10.0.100.10"
          },
          {
            subnet_id                     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/wan"
            private_ip_address_allocation = "Static"
            private_ip_address            = "10.0.100.12"
          },
          {
            name                          = "ip-wan-3"
            subnet_id                     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/wan"
            private_ip_address_allocation = "Static"
            private_ip_address            = "10.0.100.14"
          },
        ]
      },
    ]
  }

  assert {
    condition     = length(azurerm_network_interface.engine["nic0"].ip_configuration) == 3
    error_message = "Every ip_configuration must reach the network interface."
  }

  assert {
    condition     = azurerm_network_interface.engine["nic0"].ip_configuration[0].name == "ip-nic0"
    error_message = "The first configuration must keep its default name."
  }

  assert {
    condition     = azurerm_network_interface.engine["nic0"].ip_configuration[1].name == "ip-nic0-2"
    error_message = "The second configuration must take the numbered default name."
  }

  assert {
    condition     = azurerm_network_interface.engine["nic0"].ip_configuration[2].name == "ip-wan-3"
    error_message = "An explicit configuration name must be used."
  }

  assert {
    condition     = azurerm_network_interface.engine["nic0"].ip_configuration[1].subnet_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/wan"
    error_message = "A secondary configuration must sit in its subnet."
  }

  assert {
    condition     = azurerm_network_interface.engine["nic0"].ip_configuration[1].private_ip_address == "10.0.100.12"
    error_message = "A secondary configuration's pinned address must reach the NIC."
  }

  assert {
    condition     = output.network_interfaces["nic0"].ip_configurations[1].private_ip == "10.0.100.12"
    error_message = "The interface output must list the secondary configurations."
  }
}

run "a_secondary_configuration_gets_no_public_ip" {
  command = plan

  variables {
    network_interfaces = [
      {
        ip_configuration = [
          {
            primary                       = true
            subnet_id                     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/wan"
            private_ip_address_allocation = "Static"
            private_ip_address            = "10.0.100.10"
            public_ip                     = {}
          },
          {
            subnet_id                     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/wan"
            private_ip_address_allocation = "Static"
            private_ip_address            = "10.0.100.12"
          },
        ]
      },
    ]
  }

  assert {
    condition     = azurerm_public_ip.engine["nic0"].name == "engine-test-nic0-pip"
    error_message = "The module must create the public IP the first configuration names."
  }

  assert {
    condition     = azurerm_network_interface.engine["nic0"].ip_configuration[1].public_ip_address_id == null
    error_message = "The secondary configuration must not receive the module-created public IP."
  }
}

run "each_configuration_can_carry_a_public_ip" {
  command = plan

  variables {
    network_interfaces = [
      {
        ip_configuration = [
          {
            primary                       = true
            subnet_id                     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/wan"
            private_ip_address_allocation = "Static"
            private_ip_address            = "10.0.100.10"
            public_ip                     = {}
          },
          {
            subnet_id                     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/wan"
            private_ip_address_allocation = "Static"
            private_ip_address            = "10.0.100.12"
            public_ip                     = {}
          },
          {
            subnet_id                     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/wan"
            private_ip_address_allocation = "Static"
            private_ip_address            = "10.0.100.14"
          },
        ]
      },
    ]
  }

  assert {
    condition     = keys(azurerm_public_ip.engine) == ["nic0", "nic0-2"]
    error_message = "Each configuration with a public_ip block must get its own public IP, keyed nic<N>-<number> from the second configuration on."
  }

  assert {
    condition     = azurerm_public_ip.engine["nic0-2"].name == "engine-test-nic0-2-pip"
    error_message = "A secondary configuration's public IP must be named after the machine, the interface and the configuration."
  }

  assert {
    condition     = azurerm_network_interface.engine["nic0"].ip_configuration[2].public_ip_address_id == null
    error_message = "A configuration without a public IP must not receive one."
  }
}

run "an_existing_public_ip_can_sit_beside_a_module_created_one" {
  command = plan

  variables {
    network_interfaces = [
      {
        ip_configuration = [
          {
            primary   = true
            subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/wan"
            public_ip = {}
          },
          {
            subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/wan"
            public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/publicIPAddresses/mine"
          },
        ]
      },
    ]
  }

  assert {
    condition     = keys(azurerm_public_ip.engine) == ["nic0"]
    error_message = "The module must create only the public IP the first configuration asks for."
  }

  assert {
    condition     = endswith(azurerm_network_interface.engine["nic0"].ip_configuration[1].public_ip_address_id, "/publicIPAddresses/mine")
    error_message = "The existing public IP must be attached to the second configuration unmodified."
  }

  assert {
    condition     = keys(output.public_ip_ids) == ["nic0", "nic0-2"]
    error_message = "public_ip_ids must list every configuration that carries a public IP."
  }
}

run "configurations_on_different_subnets_are_rejected" {
  command = plan

  variables {
    network_interfaces = [
      {
        ip_configuration = [
          {
            primary   = true
            subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/mgmt"
          },
          {
            subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/wan"
          },
        ]
      },
    ]
  }

  expect_failures = [var.network_interfaces]
}

run "a_multi_configuration_interface_requires_a_primary" {
  command = plan

  variables {
    network_interfaces = [
      {
        ip_configuration = [
          {
            subnet_id                     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/wan"
            private_ip_address_allocation = "Static"
            private_ip_address            = "10.0.100.10"
          },
          {
            subnet_id                     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/wan"
            private_ip_address_allocation = "Static"
            private_ip_address            = "10.0.100.12"
          },
        ]
      },
    ]
  }

  expect_failures = [var.network_interfaces]
}

run "two_primary_configurations_are_rejected" {
  command = plan

  variables {
    network_interfaces = [
      {
        ip_configuration = [
          {
            primary                       = true
            subnet_id                     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/wan"
            private_ip_address_allocation = "Static"
            private_ip_address            = "10.0.100.10"
          },
          {
            primary                       = true
            subnet_id                     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/wan"
            private_ip_address_allocation = "Static"
            private_ip_address            = "10.0.100.12"
          },
        ]
      },
    ]
  }

  expect_failures = [var.network_interfaces]
}

run "an_interface_requires_a_configuration" {
  command = plan

  variables {
    network_interfaces = [
      {
        ip_configuration = []
      },
    ]
  }

  expect_failures = [var.network_interfaces]
}

run "no_ssh_keys_are_rejected" {
  command = plan

  variables {
    ssh_public_keys = []
  }

  expect_failures = [var.ssh_public_keys]
}

run "garbage_initial_contact_is_rejected" {
  command = plan

  variables {
    initial_contact = "just some text that is neither an engine.cfg nor JSON"
  }

  expect_failures = [var.initial_contact]
}

run "base64_wrapped_initial_contact_is_rejected" {
  command = plan

  variables {
    initial_contact = base64encode("stonegate/system/hostname string engine-test\n")
  }

  expect_failures = [var.initial_contact]
}

run "an_eviction_policy_without_spot_is_rejected" {
  command = plan

  variables {
    eviction_policy = "Delete"
  }

  expect_failures = [var.eviction_policy]
}

run "a_max_bid_price_without_spot_is_rejected" {
  command = plan

  variables {
    max_bid_price = 0.5
  }

  expect_failures = [var.max_bid_price]
}

run "an_invalid_priority_is_rejected" {
  command = plan

  variables {
    priority = "Low"
  }

  expect_failures = [var.priority]
}

run "an_availability_set_with_a_zone_is_rejected" {
  command = plan

  variables {
    zone                = 1
    availability_set_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Compute/availabilitySets/as1"
  }

  expect_failures = [var.availability_set_id]
}

run "a_capacity_reservation_group_with_an_availability_set_is_rejected" {
  command = plan

  variables {
    availability_set_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Compute/availabilitySets/as1"
    capacity_reservation_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Compute/capacityReservationGroups/crg1"
  }

  expect_failures = [var.capacity_reservation_group_id]
}

run "a_dedicated_host_and_group_are_rejected_together" {
  command = plan

  variables {
    dedicated_host_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Compute/hostGroups/host-group1/hosts/host1"
    dedicated_host_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Compute/hostGroups/host-group1"
  }

  expect_failures = [var.dedicated_host_group_id]
}

run "an_invalid_disk_controller_type_is_rejected" {
  command = plan

  variables {
    disk_controller_type = "USB"
  }

  expect_failures = [var.disk_controller_type]
}

run "an_invalid_identity_type_is_rejected" {
  command = plan

  variables {
    identity = { type = "Both" }
  }

  expect_failures = [var.identity]
}

run "a_user_assigned_identity_requires_ids" {
  command = plan

  variables {
    identity = { type = "UserAssigned" }
  }

  expect_failures = [var.identity]
}

run "a_system_assigned_identity_rejects_ids" {
  command = plan

  variables {
    identity = {
      type         = "SystemAssigned"
      identity_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/identity1"]
    }
  }

  expect_failures = [var.identity]
}
