variable "name" {
  description = <<-EOT
    Name of the Security Engine instance. Must be a valid GCE resource name.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.name))
    error_message = "The name must be 2-63 characters of lowercase letters, digits or hyphens, start with a letter and not end with a hyphen."
  }
}

variable "project_id" {
  description = "Project to deploy into. Defaults to the provider's project."
  type        = string
  default     = null
}

variable "zone" {
  description = <<-EOT
    Zone to deploy into, for example `europe-north1-a`. Every subnetwork in
    `network_interfaces` must be in this zone's region.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+-[a-z]$", var.zone))
    error_message = "The zone must be a GCE zone name such as europe-north1-a."
  }
}

variable "machine_type" {
  description = <<-EOT
    Machine type. Determines throughput (egress bandwidth per vCPU) and maximum
    NIC count (one vCPU per interface).
  EOT
  type        = string
  default     = "n2-standard-4"
}

variable "min_cpu_platform" {
  description = "Minimum CPU platform, for example `Intel Cascade Lake`."
  type        = string
  default     = null
}

variable "scheduling" {
  description = <<-EOT
    Instance scheduling.

    - `automatic_restart`   - restart after a GCP-initiated termination.
    - `on_host_maintenance` - `MIGRATE` or `TERMINATE`.
    - `preemptible`         - requires `provisioning_model = "SPOT"`,
      `automatic_restart = false` and
      `on_host_maintenance = "TERMINATE"`.
    - `provisioning_model`  - `STANDARD` or `SPOT`. `SPOT` requires
      `automatic_restart = false` and `on_host_maintenance = "TERMINATE"`.
  EOT
  type = object({
    automatic_restart   = optional(bool, true)
    on_host_maintenance = optional(string, "MIGRATE")
    preemptible         = optional(bool, false)
    provisioning_model  = optional(string, "STANDARD")
  })
  default = {}

  validation {
    condition     = contains(["MIGRATE", "TERMINATE"], var.scheduling.on_host_maintenance)
    error_message = "scheduling.on_host_maintenance must be MIGRATE or TERMINATE."
  }

  validation {
    condition     = contains(["STANDARD", "SPOT"], var.scheduling.provisioning_model)
    error_message = "scheduling.provisioning_model must be STANDARD or SPOT."
  }

  # The provider emits provisioning_model unconditionally, so a contradictory
  # plan would pass plan and be rejected by GCP at apply. Validate instead:
  # a spot VM (preemptible or SPOT) may not restart or migrate.
  validation {
    condition = !(var.scheduling.preemptible || var.scheduling.provisioning_model == "SPOT") || (
      var.scheduling.provisioning_model == "SPOT" &&
      !var.scheduling.automatic_restart &&
      var.scheduling.on_host_maintenance == "TERMINATE"
    )
    error_message = "A preemptible/SPOT instance requires provisioning_model = \"SPOT\", automatic_restart = false and on_host_maintenance = \"TERMINATE\"."
  }
}

variable "boot_disk" {
  description = <<-EOT
    Boot disk, mirroring the instance's `boot_disk` block.

    - `auto_delete`              - delete the disk with the instance.
    - `device_name`              - name exposed under
      `/dev/disk/by-id/google-*`.
    - `kms_key_self_link`        - customer-managed encryption key.
    - `initialize_params`        - create the disk from an image:
      - `image`                  - (Required) self-link, partial URL or
        name of the engine image, for example
        `projects/my-project/global/images/engine-7-6-0`. The image must carry
        the `MULTI_IP_SUBNET` guest OS feature.
      - `size`                   - size in GB. `null` uses the image's size.
      - `type`                   - `pd-balanced`, `pd-ssd`, `pd-standard`,
        `hyperdisk-*`.
      - `provisioned_iops`       - for disk types that support it.
      - `provisioned_throughput` - MB/s, for disk types that support it.
  EOT
  type = object({
    auto_delete       = optional(bool, true)
    device_name       = optional(string)
    kms_key_self_link = optional(string)
    initialize_params = object({
      image                  = string
      size                   = optional(number)
      type                   = optional(string, "pd-balanced")
      provisioned_iops       = optional(number)
      provisioned_throughput = optional(number)
    })
  })

  validation {
    condition     = try(length(var.boot_disk.initialize_params.image), 0) > 0
    error_message = "Set boot_disk.initialize_params.image: the engine must boot from an engine image."
  }
}

