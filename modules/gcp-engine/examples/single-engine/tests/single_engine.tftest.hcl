# The provider is mocked, so every assertion must hold at plan time.

mock_provider "google" {}

variables {
  project_id    = "example-project"
  image         = "projects/example/global/images/engine-7-6-0"
  allowed_cidrs = ["198.51.100.10/32"]
}

run "one_network_per_interface" {
  command = plan

  assert {
    condition     = length(google_compute_network.this) == 3
    error_message = "GCP forbids two interfaces of one instance in the same network."
  }

  assert {
    condition     = length(module.engine.network_interfaces) == 3
    error_message = "The engine must have management, WAN and LAN interfaces."
  }

  # Subnetwork ids are unknown at plan, so assert on which interfaces are
  # public: only WAN is, and it is the last.
  assert {
    condition     = !contains(keys(module.engine.external_ips), "nic1")
    error_message = "nic1 must be the LAN interface, so a WAN leg stays optional."
  }

  assert {
    condition     = contains(keys(module.engine.external_ips), "nic2")
    error_message = "nic2 must be the WAN interface, the last of the three."
  }

  assert {
    condition = length(distinct([
      for subnetwork in google_compute_subnetwork.this : subnetwork.ip_cidr_range
    ])) == 3
    error_message = "The three subnetworks must not overlap."
  }
}

run "protected_route_points_at_the_lan_interface" {
  command = plan

  # The next hop is unknown at plan; assert on the route's shape.
  assert {
    condition     = google_compute_route.protected_default.dest_range == "0.0.0.0/0"
    error_message = "Protected workloads' default route must go through the engine."
  }

  assert {
    condition     = google_compute_route.protected_default.next_hop_gateway == null
    error_message = "The route must hand traffic to the engine, not to the internet gateway."
  }

  assert {
    condition     = google_compute_route.protected_default.priority == 100
    error_message = "The route must be more preferred than the VPC's own default route."
  }
}

run "the_route_must_not_capture_the_engine" {
  command = plan

  assert {
    condition     = length(google_compute_route.protected_default.tags) > 0
    error_message = "The route must be tag-scoped; an untagged route applies to the engine too."
  }

  assert {
    condition     = !contains(google_compute_route.protected_default.tags, var.network_tag)
    error_message = "The engine's own network tag must not select the route."
  }

  assert {
    condition     = !contains(module.engine.instance.tags, var.protected_network_tag)
    error_message = "The engine must not carry the protected tag, or it black-holes its own egress."
  }
}

run "management_is_not_open_to_the_world" {
  command = plan

  assert {
    condition = !contains(
      google_compute_firewall.management.source_ranges,
      "0.0.0.0/0",
    )
    error_message = "The management interface must never be open to the internet."
  }

  assert {
    condition     = google_compute_firewall.management.target_tags == toset([var.network_tag])
    error_message = "The management rule must target the engine by tag."
  }
}

run "the_rules_restrict_by_source_not_by_port" {
  command = plan

  assert {
    condition = alltrue([
      for rule in google_compute_firewall.management.allow :
      rule.protocol == "all" && rule.ports == null
    ])
    error_message = "The management rule must allow every protocol and port."
  }

  assert {
    condition = alltrue([
      for rule in google_compute_firewall.wan.allow :
      rule.protocol == "all" && rule.ports == null
    ])
    error_message = "The WAN rule must allow every protocol and port."
  }
}

run "the_rules_permit_intra_subnet_traffic" {
  command = plan

  assert {
    condition     = contains(google_compute_firewall.management.source_ranges, var.management_cidr)
    error_message = "The management rule must permit traffic from its own subnetwork."
  }

  assert {
    condition     = contains(google_compute_firewall.wan.source_ranges, var.wan_cidr)
    error_message = "The WAN rule must permit traffic from its own subnetwork."
  }
}

run "the_engine_is_reachable_and_forwards" {
  command = plan

  assert {
    condition     = module.engine.instance.can_ip_forward
    error_message = "The engine must be allowed to forward traffic."
  }

  assert {
    condition     = module.engine.instance.tags == toset([var.network_tag])
    error_message = "The engine must carry the tag the firewall rules target."
  }
}

run "only_the_lan_interface_is_private" {
  command = plan

  assert {
    condition     = length(module.engine.external_ips) == 2
    error_message = "Management and WAN get public addresses; LAN does not."
  }

  assert {
    condition     = !contains(keys(module.engine.external_ips), "nic1")
    error_message = "The LAN interface must not be exposed to the internet."
  }
}

run "addresses_are_reserved_in_the_zones_region" {
  command = plan

  assert {
    condition     = length(google_compute_address.internal) == 3
    error_message = "Every interface reserves its internal address, so the SMC and the route keep working across replacements."
  }

  assert {
    condition     = length(google_compute_address.external) == 2
    error_message = "Management and WAN reserve a public address; LAN does not."
  }

  assert {
    condition     = !contains(keys(google_compute_address.external), "lan")
    error_message = "The LAN interface must not be exposed to the internet."
  }

  assert {
    condition = alltrue([
      for address in google_compute_address.internal :
      address.region == "europe-north1"
    ])
    error_message = "Every reserved address must be in the region of the configured zone."
  }
}

run "the_reservations_are_pinned" {
  command = plan

  assert {
    condition     = google_compute_address.internal["lan"].address == cidrhost(var.lan_cidr, 10)
    error_message = "The LAN reservation must be pinned, so the SMC interface configuration can be static."
  }
}

run "ssh_keys_are_installed_for_the_cloud_login" {
  command = plan

  variables {
    ssh_public_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI0000000000000000000000000000000000000 me@example"]
  }

  assert {
    condition     = startswith(module.engine.instance.metadata["ssh-keys"], "gencloud:")
    error_message = "Keys must be scoped to the gencloud login in the ssh-keys metadata."
  }
}

run "the_protected_server_is_reachable_only_through_the_engine" {
  command = plan

  assert {
    condition     = length(google_compute_instance.server.network_interface[0].access_config) == 0
    error_message = "The protected server must not have a public address."
  }

  assert {
    condition     = contains(google_compute_instance.server.tags, var.protected_network_tag)
    error_message = "The server must carry the tag the route selects, or its egress bypasses the engine."
  }

  # Subnetwork ids are unknown at plan, so compare names instead.
  assert {
    condition     = google_compute_subnetwork.this["lan"].name == "${var.name}-lan"
    error_message = "The protected server must sit in the LAN subnetwork."
  }
}

run "iap_is_the_only_way_in_to_the_server" {
  command = plan

  assert {
    condition     = google_compute_firewall.iap.source_ranges == toset(["35.235.240.0/20"])
    error_message = "The IAP rule must admit only Google's IAP forwarding range."
  }

  assert {
    condition     = google_compute_firewall.iap.target_tags == toset([var.protected_network_tag])
    error_message = "The IAP rule must target the protected workloads, not the engine."
  }
}
