# The provider is mocked, so every assertion must hold at plan time.
#
# Computed self-links and external addresses are unknown at plan; compare
# names and configured values instead.

mock_provider "google" {}

variables {
  project_id      = "example-project"
  image           = "projects/example/global/images/engine-7-6-0"
  name            = "example"
  allowed_cidrs   = ["198.51.100.10/32", "203.0.113.0/24"]
  ssh_public_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHH6MBe8CCHwOgcBIIy6rE6F8A5SpJvYyOtwhEXWNOLH me@example"]
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
    condition     = module.primary.zone == "europe-north1-a"
    error_message = "The primary engine must sit in zone_primary."
  }

  assert {
    condition     = module.secondary.zone == "europe-north1-b"
    error_message = "The secondary engine must sit in zone_secondary."
  }
}

run "the_engines_addresses_are_pinned" {
  command = plan

  # The failover script's settings and the servers' route name these
  # addresses, so they must not move on a replacement.
  assert {
    condition     = module.primary.internal_ips == { nic0 = cidrhost(var.management_cidr, 10), nic1 = cidrhost(var.lan_cidr, 10), nic2 = cidrhost(var.wan_cidr, 10) }
    error_message = "The primary takes host 10 of each subnetwork, in management, LAN, WAN order."
  }

  assert {
    condition     = module.secondary.internal_ips == { nic0 = cidrhost(var.management_cidr, 11), nic1 = cidrhost(var.lan_cidr, 11), nic2 = cidrhost(var.wan_cidr, 11) }
    error_message = "The secondary takes host 11 of each subnetwork, in management, LAN, WAN order."
  }

  assert {
    condition     = length(google_compute_network.this) == 3
    error_message = "GCP forbids two interfaces of one instance in the same network."
  }
}

run "management_is_the_only_external_address_at_creation" {
  command = plan

  assert {
    condition     = keys(module.primary.external_ips) == ["nic0"]
    error_message = "Only the management interface gets an external address; the WAN address is reserved and attached by the failover script."
  }

  assert {
    condition     = keys(module.secondary.external_ips) == ["nic0"]
    error_message = "Only the management interface gets an external address; the WAN address is reserved and attached by the failover script."
  }
}

run "the_reserved_public_ip_is_created" {
  command = plan

  assert {
    condition     = keys(google_compute_address.ha) == ["vpn"]
    error_message = "The pair needs the vpn reserved public IP, and only it: a GCP interface holds one external address."
  }

  assert {
    condition     = google_compute_address.ha["vpn"].address_type == "EXTERNAL"
    error_message = "The reserved public IP must be external."
  }

  assert {
    condition     = google_compute_address.ha["vpn"].name == "example-ha-vpn"
    error_message = "The reserved public IP must be named after the pair."
  }
}

run "each_engine_has_its_own_wan_public_ip" {
  command = plan

  variables {
    wan_floating_ip = false
  }

  assert {
    condition     = length(google_compute_address.ha) == 0
    error_message = "With a public IP per engine, no address floats."
  }

  assert {
    condition = alltrue([
      for engine in ["primary", "secondary"] : (
        google_compute_address.wan[engine].name == "example-${engine}-wan-external" &&
        google_compute_address.wan[engine].address_type == "EXTERNAL"
      )
    ])
    error_message = "Each engine must have an external address of its own, named after it."
  }

  assert {
    condition     = keys(module.primary.external_ips) == ["nic0", "nic2"] && keys(module.secondary.external_ips) == ["nic0", "nic2"]
    error_message = "The WAN interface must carry the engine's own public IP."
  }

  assert {
    condition     = !contains(keys(local.ha_metadata), "FP_HA_reserved_public_ip_vpn") && length(local.ha_metadata) == 5
    error_message = "With nothing to move but the route, the script must get no reserved public IP."
  }
}

run "the_servers_egress_through_the_primary_engine" {
  command = plan

  assert {
    condition     = google_compute_route.protected_default.dest_range == "0.0.0.0/0"
    error_message = "The default route must hand the servers' traffic to the engine."
  }

  assert {
    condition     = google_compute_route.protected_default.next_hop_ip == cidrhost(var.lan_cidr, 10)
    error_message = "The default route must point at the primary engine's LAN address."
  }

  # The network's own default route has priority 1000; a tie would spread
  # the egress across the engine and the internet gateway.
  assert {
    condition     = google_compute_route.protected_default.priority == 100
    error_message = "The route must be more preferred than the network's own default route."
  }

  assert {
    condition     = google_compute_route.protected_default.tags == toset([var.protected_network_tag])
    error_message = "The route must be scoped to the protected tag; an untagged route captures the engines too."
  }

  assert {
    condition     = !contains(module.primary.instance.tags, var.protected_network_tag) && !contains(module.secondary.instance.tags, var.protected_network_tag)
    error_message = "The engines must not carry the protected tag, or they route their own traffic through themselves."
  }
}

run "the_wan_is_open_and_the_management_is_not" {
  command = plan

  assert {
    condition     = google_compute_firewall.wan.source_ranges == toset(["0.0.0.0/0"])
    error_message = "The WAN interface is the external network's entry; the engine's policy is the filter."
  }

  assert {
    condition     = !contains(google_compute_firewall.management.source_ranges, "0.0.0.0/0")
    error_message = "The management interface must never be open to the internet."
  }

  assert {
    condition     = google_compute_firewall.iap.source_ranges == toset(["35.235.240.0/20"])
    error_message = "SSH to the servers must come through IAP only."
  }

  assert {
    condition     = google_compute_firewall.iap.target_tags == toset([var.protected_network_tag])
    error_message = "The IAP rule must target the servers."
  }

  assert {
    condition     = google_compute_firewall.server_engines.source_ranges == toset([var.lan_cidr])
    error_message = "The servers accept traffic from the engines' LAN subnetwork only, not from each other."
  }

  assert {
    condition     = google_compute_firewall.server_admins_and_peers.source_ranges == toset(var.allowed_cidrs)
    error_message = "The servers accept the allowed CIDRs, so VPN peer sites reach them."
  }

  assert {
    condition     = one(google_compute_firewall.server_admins_and_peers.allow).protocol == "all"
    error_message = "The servers accept any protocol from the allowed CIDRs."
  }
}

