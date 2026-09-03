output "id" {
  description = <<-EOT
    Fully qualified instance identifier,
    `projects/<project>/zones/<zone>/instances/<name>`.
  EOT
  value       = google_compute_instance.engine.id
}

output "instance_id" {
  description = <<-EOT
    Numeric server-assigned instance ID, stable for the life of the instance.
  EOT
  value       = google_compute_instance.engine.instance_id
}

output "name" {
  description = "Name of the engine instance."
  value       = google_compute_instance.engine.name
}

output "self_link" {
  description = "Self-link of the engine instance."
  value       = google_compute_instance.engine.self_link
}

output "zone" {
  description = "Zone the instance runs in."
  value       = google_compute_instance.engine.zone
}

output "instance" {
  description = <<-EOT
    The full `google_compute_instance` object, for attributes this module does
    not surface.
  EOT
  value       = google_compute_instance.engine
  sensitive   = true
}

output "internal_ips" {
  description = <<-EOT
    Internal IPv4 address per interface, keyed `nic0`, `nic1`, and so on.
  EOT
  value = {
    for index, nic in google_compute_instance.engine.network_interface :
    format("nic%d", index) => nic.network_ip
  }
}

output "external_ips" {
  description = <<-EOT
    External IPv4 address per interface that has one, keyed by NIC name.
    Interfaces without one are absent.
  EOT
  value = {
    for index, nic in google_compute_instance.engine.network_interface :
    format("nic%d", index) => nic.access_config[0].nat_ip
    if length(nic.access_config) > 0
  }
}

output "external_ipv6s" {
  description = <<-EOT
    External IPv6 address per dual-stack interface that has one, keyed by NIC
    name.
  EOT
  value = {
    for index, nic in google_compute_instance.engine.network_interface :
    format("nic%d", index) => nic.ipv6_access_config[0].external_ipv6
    if length(nic.ipv6_access_config) > 0
  }
}

output "management_internal_ip" {
  description = "Internal IPv4 address of `nic0`, the SMC management address."
  value       = google_compute_instance.engine.network_interface[0].network_ip
}

output "management_external_ip" {
  description = <<-EOT
    External IPv4 address of `nic0`, or `null` when the management interface has
    none.
  EOT
  value       = try(google_compute_instance.engine.network_interface[0].access_config[0].nat_ip, null)
}

output "network_interfaces" {
  description = <<-EOT
    Per-interface `index`, `subnetwork`, `network`, `internal_ip` and
    `external_ip`, keyed by NIC name.
  EOT
  value = {
    for index, nic in google_compute_instance.engine.network_interface :
    format("nic%d", index) => {
      index       = index
      subnetwork  = nic.subnetwork
      network     = nic.network
      internal_ip = nic.network_ip
      external_ip = try(nic.access_config[0].nat_ip, null)
    }
  }
}

output "instance_group_self_link" {
  description = <<-EOT
    Self-link of the unmanaged instance group, or `null` when
    `create_instance_group` is `false`.
  EOT
  value       = try(google_compute_instance_group.engine[0].self_link, null)
}

output "instance_group_id" {
  description = <<-EOT
    ID of the unmanaged instance group, or `null` when `create_instance_group`
    is `false`.
  EOT
  value       = try(google_compute_instance_group.engine[0].id, null)
}

output "service_account_email" {
  description = <<-EOT
    Service account attached to the instance, or `null` when none is.
  EOT
  value       = try(google_compute_instance.engine.service_account[0].email, null)
}
