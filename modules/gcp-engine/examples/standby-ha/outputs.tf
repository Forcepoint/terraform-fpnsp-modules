output "project_id" {
  description = "Project the example is deployed into."
  value       = var.project_id
}

output "networks" {
  description = "Self-link of each VPC network, keyed `management`, `lan` and `wan`."
  value = {
    for key, network in google_compute_network.this : key => network.self_link
  }
}

output "subnetworks" {
  description = <<-EOT
    Self-link of each subnetwork, keyed `management`, `lan`, `wan`,
    `server-a` and `server-b`.
  EOT
  value = merge(
    { for key, subnetwork in google_compute_subnetwork.this : key => subnetwork.self_link },
    { for key, subnetwork in google_compute_subnetwork.server : "server-${key}" => subnetwork.self_link },
  )
}

output "route" {
  description = "Name and self-link of the servers' default route."
  value = {
    name      = google_compute_route.protected_default.name
    self_link = google_compute_route.protected_default.self_link
  }
}

output "engine_ids" {
  description = "Self-link of each engine instance."
  value = {
    primary   = module.primary.self_link
    secondary = module.secondary.self_link
  }
}

output "management_public_ips" {
  description = "Public IPv4 address of each engine's management interface."
  value = {
    primary   = module.primary.management_external_ip
    secondary = module.secondary.management_external_ip
  }
}

output "reserved_public_ips" {
  description = "Public IPv4 address of each reserved public IP, keyed `vpn` when `wan_floating_ip` is set."
  value = {
    for key, address in google_compute_address.ha : key => address.address
  }
}

output "reserved_public_ip_ids" {
  description = "Self-link of each reserved public IP, keyed `vpn` when `wan_floating_ip` is set."
  value = {
    for key, address in google_compute_address.ha : key => address.self_link
  }
}

output "wan_public_ips" {
  description = <<-EOT
    Public IPv4 address of each engine's WAN interface, keyed `primary` and
    `secondary`, when `wan_floating_ip` is off.
  EOT
  value = var.wan_floating_ip ? null : {
    for key, address in google_compute_address.wan : key => address.address
  }
}

output "ha_metadata" {
  description = <<-EOT
    The `FP_HA_` metadata the cloud HA failover script reads from the
    engines.
  EOT
  value       = local.ha_metadata
}

output "identity" {
  description = <<-EOT
    The failover service account's email and its custom role's ID, when
    `enable_ha_identity` is set.
  EOT
  value = var.enable_ha_identity ? {
    email   = google_service_account.ha[0].email
    role_id = google_project_iam_custom_role.ha[0].id
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
    primary   = "ssh gencloud@${module.primary.management_external_ip}"
    secondary = "ssh gencloud@${module.secondary.management_external_ip}"
  }
}

output "server_ssh_commands" {
  description = "SSH to the servers through IAP. They have no public address."
  value = {
    for key, server in google_compute_instance.server : key => join(" ", [
      "gcloud compute ssh",
      server.name,
      "--zone", var.zone_primary,
      "--tunnel-through-iap",
    ])
  }
}
