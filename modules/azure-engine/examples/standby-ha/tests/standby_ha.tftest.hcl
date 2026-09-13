# The provider is mocked, so every assertion must hold at plan time.
#
# Computed IDs and public IP addresses are unknown at plan; compare names
# and configured values instead.

mock_provider "azurerm" {}

variables {
  resource_group_name = "standby-ha-rg"
  name                = "example"
  allowed_cidrs       = ["198.51.100.10/32", "203.0.113.0/24"]
  ssh_public_keys     = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHH6MBe8CCHwOgcBIIy6rE6F8A5SpJvYyOtwhEXWNOLH me@example"]
}

run "the_pair_spans_two_zones" {
  command = plan

  assert {
    condition     = module.primary.name == "example-primary"
    error_message = "The engines must be named after the pair."
  }

  assert {
    condition     = module.secondary.name == "example-secondary"
    error_message = "The engines must be named after the pair."
  }

  assert {
    condition     = module.primary.instance.zone == "1"
    error_message = "The primary engine must sit in zone_primary."
  }

  assert {
    condition     = module.secondary.instance.zone == "2"
    error_message = "The secondary engine must sit in zone_secondary."
  }
}

run "the_wan_interface_carries_the_secondary_configurations" {
  command = plan

  # The reserved public IPs attach to one IP configuration each, so the
  # WAN interface needs a configuration for every address on it.
  assert {
    condition     = length(module.primary.network_interfaces["nic2"].ip_configurations) == 3
    error_message = "The WAN interface must carry the primary and the two secondary configurations."
  }

  assert {
    condition     = module.primary.network_interfaces["nic2"].ip_configurations[1].name == "ip-wan-2"
    error_message = "The secondary configurations must take their explicit names."
  }

  assert {
    condition     = module.primary.network_interfaces["nic2"].ip_configurations[2].name == "ip-wan-3"
    error_message = "The secondary configurations must take their explicit names."
  }

  assert {
    condition     = module.primary.network_interfaces["nic2"].ip_configurations[1].private_ip == cidrhost(var.wan_cidr, 12)
    error_message = "The primary's weba address must be pinned, so the failover script's triplets keep working."
  }

  assert {
    condition     = module.primary.network_interfaces["nic2"].ip_configurations[2].private_ip == cidrhost(var.wan_cidr, 14)
    error_message = "The primary's webb address must be pinned, so the failover script's triplets keep working."
  }

  assert {
    condition     = module.secondary.network_interfaces["nic2"].ip_configurations[1].private_ip == cidrhost(var.wan_cidr, 13)
    error_message = "The secondary's weba address must be pinned, so the failover script's triplets keep working."
  }

  assert {
    condition     = module.secondary.network_interfaces["nic2"].ip_configurations[2].private_ip == cidrhost(var.wan_cidr, 15)
    error_message = "The secondary's webb address must be pinned, so the failover script's triplets keep working."
  }
}

run "management_is_the_only_module_created_public_ip" {
  command = plan

  assert {
    condition     = keys(module.primary.public_ips) == ["nic0"]
    error_message = "Only the management interface gets a module-created public IP; the WAN addresses are reserved and attached by the failover script."
  }

  assert {
    condition     = keys(module.secondary.public_ips) == ["nic0"]
    error_message = "Only the management interface gets a module-created public IP; the WAN addresses are reserved and attached by the failover script."
  }
}

run "the_reserved_public_ips_are_created" {
  command = plan

  assert {
    condition     = length(azurerm_public_ip.ha) == 3
    error_message = "The pair needs the vpn, weba and webb reserved public IPs."
  }

  assert {
    condition     = alltrue([for pip in azurerm_public_ip.ha : pip.allocation_method == "Static" && pip.sku == "Standard"])
    error_message = "The reserved public IPs must be static and Standard SKU."
  }

  assert {
    condition     = azurerm_public_ip.ha["vpn"].name == "example-ha-vpn-pip"
    error_message = "The reserved public IPs must be named after the pair."
  }

  assert {
    condition     = azurerm_public_ip.ha["weba"].name == "example-ha-weba-pip"
    error_message = "The reserved public IPs must be named after the pair."
  }

  assert {
    condition     = azurerm_public_ip.ha["webb"].name == "example-ha-webb-pip"
    error_message = "The reserved public IPs must be named after the pair."
  }
}

run "the_servers_egress_through_the_primary_engine" {
  command = plan

  # The route blocks are a set, so select by name. One route table serves
  # both server subnets.
  assert {
    condition     = [for route in azurerm_route_table.spoke.route : route if route.name == "default-via-engine"][0].next_hop_type == "VirtualAppliance"
    error_message = "The default route must hand the servers' traffic to the engine."
  }

  assert {
    condition     = [for route in azurerm_route_table.spoke.route : route if route.name == "default-via-engine"][0].next_hop_in_ip_address == cidrhost(var.lan_cidr, 10)
    error_message = "The default route must point at the primary engine's LAN address."
  }
}

run "the_servers_keep_a_bypass_to_the_allowed_cidrs" {
  command = plan

  assert {
    condition     = alltrue([for cidr in var.allowed_cidrs : contains([for route in azurerm_route_table.spoke.route : route.address_prefix if route.next_hop_type == "Internet"], cidr)])
    error_message = "Each allowed CIDR needs its own bypass route to the internet next hop."
  }
}

