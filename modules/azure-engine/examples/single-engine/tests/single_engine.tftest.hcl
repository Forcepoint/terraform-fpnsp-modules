# The provider is mocked, so every assertion must hold at plan time.
#
# Computed IDs are unknown at plan; compare names and configured values
# instead.

mock_provider "azurerm" {}

variables {
  resource_group_name = "example-rg"
  allowed_cidrs       = ["198.51.100.10/32"]
  ssh_public_keys     = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHH6MBe8CCHwOgcBIIy6rE6F8A5SpJvYyOtwhEXWNOLH me@example"]
}

run "one_subnet_per_interface" {
  command = plan

  assert {
    condition     = length(azurerm_subnet.this) == 3
    error_message = "The engine needs a management, a LAN and a WAN subnet."
  }

  assert {
    condition     = length(distinct([for subnet in local.subnets : subnet.cidr])) == 3
    error_message = "The three subnets must not overlap."
  }

  assert {
    condition     = keys(module.engine.network_interfaces) == ["nic0", "nic1", "nic2"]
    error_message = "The engine must have management, LAN and WAN interfaces, in guest order."
  }
}

run "management_and_wan_are_public_lan_is_not" {
  command = plan

  assert {
    condition     = keys(module.engine.public_ips) == ["nic0", "nic2"]
    error_message = "Management and WAN get public addresses; LAN does not."
  }
}

run "the_protected_route_points_at_the_lan_interface" {
  command = plan

  # The route blocks are a set, so select by name.
  assert {
    condition     = [for route in azurerm_route_table.lan.route : route if route.name == "default-via-engine"][0].address_prefix == "0.0.0.0/0"
    error_message = "Protected workloads' default route must go through the engine."
  }

  assert {
    condition     = [for route in azurerm_route_table.lan.route : route if route.name == "default-via-engine"][0].next_hop_type == "VirtualAppliance"
    error_message = "The route must hand traffic to the engine, not to the internet."
  }

  assert {
    condition     = [for route in azurerm_route_table.lan.route : route if route.name == "default-via-engine"][0].next_hop_in_ip_address == cidrhost(var.lan_cidr, 10)
    error_message = "The route must point at the pinned address of the engine's LAN interface."
  }
}

run "the_control_bypass_cidrs_bypass_the_engine" {
  command = plan

  variables {
    control_bypass_cidrs = ["198.51.100.20/32"]
  }

  # Without these routes the workloads' replies to the administrative
  # networks would follow the default route through the engine, and the
  # workloads would be unreachable from there when the engine is down.
  assert {
    condition     = [for route in azurerm_route_table.lan.route : route.address_prefix if route.next_hop_type == "Internet"] == ["198.51.100.20/32"]
    error_message = "Only the control bypass CIDRs may go around the engine."
  }
}

run "the_control_bypass_is_off_by_default" {
  command = plan

  assert {
    condition     = length([for route in azurerm_route_table.lan.route : route if route.next_hop_type == "Internet"]) == 0
    error_message = "Without control bypass CIDRs, no route may go around the engine."
  }
}

run "the_bastion_subnet_keeps_a_direct_route_when_the_engine_is_down" {
  command = plan

  variables {
    enable_bastion = true
  }

  # Without this route the workloads' replies to the Bastion data plane
  # would follow the default route through the engine, and Bastion would
  # die with the engine.
  assert {
    condition     = length(azurerm_route_table.lan.route) == 2
    error_message = "The LAN route table must carry only the default route and the Bastion route."
  }

  assert {
    condition     = [for route in azurerm_route_table.lan.route : route if route.name == "to-bastion"][0].address_prefix == var.bastion_subnet_cidr
    error_message = "The bypass route must select the Bastion subnet."
  }

  assert {
    condition     = [for route in azurerm_route_table.lan.route : route if route.name == "to-bastion"][0].next_hop_type == "VnetLocal"
    error_message = "The bypass route must go to the virtual network, not the engine."
  }

  assert {
    condition     = [for rule in azurerm_network_security_group.lan.security_rule : rule if rule.name == "allow-bastion-ssh"][0].destination_port_range == "22"
    error_message = "The LAN NSG must allow Bastion's SSH to the workloads."
  }

  assert {
    condition     = [for rule in azurerm_network_security_group.lan.security_rule : rule if rule.name == "allow-bastion-ssh"][0].source_address_prefix == var.bastion_subnet_cidr
    error_message = "The SSH rule for Bastion must be scoped to the Bastion subnet."
  }
}

run "management_is_not_open_to_the_world" {
  command = plan

  assert {
    condition     = !contains([for rule in azurerm_network_security_group.management.security_rule : rule if rule.name == "allow-admins-and-smc"][0].source_address_prefixes, "0.0.0.0/0")
    error_message = "The management interface must never be open to the internet."
  }

  assert {
    condition     = [for rule in azurerm_network_security_group.management.security_rule : rule if rule.name == "allow-admins-and-smc"][0].source_address_prefixes == toset(var.allowed_cidrs)
    error_message = "The management rule must admit exactly the allowed sources."
  }
}