variable "network_interfaces" {
  description = <<-EOT
    Interfaces in guest order: element 0 is `nic0`, element 1 is `nic1`, etc.
    The shape mirrors the instance's `network_interface` block, so an
    interface written for a plain `google_compute_instance` attaches here
    unchanged.

    `nic0` is the management interface. GCP gives a default route to `nic0`
    only, and the metadata server is reachable over it alone.

    Each interface must attach to a different VPC network, and every
    subnetwork must be in the region of `var.zone`.

    The module attaches the addresses you give it; it reserves none. An
    ephemeral external IP is released when the instance stops, and an
    unreserved internal IP can change on replacement, so for either of them
    reserve a `google_compute_address` in your root module and pass its
    `.address` attribute.

    `nic_type` is `VIRTIO_NET` or unset; the engine supports no other type.
  EOT
  type = list(object({
    subnetwork         = string
    subnetwork_project = optional(string)
    network_ip         = optional(string)
    ipv6_address       = optional(string)
    nic_type           = optional(string)
    queue_count        = optional(number)
    stack_type         = optional(string)

    access_config = optional(list(object({
      nat_ip                 = optional(string)
      network_tier           = optional(string)
      public_ptr_domain_name = optional(string)
    })), [])

    ipv6_access_config = optional(list(object({
      network_tier  = string
      external_ipv6 = optional(string)
      name          = optional(string)
    })), [])

    alias_ip_range = optional(list(object({
      ip_cidr_range         = string
      subnetwork_range_name = optional(string)
    })), [])
  }))

  validation {
    condition     = length(var.network_interfaces) >= 1 && length(var.network_interfaces) <= 8
    error_message = "Provide between 1 and 8 network interfaces; GCP allows at most 8 NICs per instance and requires at least one vCPU per NIC."
  }

  # The inputs name subnetworks, not networks, so distinctness is keyed on
  # (project, subnetwork). Same-named subnetworks in different host projects
  # are different subnetworks; if they share one VPC network, GCP rejects
  # the instance at apply time.
  validation {
    condition = length(distinct([
      for nic in var.network_interfaces : [nic.subnetwork_project, nic.subnetwork]
    ])) == length(var.network_interfaces)
    error_message = "Each interface must attach to a different subnetwork; GCP also forbids two NICs of one instance on the same VPC network."
  }

  validation {
    condition = alltrue([
      for nic in var.network_interfaces :
      length(nic.ipv6_access_config) == 0 || nic.stack_type == "IPV4_IPV6"
    ])
    error_message = "ipv6_access_config requires stack_type = \"IPV4_IPV6\" on the same interface."
  }

  validation {
    condition = alltrue([
      for nic in var.network_interfaces :
      nic.nic_type == null || nic.nic_type == "VIRTIO_NET"
    ])
    error_message = "nic_type must be VIRTIO_NET or unset; the engine supports no other type."
  }
}

variable "can_ip_forward" {
  description = <<-EOT
    Allow the instance to send and receive packets whose source or destination
    is not its own address. Required to forward traffic.
  EOT
  type        = bool
  default     = true
}

variable "network_tags" {
  description = <<-EOT
    Network tags applied to the instance. VPC firewall rules and routes select
    instances by these.
  EOT
  type        = list(string)
  default     = []
}

variable "initial_contact" {
  description = <<-EOT
    Initial contact data, either an `engine.cfg` exported from SMC or a cloud
    contact JSON document. Delivered through the `startup-script` metadata key.

    `null` boots an unconfigured engine, configurable over the console or SSH
    with `sg-reconfigure`.
  EOT
  type        = string
  default     = null
  sensitive   = true

  # The message never interpolates the value, so it is safe on a sensitive
  # variable.
  validation {
    condition     = var.initial_contact == null || can(regex("^\\s*\\{", var.initial_contact)) || can(regex("stonegate/", var.initial_contact))
    error_message = "initial_contact must be an engine.cfg initial configuration (containing stonegate/... keys) or a JSON document describing the SMC API contact details."
  }
}

variable "initial_contact_replace_on_change" {
  description = <<-EOT
    Replace the instance when `initial_contact` changes. The engine reads the
    value only on first boot.
  EOT
  type        = bool
  default     = true
}

variable "ssh_public_keys" {
  description = <<-EOT
    Public keys in OpenSSH `authorized_keys` format, granted access as
    `gencloud`. Whether SSH answers is governed by the engine's policy, not
    by GCP.
  EOT
  type        = list(string)
  default     = []
}

variable "block_project_ssh_keys" {
  description = <<-EOT
    Ignore project-wide SSH keys, so only `ssh_public_keys` grant access.
  EOT
  type        = bool
  default     = true
}

variable "enable_guest_attributes" {
  description = <<-EOT
    Enable the guest attributes endpoint, required by the GCP HA Module for peer
    status signalling. On by default. Settable only at instance creation.
  EOT
  type        = bool
  default     = true
}

variable "enable_serial_console" {
  description = <<-EOT
    Enable serial console access. Reachable by anyone holding the IAM permission
    on the project. The only way into an engine that never contacted the SMC.
  EOT
  type        = bool
  default     = false
}

variable "metadata" {
  description = <<-EOT
    Additional instance metadata, merged last. Overrides any key this module
    computes, including `startup-script` and `ssh-keys`.
  EOT
  type        = map(string)
  default     = {}
}

variable "service_account" {
  description = <<-EOT
    Service account to attach, mirroring the instance's `service_account`
    block. Required for engine features that call Google APIs, such as HA
    failover. `null` attaches no account, not even the project default.

    - `scopes` - OAuth scopes. The metadata server only issues tokens for
      scopes granted at creation.
  EOT
  type = object({
    email  = string
    scopes = optional(list(string), ["https://www.googleapis.com/auth/cloud-platform"])
  })
  default = null
}

variable "create_instance_group" {
  description = <<-EOT
    Create a zonal unmanaged instance group for use as a load balancer backend.
  EOT
  type        = bool
  default     = false
}

variable "instance_group_name" {
  description = "Name of the instance group. Defaults to `<name>-ig`."
  type        = string
  default     = null
}

variable "instance_group_named_ports" {
  description = <<-EOT
    Named ports on the instance group. Backend services reference the port by
    name.
  EOT
  type = list(object({
    name = string
    port = number
  }))
  default = []
}

variable "labels" {
  description = <<-EOT
    Labels applied to the instance and to its boot disk.
  EOT
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = <<-EOT
    Reject delete calls, including `terraform destroy`, until cleared.
  EOT
  type        = bool
  default     = false
}

variable "allow_stopping_for_update" {
  description = <<-EOT
    Let Terraform stop the instance for changes that require it, such as the
    machine type or an interface's subnetwork. With `false`, such a plan
    fails.
  EOT
  type        = bool
  default     = true
}

variable "resource_policies" {
  description = <<-EOT
    Self-links of resource policies to attach, for example a snapshot schedule.
  EOT
  type        = list(string)
  default     = []
}