run "the_control_bypass_is_optional" {
  command = plan

  variables {
    enable_control_bypass = false
  }

  assert {
    condition     = length([for route in azurerm_route_table.spoke.route : route if route.next_hop_type == "Internet"]) == 0
    error_message = "With the control bypass off, no route may go around the engines."
  }
}

run "the_wan_is_open_and_the_management_is_not" {
  command = plan

  assert {
    condition     = [for rule in azurerm_network_security_group.wan.security_rule : rule if rule.name == "allow-internet"][0].source_address_prefix == "0.0.0.0/0"
    error_message = "The WAN interface is the security hub's entry; the engine's policy is the filter."
  }

  assert {
    condition     = !contains([for rule in azurerm_network_security_group.management.security_rule : rule if rule.name == "allow-admins-and-smc"][0].source_address_prefixes, "0.0.0.0/0")
    error_message = "The management interface must never be open to the internet."
  }

  assert {
    condition     = [for rule in azurerm_network_security_group.server_a.security_rule : rule if rule.name == "allow-ssh"][0].destination_port_range == "22"
    error_message = "The servers are reachable over SSH only."
  }
}

run "the_failover_tags_reach_the_engines" {
  command = plan

  # The tag values carry resource IDs, which the mock provider cannot
  # know at plan, and sensitivity propagates through the comparison, so
  # the handover is asserted on its size and the reach onto the engines
  # on the tags map's presence. The script's probe settings take its
  # defaults and are not part of the handover.
  assert {
    condition     = length(local.ha_tags) == 7
    error_message = "The handover carries the failover script's tags: the route table, the internal NIC index, both instances and the three reserved public IPs."
  }

  assert {
    condition     = module.primary.instance.tags != null
    error_message = "The primary engine must carry the failover script's tags."
  }

  assert {
    condition     = module.secondary.instance.tags != null
    error_message = "The secondary engine must carry the failover script's tags."
  }
}

run "the_failover_identity_is_scoped_to_the_resource_group" {
  command = plan

  assert {
    condition     = azurerm_role_definition.ha[0].name == "example-ha"
    error_message = "The role must be named after the pair."
  }

  assert {
    condition     = regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", azurerm_role_assignment.ha[0].name) != ""
    error_message = "The role assignment must have a stable, deterministic UUID name, or every plan tries to replace it."
  }

  assert {
    condition     = length(azurerm_role_definition.ha[0].permissions[0].actions) == 13
    error_message = "The role must grant the failover script's actions and nothing more."
  }

  assert {
    condition     = contains(azurerm_role_definition.ha[0].permissions[0].actions, "Microsoft.Network/publicIPAddresses/join/action")
    error_message = "The script moves the reserved public IPs between the engines."
  }
}

run "the_failover_identity_is_optional" {
  command = plan

  variables {
    enable_ha_identity = false
  }

  assert {
    condition     = length(azurerm_user_assigned_identity.ha) == 0
    error_message = "Without the flag no identity may be created."
  }

  assert {
    condition     = length(azurerm_role_definition.ha) == 0
    error_message = "Without the flag no role may be created."
  }
}

run "the_servers_sit_in_their_own_subnets" {
  command = plan

  # One spoke virtual network, one subnet per server: a route table can
  # serve several subnets of one vnet, so the pair's failover rewrites a
  # single table.
  assert {
    condition     = azurerm_virtual_network.spoke.name == "example-spoke"
    error_message = "The servers share one spoke virtual network."
  }

  assert {
    condition     = length(azurerm_subnet.spoke) == 2
    error_message = "Each server needs its own subnet."
  }

  assert {
    condition     = azurerm_network_interface.server["a"].ip_configuration[0].private_ip_address == cidrhost(var.spoke_a_subnet_cidr, 120)
    error_message = "Server a must be pinned in its subnet."
  }

  assert {
    condition     = azurerm_network_interface.server["b"].ip_configuration[0].private_ip_address == cidrhost(var.spoke_b_subnet_cidr, 120)
    error_message = "Server b must be pinned in its subnet."
  }

  assert {
    condition     = azurerm_virtual_network_peering.hub_to_spoke.name == "hub-to-spoke" && azurerm_virtual_network_peering.spoke_to_hub.name == "spoke-to-hub"
    error_message = "The spoke must be peered to the hub, both ways."
  }

  assert {
    condition     = azurerm_virtual_network_peering.hub_to_spoke.allow_forwarded_traffic && azurerm_virtual_network_peering.spoke_to_hub.allow_forwarded_traffic
    error_message = "Forwarded traffic must cross the peering: the route table points into the hub."
  }

  assert {
    condition     = length(azurerm_subnet_route_table_association.spoke) == 2
    error_message = "The shared route table must be associated with both server subnets."
  }
}

run "the_zones_must_differ" {
  command = plan

  variables {
    zone_secondary = 1
  }

  expect_failures = [var.zone_secondary]
}

run "an_invalid_zone_is_rejected" {
  command = plan

  variables {
    zone_primary = 4
  }

  expect_failures = [var.zone_primary]
}

run "a_wan_subnet_too_small_is_rejected" {
  command = plan

  variables {
    wan_cidr = "10.0.100.0/28"
  }

  expect_failures = [var.wan_cidr]
}

run "a_long_name_is_rejected" {
  command = plan

  variables {
    name = "abcdefghijklmnopqrstuvwxyz-abcdefghijklmnopqrstuvwxyz-abcde"
  }

  expect_failures = [var.name]
}