run "the_rules_restrict_by_source_not_by_port" {
  command = plan

  assert {
    condition = alltrue([
      for rule in azurerm_network_security_group.management.security_rule :
      rule.direction == "Inbound" && rule.protocol == "*" && rule.destination_port_range == "*"
      if rule.name != "allow-outbound"
    ])
    error_message = "The management rules must allow every protocol and port from their sources."
  }

  assert {
    condition = alltrue([
      for rule in azurerm_network_security_group.wan.security_rule :
      rule.direction == "Inbound" && rule.protocol == "*" && rule.destination_port_range == "*"
      if rule.name != "allow-outbound"
    ])
    error_message = "The WAN rules must allow every protocol and port from their sources."
  }
}

run "ssh_to_the_server_is_scoped_to_the_allowed_sources" {
  command = plan

  assert {
    condition     = [for rule in azurerm_network_security_group.lan.security_rule : rule if rule.name == "allow-ssh-to-server"][0].destination_port_range == "22"
    error_message = "The test server is reachable over SSH only."
  }

  assert {
    condition     = [for rule in azurerm_network_security_group.lan.security_rule : rule if rule.name == "allow-ssh-to-server"][0].source_address_prefixes == toset(var.allowed_cidrs)
    error_message = "SSH to the test server must come from the allowed sources only."
  }
}

run "initial_contact_reaches_user_data" {
  command = plan

  variables {
    initial_contact = "stonegate/system/hostname string engine\n"
  }

  assert {
    condition     = module.engine.instance.custom_data == base64encode("stonegate/system/hostname string engine\n")
    error_message = "initial_contact must reach the engine's custom data base64-encoded."
  }
}

run "ssh_keys_reach_the_engine" {
  command = plan

  assert {
    condition     = length(module.engine.instance.admin_ssh_key) == 1
    error_message = "The public key must reach the engine."
  }

  assert {
    condition     = [for key in module.engine.instance.admin_ssh_key : key.username] == ["azure"]
    error_message = "The keys must be installed for admin_username."
  }
}

run "the_protected_server_sits_in_the_lan_subnet" {
  command = plan

  # Subnet IDs are unknown at plan, so assert on the pinned address and the
  # NIC name.
  assert {
    condition     = azurerm_network_interface.server.ip_configuration[0].private_ip_address == cidrhost(var.lan_cidr, 120)
    error_message = "The protected server must sit in the LAN subnet, behind the engine."
  }

  assert {
    condition     = azurerm_network_interface.server.name == "${var.name}-server"
    error_message = "The server NIC must be named after the example."
  }

  assert {
    condition     = length(azurerm_linux_virtual_machine.server.admin_ssh_key) == 1
    error_message = "The server must take an SSH key, so the egress route can be verified."
  }
}

run "the_engine_uses_the_template" {
  command = plan

  # Set rather than defaulted: terraform test also reads a local
  # terraform.tfvars, which may choose the BYOL plan.
  variables {
    engine_image_sku = "ngfw_payg"
  }

  assert {
    condition     = module.engine.instance.plan[0].publisher == "forcepoint-llc"
    error_message = "The engine must boot from the Forcepoint marketplace template."
  }

  assert {
    condition     = module.engine.instance.source_image_reference[0].version == var.engine_image_version
    error_message = "The pinned template version must reach the engine."
  }

  assert {
    condition     = module.engine.instance.plan[0].name == "ngfw_payg"
    error_message = "The pay-as-you-go plan must reach the engine."
  }
}

run "the_byol_plan_reaches_the_engine" {
  command = plan

  variables {
    engine_image_sku = "ngfw_byol"
  }

  assert {
    condition     = module.engine.instance.plan[0].name == "ngfw_byol"
    error_message = "The chosen plan must reach the engine's plan."
  }

  assert {
    condition     = module.engine.instance.source_image_reference[0].sku == "ngfw_byol"
    error_message = "The chosen plan must reach the engine's image."
  }
}

run "the_bastion_host_sits_in_the_reserved_subnet" {
  command = plan

  variables {
    enable_bastion = true
  }

  assert {
    condition     = azurerm_bastion_host.this[0].sku == "Standard"
    error_message = "The Bastion host must use the Standard SKU for the native client."
  }

  # The ip_configuration's subnet_id is computed, so assert on the subnet
  # itself and the configured block instead.
  assert {
    condition     = azurerm_bastion_host.this[0].ip_configuration[0].name == "bastion"
    error_message = "The Bastion host must carry one IP configuration."
  }

  assert {
    condition     = azurerm_subnet.bastion[0].name == "AzureBastionSubnet"
    error_message = "The Bastion subnet must carry the exact reserved name."
  }

  assert {
    condition     = azurerm_bastion_host.this[0].tunneling_enabled
    error_message = "Tunneling must be enabled on the Bastion host."
  }
}
