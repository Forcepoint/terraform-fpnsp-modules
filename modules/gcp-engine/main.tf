# The engine reads initial contact data on first boot only, so a change must
# replace the instance. Always created: replace_triggered_by cannot reference a
# zero-instance resource. A null trigger never replaces.
resource "terraform_data" "initial_contact" {
  triggers_replace = (
    var.initial_contact != null && var.initial_contact_replace_on_change
    ? sha256(var.initial_contact)
    : null
  )
}

resource "google_compute_instance" "engine" {
  project      = var.project_id
  name         = var.name
  zone         = var.zone
  machine_type = var.machine_type

  min_cpu_platform          = var.min_cpu_platform
  can_ip_forward            = var.can_ip_forward
  tags                      = var.network_tags
  labels                    = var.labels
  resource_policies         = var.resource_policies
  deletion_protection       = var.deletion_protection
  allow_stopping_for_update = var.allow_stopping_for_update

  # var.metadata merges last: callers can override any computed key.
  # The engine's sshd installs only the gencloud: line of the ssh-keys
  # metadata, so the login is fixed, not a variable.
  metadata = merge(
    var.initial_contact == null ? {} : { startup-script = var.initial_contact },
    length(var.ssh_public_keys) == 0 ? {} : {
      ssh-keys = join("\n", [
        for key in var.ssh_public_keys : format("gencloud:%s", trimspace(key))
      ]),
    },
    var.block_project_ssh_keys ? { block-project-ssh-keys = "TRUE" } : {},
    var.enable_guest_attributes ? { enable-guest-attributes = "TRUE" } : {},
    var.enable_serial_console ? { serial-port-enable = "TRUE" } : {},
    var.metadata,
  )

  boot_disk {
    auto_delete       = var.boot_disk.auto_delete
    device_name       = var.boot_disk.device_name
    kms_key_self_link = var.boot_disk.kms_key_self_link

    initialize_params {
      image                  = var.boot_disk.initialize_params.image
      size                   = var.boot_disk.initialize_params.size
      type                   = var.boot_disk.initialize_params.type
      provisioned_iops       = var.boot_disk.initialize_params.provisioned_iops
      provisioned_throughput = var.boot_disk.initialize_params.provisioned_throughput
      labels                 = var.labels
    }
  }

  # Block order is guest interface order: the first block is nic0.
  dynamic "network_interface" {
    for_each = var.network_interfaces

    content {
      subnetwork = network_interface.value.subnetwork
      # project_id may be null (the provider's project), and coalesce() errors
      # when every argument is null, hence the try(): then this stays null.
      subnetwork_project = try(coalesce(network_interface.value.subnetwork_project, var.project_id), null)
      network_ip         = network_interface.value.network_ip
      ipv6_address       = network_interface.value.ipv6_address
      nic_type           = network_interface.value.nic_type
      queue_count        = network_interface.value.queue_count
      stack_type         = network_interface.value.stack_type

      dynamic "access_config" {
        for_each = network_interface.value.access_config

        content {
          nat_ip                 = access_config.value.nat_ip
          network_tier           = access_config.value.network_tier
          public_ptr_domain_name = access_config.value.public_ptr_domain_name
        }
      }

      dynamic "ipv6_access_config" {
        for_each = network_interface.value.ipv6_access_config

        content {
          network_tier  = ipv6_access_config.value.network_tier
          external_ipv6 = ipv6_access_config.value.external_ipv6
          name          = ipv6_access_config.value.name
        }
      }

      dynamic "alias_ip_range" {
        for_each = network_interface.value.alias_ip_range

        content {
          ip_cidr_range         = alias_ip_range.value.ip_cidr_range
          subnetwork_range_name = alias_ip_range.value.subnetwork_range_name
        }
      }
    }
  }

  scheduling {
    automatic_restart   = var.scheduling.automatic_restart
    on_host_maintenance = var.scheduling.on_host_maintenance
    preemptible         = var.scheduling.preemptible
    provisioning_model  = var.scheduling.provisioning_model
  }

  # An empty block would attach the project default account. Omit it instead.
  dynamic "service_account" {
    for_each = var.service_account == null ? [] : [var.service_account]

    content {
      email  = service_account.value.email
      scopes = service_account.value.scopes
    }
  }

  lifecycle {
    replace_triggered_by = [terraform_data.initial_contact]
  }
}

# Zonal and unmanaged: the backend shape an internal load balancer expects.
resource "google_compute_instance_group" "engine" {
  count = var.create_instance_group ? 1 : 0

  project   = var.project_id
  name      = coalesce(var.instance_group_name, format("%s-ig", var.name))
  zone      = var.zone
  instances = [google_compute_instance.engine.self_link]

  dynamic "named_port" {
    for_each = var.instance_group_named_ports

    content {
      name = named_port.value.name
      port = named_port.value.port
    }
  }
}
