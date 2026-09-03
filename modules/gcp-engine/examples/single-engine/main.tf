# One VPC network per interface: GCP forbids two interfaces of one instance in
# the same network.

locals {
  region = join("-", slice(split("-", var.zone), 0, 2))

  # The engine's addresses are pinned at host 10 of each CIDR, so a static
  # SMC interface configuration keeps working. cidrhost() needs a prefix of
  # at most /28 for host 10, so the CIDRs must be /28 or larger. GCP would
  # otherwise give a reservation the lowest free IP at creation time, and
  # re-pick one on recreation.
  networks = {
    management = { cidr = var.management_cidr, engine_ip = cidrhost(var.management_cidr, 10) }
    wan        = { cidr = var.wan_cidr, engine_ip = cidrhost(var.wan_cidr, 10) }
    lan        = { cidr = var.lan_cidr, engine_ip = cidrhost(var.lan_cidr, 10) }
  }

  server_ssh_keys = join("\n", [
    for key in var.ssh_public_keys :
    format("%s:%s", var.server_user, trimspace(key))
  ])
}

resource "google_compute_network" "this" {
  for_each = local.networks

  project                 = var.project_id
  name                    = "${var.name}-${each.key}"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "this" {
  for_each = local.networks

  project       = var.project_id
  name          = "${var.name}-${each.key}"
  region        = local.region
  network       = google_compute_network.this[each.key].id
  ip_cidr_range = each.value.cidr
}

# Reserved and pinned, so the addresses survive an engine replacement and
# the SMC interface definitions and the protected route keep pointing at
# the same values.
resource "google_compute_address" "internal" {
  for_each = local.networks

  project      = var.project_id
  name         = "${var.name}-${each.key}-internal"
  region       = local.region
  subnetwork   = google_compute_subnetwork.this[each.key].id
  address      = each.value.engine_ip
  address_type = "INTERNAL"
  labels       = { role = "engine" }
}

resource "google_compute_address" "external" {
  for_each = { management = true, wan = true }

  project = var.project_id
  name    = "${var.name}-${each.key}-external"
  region  = local.region
  labels  = { role = "engine" }
}

# Policy lives in the SMC, so these rules scope by source range only, not by
# port. GCP ingress is default-deny.

resource "google_compute_firewall" "management" {
  project   = var.project_id
  name      = "${var.name}-allow-management"
  network   = google_compute_network.this["management"].id
  direction = "INGRESS"

  allow {
    protocol = "all"
  }

  # Own subnetwork included, so engines in it reach each other.
  source_ranges = concat(var.allowed_cidrs, [var.management_cidr])
  target_tags   = [var.network_tag]
}

resource "google_compute_firewall" "wan" {
  project   = var.project_id
  name      = "${var.name}-allow-wan"
  network   = google_compute_network.this["wan"].id
  direction = "INGRESS"

  allow {
    protocol = "all"
  }

  source_ranges = concat(var.allowed_cidrs, [var.wan_cidr])
  target_tags   = [var.network_tag]
}

resource "google_compute_firewall" "lan" {
  project   = var.project_id
  name      = "${var.name}-allow-lan"
  network   = google_compute_network.this["lan"].id
  direction = "INGRESS"

  allow {
    protocol = "all"
  }

  source_ranges = [var.lan_cidr]
}

# Tag-scoped: an untagged route would capture the engine too.
resource "google_compute_route" "protected_default" {
  project     = var.project_id
  name        = "${var.name}-protected-default"
  network     = google_compute_network.this["lan"].id
  dest_range  = "0.0.0.0/0"
  next_hop_ip = module.engine.internal_ips["nic1"]
  priority    = 100
  tags        = [var.protected_network_tag]

  depends_on = [google_compute_subnetwork.this]
}

module "engine" {
  source = "github.com/Forcepoint/terraform-fpnsp-modules//modules/gcp-engine"

  name         = var.name
  project_id   = var.project_id
  zone         = var.zone
  machine_type = var.machine_type

  boot_disk = {
    initialize_params = { image = var.image }
  }

  network_interfaces = [
    {
      subnetwork = google_compute_subnetwork.this["management"].id
      network_ip = google_compute_address.internal["management"].address

      access_config = [
        {
          nat_ip = google_compute_address.external["management"].address
        },
      ]
    },
    {
      subnetwork = google_compute_subnetwork.this["lan"].id
      network_ip = google_compute_address.internal["lan"].address
    },
    {
      subnetwork = google_compute_subnetwork.this["wan"].id
      network_ip = google_compute_address.internal["wan"].address

      access_config = [
        {
          nat_ip = google_compute_address.external["wan"].address
        },
      ]
    },
  ]

  initial_contact = var.initial_contact
  ssh_public_keys = var.ssh_public_keys

  network_tags = [var.network_tag]

  labels = {
    role = "engine"
  }
}

# A workload with no public address, to verify the route end to end.
resource "google_compute_instance" "server" {
  project      = var.project_id
  name         = "${var.name}-server"
  zone         = var.zone
  machine_type = var.server_machine_type

  # The route selects this tag. The engine must not carry it.
  tags = [var.protected_network_tag]

  boot_disk {
    initialize_params {
      image = var.server_image
    }
  }

  # No access_config: no public address. The address stays ephemeral; only
  # the engine's addresses need to be stable for the SMC configuration.
  network_interface {
    subnetwork = google_compute_subnetwork.this["lan"].id
  }

  metadata = {
    ssh-keys               = local.server_ssh_keys
    block-project-ssh-keys = "TRUE"
    enable-oslogin         = "FALSE"
  }

  labels = {
    role = "protected-workload"
  }
}

# IAP brokers SSH from a fixed Google-owned range to instances without a public
# address.
resource "google_compute_firewall" "iap" {
  project   = var.project_id
  name      = "${var.name}-allow-iap"
  network   = google_compute_network.this["lan"].id
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = [var.protected_network_tag]
}
