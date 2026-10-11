locals {
  region = join("-", slice(split("-", var.zone_primary), 0, 2))

  # The engines' addresses are pinned inside each subnetwork, so a static
  # SMC interface configuration keeps working. The primary takes host 10,
  # the secondary host 11.
  addresses = {
    primary = {
      management = cidrhost(var.management_cidr, 10)
      lan        = cidrhost(var.lan_cidr, 10)
      wan        = cidrhost(var.wan_cidr, 10)
    }
    secondary = {
      management = cidrhost(var.management_cidr, 11)
      lan        = cidrhost(var.lan_cidr, 11)
      wan        = cidrhost(var.wan_cidr, 11)
    }
  }

  # One reserved internal address per engine interface, keyed
  # `<engine>-<network>`.
  internal_addresses = merge([
    for engine, networks in local.addresses : {
      for network, address in networks : "${engine}-${network}" => {
        network = network
        address = address
      }
    }
  ]...)

  # The protected servers, one per subnetwork of the LAN network, pinned at
  # host 120.
  servers = {
    a = { cidr = var.server_a_cidr, ip = cidrhost(var.server_a_cidr, 120) }
    b = { cidr = var.server_b_cidr, ip = cidrhost(var.server_b_cidr, 120) }
  }

  # Read by the failover script from the engines' metadata. The instance
  # references are built from the inputs, so the two engines need not know
  # each other. A reserved public IP is
  # `public address,primary private address,secondary private address`.
  # Without a floating IP, the script moves the route only.
  ha_metadata = merge(
    {
      FP_HA_route_name            = "${var.name}-protected-default"
      FP_HA_internal_nic_idx      = "1"
      FP_HA_primary_instance_id   = "projects/${var.project_id}/zones/${var.zone_primary}/instances/${var.name}-primary"
      FP_HA_secondary_instance_id = "projects/${var.project_id}/zones/${var.zone_secondary}/instances/${var.name}-secondary"
      FP_HA_probe_ip              = local.addresses.primary.lan
    },
    var.wan_floating_ip ? {
      FP_HA_reserved_public_ip_vpn = "${google_compute_address.ha["vpn"].address},${local.addresses.primary.wan},${local.addresses.secondary.wan}"
    } : {},
  )

  # The WAN interface's external address, when each engine has its own.
  wan_access_config = {
    for engine in ["primary", "secondary"] : engine => var.wan_floating_ip ? [] : [
      { nat_ip = google_compute_address.wan[engine].address },
    ]
  }

  server_ssh_keys = join("\n", [
    for key in var.ssh_public_keys :
    format("%s:%s", var.server_user, trimspace(key))
  ])
}

# --- Networks: one per engine interface ---

# GCP forbids two interfaces of one instance in the same network.