run "the_servers_have_no_public_address" {
  command = plan

  assert {
    condition     = alltrue([for server in google_compute_instance.server : length(server.network_interface[0].access_config) == 0])
    error_message = "The servers are reached over IAP; they must have no external address."
  }
}

run "the_failover_metadata_reaches_the_engines" {
  command = plan

  # The reserved IP triplet carries an address the mock provider cannot
  # know at plan, so the handover is asserted on its keys and its known
  # values. The script's probe settings beyond the address take its
  # defaults and are not part of the handover.
  assert {
    condition     = length(local.ha_metadata) == 6
    error_message = "The handover carries the failover script's settings: the route, the internal NIC index, both instances, the probe address and the reserved public IP."
  }

  assert {
    condition     = local.ha_metadata.FP_HA_route_name == google_compute_route.protected_default.name
    error_message = "The script must find the servers' route by name."
  }

  assert {
    condition     = local.ha_metadata.FP_HA_primary_instance_id == "projects/example-project/zones/europe-north1-a/instances/example-primary"
    error_message = "The primary instance reference must be its self link."
  }

  assert {
    condition     = local.ha_metadata.FP_HA_secondary_instance_id == "projects/example-project/zones/europe-north1-b/instances/example-secondary"
    error_message = "The secondary instance reference must be its self link."
  }

  assert {
    condition     = local.ha_metadata.FP_HA_probe_ip == cidrhost(var.lan_cidr, 10)
    error_message = "The secondary must probe the primary's LAN address."
  }

  assert {
    condition     = alltrue([for key in keys(local.ha_metadata) : contains(keys(module.primary.instance.metadata), key)])
    error_message = "The primary engine must carry the failover script's metadata."
  }

  assert {
    condition     = alltrue([for key in keys(local.ha_metadata) : contains(keys(module.secondary.instance.metadata), key)])
    error_message = "The secondary engine must carry the failover script's metadata."
  }
}

run "the_failover_identity_is_scoped_to_the_project" {
  command = plan

  assert {
    condition     = google_service_account.ha[0].account_id == "example-ha-sa"
    error_message = "The service account must be named after the pair."
  }

  assert {
    condition     = google_project_iam_custom_role.ha[0].role_id == "example_ha"
    error_message = "The role must be named after the pair."
  }

  assert {
    condition     = length(google_project_iam_custom_role.ha[0].permissions) == 14
    error_message = "The role must grant the failover script's permissions and nothing more."
  }

  assert {
    condition     = contains(google_project_iam_custom_role.ha[0].permissions, "compute.instances.addAccessConfig")
    error_message = "The script moves the reserved public IP between the engines."
  }

  assert {
    condition     = contains(google_project_iam_custom_role.ha[0].permissions, "compute.routes.create")
    error_message = "The script creates the failover route."
  }
}

run "the_failover_identity_is_optional" {
  command = plan

  variables {
    enable_ha_identity = false
  }

  assert {
    condition     = length(google_service_account.ha) == 0
    error_message = "Without the flag no service account may be created."
  }

  assert {
    condition     = length(google_project_iam_custom_role.ha) == 0
    error_message = "Without the flag no role may be created."
  }

  assert {
    condition     = module.primary.service_account_email == null
    error_message = "Without the flag the engines carry no service account."
  }
}

run "the_servers_sit_in_their_own_subnetworks" {
  command = plan

  # The servers live in the LAN network: a tag-scoped route does not cross
  # a peering.
  assert {
    condition     = length(google_compute_subnetwork.server) == 2
    error_message = "Each server needs its own subnetwork."
  }

  assert {
    condition     = google_compute_instance.server["a"].network_interface[0].network_ip == cidrhost(var.server_a_cidr, 120)
    error_message = "Server a must be pinned in its subnetwork."
  }

  assert {
    condition     = google_compute_instance.server["b"].network_interface[0].network_ip == cidrhost(var.server_b_cidr, 120)
    error_message = "Server b must be pinned in its subnetwork."
  }

  assert {
    condition     = alltrue([for server in google_compute_instance.server : contains(server.tags, var.protected_network_tag)])
    error_message = "The servers must carry the protected tag, or the route does not apply to them."
  }
}

run "the_zones_must_differ" {
  command = plan

  variables {
    zone_secondary = "europe-north1-a"
  }

  expect_failures = [var.zone_secondary]
}

run "the_zones_must_share_a_region" {
  command = plan

  variables {
    zone_secondary = "europe-west1-b"
  }

  expect_failures = [var.zone_secondary]
}

run "an_invalid_zone_is_rejected" {
  command = plan

  variables {
    zone_primary = "europe-north1"
  }

  expect_failures = [var.zone_primary]
}

run "a_wan_subnetwork_too_small_is_rejected" {
  command = plan

  variables {
    wan_cidr = "10.20.100.0/29"
  }

  expect_failures = [var.wan_cidr]
}

run "a_long_name_is_rejected" {
  command = plan

  variables {
    name = "abcdefghijklmnopqrstuvwxy"
  }

  expect_failures = [var.name]
}