resource "google_compute_network" "this" {
  for_each = toset(["management", "lan", "wan"])

  project                 = var.project_id
  name                    = "${var.name}-${each.key}"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "this" {
  for_each = {
    management = var.management_cidr
    lan        = var.lan_cidr
    wan        = var.wan_cidr
  }

  project       = var.project_id
  name          = "${var.name}-${each.key}"
  region        = local.region
  network       = google_compute_network.this[each.key].id
  ip_cidr_range = each.value
}

# --- The servers' subnetworks, in the LAN network ---

# Not a peered network: peering does not export tag-scoped routes, so the
# servers' route through the engines would not reach it.

resource "google_compute_subnetwork" "server" {
  for_each = local.servers

  project       = var.project_id
  name          = "${var.name}-server-${each.key}"
  region        = local.region
  network       = google_compute_network.this["lan"].id
  ip_cidr_range = each.value.cidr
}

# --- The engines' addresses ---

# Reserved and pinned, so the addresses survive an engine replacement and
# the SMC interface definitions, the servers' route and the failover
# script's settings keep pointing at the same values.

resource "google_compute_address" "internal" {
  for_each = local.internal_addresses

  project      = var.project_id
  name         = "${var.name}-${each.key}-internal"
  region       = local.region
  subnetwork   = google_compute_subnetwork.this[each.value.network].id
  address      = each.value.address
  address_type = "INTERNAL"
  labels       = { role = "engine" }
}

# Reserved, as an ephemeral external address is released when the engine
# stops.
resource "google_compute_address" "management" {
  for_each = toset(["primary", "secondary"])

  project = var.project_id
  name    = "${var.name}-${each.key}-management-external"
  region  = local.region
  labels  = { role = "engine" }
}

# --- Firewall rules ---

# Policy lives in the SMC, so these rules scope by source range only, not by
# port. GCP ingress is default-deny, and egress is open.

resource "google_compute_firewall" "management" {
  project   = var.project_id
  name      = "${var.name}-allow-management"
  network   = google_compute_network.this["management"].id
  direction = "INGRESS"

  allow {
    protocol = "all"
  }

  # Own subnetwork included, so the engines reach each other.
  source_ranges = concat(var.allowed_cidrs, [var.management_cidr])
  target_tags   = [var.network_tag]
}

# The LAN interface is the servers' next hop, and the failover script probes
# the primary over it.
resource "google_compute_firewall" "lan" {
  project   = var.project_id
  name      = "${var.name}-allow-lan"
  network   = google_compute_network.this["lan"].id
  direction = "INGRESS"

  allow {
    protocol = "all"
  }

  source_ranges = [var.lan_cidr, var.server_a_cidr, var.server_b_cidr]
  target_tags   = [var.network_tag]
}

# Open by design: the engine's policy decides what reaches the servers.
resource "google_compute_firewall" "wan" {
  project   = var.project_id
  name      = "${var.name}-allow-wan"
  network   = google_compute_network.this["wan"].id
  direction = "INGRESS"

  allow {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = [var.network_tag]
}

# IAP brokers SSH from a fixed Google-owned range to instances without a
# public address.
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

# Traffic sourced from the engines' LAN subnetwork. The server subnetworks
# are not sources, so server-to-server traffic is denied.
resource "google_compute_firewall" "server_engines" {
  project   = var.project_id
  name      = "${var.name}-allow-server-engines"
  network   = google_compute_network.this["lan"].id
  direction = "INGRESS"

  allow {
    protocol = "all"
  }

  source_ranges = [var.lan_cidr]
  target_tags   = [var.protected_network_tag]
}

resource "google_compute_firewall" "server_admins_and_peers" {
  project   = var.project_id
  name      = "${var.name}-allow-server-admins-and-peers"
  network   = google_compute_network.this["lan"].id
  direction = "INGRESS"

  allow {
    protocol = "all"
  }

  source_ranges = var.allowed_cidrs
  target_tags   = [var.protected_network_tag]
}

# --- Routing: the servers' egress goes through the engines ---

# Tag-scoped: an untagged route would capture the engines too. The next hop
# is the primary's pinned LAN address. On failover the failover script
# leaves this route alone and creates a `-failover` copy, pointing at the
# secondary, one offset (100 by default) more preferred; failback deletes
# it. Priority 100 beats the network's own default route (1000), and the
# copy takes priority 0.
resource "google_compute_route" "protected_default" {
  project     = var.project_id
  name        = "${var.name}-protected-default"
  network     = google_compute_network.this["lan"].id
  dest_range  = "0.0.0.0/0"
  next_hop_ip = local.addresses.primary.lan
  priority    = 100
  tags        = [var.protected_network_tag]

  depends_on = [google_compute_subnetwork.this]
}

# --- The WAN public IPs ---

# Floating: left unattached, the failover script attaches it to the active
# engine's WAN interface. One address only: a GCP interface holds one
# external address, and it must map to the interface's primary internal
# address.

resource "google_compute_address" "ha" {
  for_each = var.wan_floating_ip ? toset(["vpn"]) : toset([])

  project      = var.project_id
  name         = "${var.name}-ha-${each.value}"
  region       = local.region
  address_type = "EXTERNAL"
  labels       = { role = "ha" }
}

# Per engine: attached to the engine's WAN interface by Terraform, as it
# does not move.
resource "google_compute_address" "wan" {
  for_each = var.wan_floating_ip ? toset([]) : toset(["primary", "secondary"])

  project      = var.project_id
  name         = "${var.name}-${each.key}-wan-external"
  region       = local.region
  address_type = "EXTERNAL"
  labels       = { role = "engine" }
}

# --- The failover identity ---

resource "google_service_account" "ha" {
  count = var.enable_ha_identity ? 1 : 0

  project      = var.project_id
  account_id   = "${var.name}-ha-sa"
  display_name = "${var.name} NGFW HA failover"
}

# Project-scoped: GCP has no narrower scope for the routes and addresses
# the script manages.
resource "google_project_iam_custom_role" "ha" {
  count = var.enable_ha_identity ? 1 : 0

  project     = var.project_id
  role_id     = replace("${var.name}_ha", "-", "_")
  title       = "${var.name} NGFW HA failover"
  description = "Actions the Forcepoint NGFW cloud HA failover script needs in this project."

  permissions = [
    # Own settings, the peer's interfaces and the peer's status.
    "compute.instances.get",
    "compute.instances.getGuestAttributes",
    # The failover route.
    "compute.routes.get",
    "compute.routes.create",
    "compute.routes.delete",
    "compute.networks.updatePolicy",
    # Moving the reserved public IP between the WAN interfaces.
    "compute.instances.addAccessConfig",
    "compute.instances.deleteAccessConfig",
    "compute.addresses.get",
    "compute.addresses.list",
    "compute.addresses.use",
    "compute.subnetworks.useExternalIp",
    # Polling the operations the mutating calls return.
    "compute.zoneOperations.get",
    "compute.globalOperations.get",
  ]
}

resource "google_project_iam_member" "ha" {
  count = var.enable_ha_identity ? 1 : 0

  project = var.project_id
  role    = google_project_iam_custom_role.ha[0].id
  member  = "serviceAccount:${google_service_account.ha[0].email}"
}

# --- The engines ---

# The failover script attaches the floating IP outside of Terraform.
# The engines depend on it, so a destroy deletes the engines, and the
# attachment with them, before the address.

module "primary" {
  source = "github.com/Forcepoint/terraform-fpnsp-modules//modules/gcp-engine"

  name         = "${var.name}-primary"
  project_id   = var.project_id
  zone         = var.zone_primary
  machine_type = var.machine_type

  boot_disk = {
    initialize_params = { image = var.image }
  }

  network_interfaces = [
    {
      subnetwork = google_compute_subnetwork.this["management"].id
      network_ip = google_compute_address.internal["primary-management"].address

      access_config = [
        {
          nat_ip = google_compute_address.management["primary"].address
        },
      ]
    },
    {
      subnetwork = google_compute_subnetwork.this["lan"].id
      network_ip = google_compute_address.internal["primary-lan"].address
    },
    {
      subnetwork = google_compute_subnetwork.this["wan"].id
      network_ip = google_compute_address.internal["primary-wan"].address

      access_config = local.wan_access_config.primary
    },
  ]

  ssh_public_keys = var.ssh_public_keys

  initial_contact = var.initial_contact_primary

  service_account = var.enable_ha_identity ? {
    email = google_service_account.ha[0].email
  } : null

  metadata = local.ha_metadata

  network_tags = [var.network_tag]

  labels = {
    role = "engine"
  }

  depends_on = [google_compute_address.ha]
}

module "secondary" {
  source = "github.com/Forcepoint/terraform-fpnsp-modules//modules/gcp-engine"

  name         = "${var.name}-secondary"
  project_id   = var.project_id
  zone         = var.zone_secondary
  machine_type = var.machine_type

  boot_disk = {
    initialize_params = { image = var.image }
  }

  network_interfaces = [
    {
      subnetwork = google_compute_subnetwork.this["management"].id
      network_ip = google_compute_address.internal["secondary-management"].address

      access_config = [
        {
          nat_ip = google_compute_address.management["secondary"].address
        },
      ]
    },
    {
      subnetwork = google_compute_subnetwork.this["lan"].id
      network_ip = google_compute_address.internal["secondary-lan"].address
    },
    {
      subnetwork = google_compute_subnetwork.this["wan"].id
      network_ip = google_compute_address.internal["secondary-wan"].address

      access_config = local.wan_access_config.secondary
    },
  ]

  ssh_public_keys = var.ssh_public_keys

  initial_contact = var.initial_contact_secondary

  service_account = var.enable_ha_identity ? {
    email = google_service_account.ha[0].email
  } : null

  metadata = local.ha_metadata

  network_tags = [var.network_tag]

  labels = {
    role = "engine"
  }

  depends_on = [google_compute_address.ha]
}

# --- The protected servers ---

resource "google_compute_instance" "server" {
  for_each = local.servers

  project      = var.project_id
  name         = "${var.name}-server-${each.key}"
  zone         = var.zone_primary
  machine_type = var.server_machine_type

  # The route selects this tag. The engines must not carry it.
  tags = [var.protected_network_tag]

  boot_disk {
    initialize_params {
      image = var.server_image
    }
  }

  # No access_config: no public address, reached over IAP.
  network_interface {
    subnetwork = google_compute_subnetwork.server[each.key].id
    network_ip = each.value.ip
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
