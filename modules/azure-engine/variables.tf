variable "name" {
  description = <<-EOT
    Name of the Security Engine virtual machine. Must be a valid Azure
    resource name.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,56}[a-z0-9]$", var.name))
    error_message = "The name must be 2-58 characters of lowercase letters, digits or hyphens, start with a letter and not end with a hyphen."
  }
}

variable "resource_group_name" {
  description = <<-EOT
    Name of the resource group to deploy into. It must already exist, or be
    created by your root module.
  EOT
  type        = string
}

variable "location" {
  description = <<-EOT
    Azure location to deploy into, for example `westeurope`. Every subnet in
    `network_interfaces` must be in this location.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]+$", var.location))
    error_message = "The location must be an Azure region name such as westeurope: lowercase letters and digits, starting with a letter."
  }
}

variable "zone" {
  description = <<-EOT
    Availability zone within `location`, for example `1`. Requires a
    zone-enabled location. `null` leaves the placement within the location.
    Public IPs the module creates inherit this zone.
  EOT
  type        = number
  default     = null

  validation {
    condition     = var.zone == null || contains([1, 2, 3], var.zone)
    error_message = "The zone must be 1, 2 or 3."
  }
}

variable "size" {
  description = <<-EOT
    Virtual machine size, for example `Standard_B4ms`. Determines the
    throughput (memory and network bandwidth) the engine gets, and the
    maximum number of interfaces. Consult the template's marketplace listing
    for the sizes it supports.
  EOT
  type        = string
}

variable "source_image" {
  description = <<-EOT
    Boot image, the template Forcepoint publishes to the Azure Marketplace by
    default.

    - `publisher` - Marketplace publisher, default `forcepoint-llc`.
    - `offer`     - Marketplace product, default `forcepoint-ngfw`.
    - `sku`       - Marketplace plan, default `ngfw_payg` (pay-as-you-go).
      The same offer also publishes `ngfw_byol` for customers who bring
      their own license.
    - `version`   - Template version, default `7.3.5`.
    - `image_id`  - Resource ID of a custom image, community image or shared
      image gallery image. When set, it replaces the template entirely: the
      marketplace fields above are ignored and no plan is attached.
  EOT
  type = object({
    publisher = optional(string, "forcepoint-llc")
    offer     = optional(string, "forcepoint-ngfw")
    sku       = optional(string, "ngfw_payg")
    version   = optional(string, "7.3.5")
    image_id  = optional(string)
  })
  default = {}
}

variable "network_interfaces" {
  description = <<-EOT
    Interfaces in guest order: element 0 is `nic0`, element 1 is `nic1`, and
    so on. `nic0` is the management interface.

    Each element mirrors the arguments the provider takes for
    `azurerm_network_interface`: the interface's arguments and one or more
    `ip_configuration` blocks. The first configuration is the interface's
    primary address; the others are secondary addresses on the same guest
    interface, in the same subnet. With more than one configuration, exactly
    one must carry `primary = true`. The module creates the public IP a
    configuration is given a `public_ip` block for; an existing public IP
    attaches through `public_ip_address_id` instead. Each configuration can
    carry its own public IP.

    The module creates one network interface per element in `location`, and
    attaches the addresses you give it; it reserves none. For a private
    address that must survive an engine replacement, pass a
    `private_ip_address` inside the subnet's prefix, the way the example pins
    host 10 of each subnet.
  EOT
  type = list(object({
    name                      = optional(string)
    ip_forwarding             = optional(bool, true)
    dns_servers               = optional(list(string))
    network_security_group_id = optional(string)

    ip_configuration = list(object({
      name                          = optional(string)
      primary                       = optional(bool, false)
      subnet_id                     = string
      private_ip_address_allocation = optional(string, "Dynamic")
      private_ip_address            = optional(string)
      private_ip_address_version    = optional(string, "IPv4")
      public_ip_address_id          = optional(string)

      public_ip = optional(object({
        name                    = optional(string)
        allocation_method       = optional(string, "Static")
        sku                     = optional(string, "Standard")
        ip_version              = optional(string, "IPv4")
        zone                    = optional(string)
        domain_name_label       = optional(string)
        idle_timeout_in_minutes = optional(number)
        ddos_protection_plan_id = optional(string)
      }))
    }))
  }))

  validation {
    condition     = length(var.network_interfaces) >= 1 && length(var.network_interfaces) <= 8
    error_message = "Provide between 1 and 8 network interfaces; Azure allows at most 8 NICs on most VM sizes."
  }

  validation {
    condition     = alltrue([for nic in var.network_interfaces : length(nic.ip_configuration) >= 1])
    error_message = "Each interface needs at least one ip_configuration."
  }

  # A single configuration is primary without the flag.
  validation {
    condition = alltrue([
      for nic in var.network_interfaces :
      length(nic.ip_configuration) == 1 ||
      length([for config in nic.ip_configuration : config if config.primary]) == 1
    ])
    error_message = "Exactly one ip_configuration must be primary when an interface has more than one."
  }

  # An interface's subnet is that of its first ip_configuration.
  validation {
    condition = length(distinct([
      for nic in var.network_interfaces :
      nic.ip_configuration[0].subnet_id
      if length(nic.ip_configuration) >= 1
      ])) == length([
      for nic in var.network_interfaces :
      nic
      if length(nic.ip_configuration) >= 1
    ])
    error_message = "Each interface must attach to a different subnet."
  }

  validation {
    condition = alltrue([
      for nic in var.network_interfaces :
      length(distinct([for config in nic.ip_configuration : config.subnet_id])) <= 1
    ])
    error_message = "All ip_configuration blocks of an interface must use the same subnet."
  }

  validation {
    condition = alltrue([
      for nic in var.network_interfaces :
      alltrue([
        for config in nic.ip_configuration :
        contains(["Dynamic", "Static"], config.private_ip_address_allocation)
      ])
    ])
    error_message = "ip_configuration.private_ip_address_allocation must be Dynamic or Static."
  }

  validation {
    condition = alltrue([
      for nic in var.network_interfaces :
      alltrue([
        for config in nic.ip_configuration :
        config.private_ip_address_allocation == "Dynamic" || config.private_ip_address != null
      ])
    ])
    error_message = "A static private IP requires private_ip_address."
  }

  validation {
    condition = alltrue([
      for nic in var.network_interfaces :
      alltrue([
        for config in nic.ip_configuration :
        config.private_ip_address == null || config.private_ip_address_allocation == "Static"
      ])
    ])
    error_message = "private_ip_address requires private_ip_address_allocation = \"Static\"."
  }

  validation {
    condition = alltrue([
      for nic in var.network_interfaces :
      alltrue([
        for config in nic.ip_configuration :
        contains(["IPv4", "IPv6"], config.private_ip_address_version)
      ])
    ])
    error_message = "private_ip_address_version must be IPv4 or IPv6."
  }

  validation {
    condition = alltrue([
      for nic in var.network_interfaces :
      alltrue([
        for config in nic.ip_configuration :
        !(config.public_ip != null && config.public_ip_address_id != null)
      ])
    ])
    error_message = "Set either the public_ip block or public_ip_address_id on an ip_configuration, not both."
  }

  validation {
    condition = alltrue([
      for nic in var.network_interfaces :
      alltrue([
        for config in nic.ip_configuration :
        config.public_ip == null || contains(["Dynamic", "Static"], config.public_ip.allocation_method)
      ])
    ])
    error_message = "public_ip.allocation_method must be Dynamic or Static."
  }

  validation {
    condition = alltrue([
      for nic in var.network_interfaces :
      alltrue([
        for config in nic.ip_configuration :
        config.public_ip == null || contains(["Basic", "Standard"], config.public_ip.sku)
      ])
    ])
    error_message = "public_ip.sku must be Basic or Standard."
  }

  validation {
    condition = alltrue([
      for nic in var.network_interfaces :
      alltrue([
        for config in nic.ip_configuration :
        config.public_ip == null || contains(["IPv4", "IPv6"], config.public_ip.ip_version)
      ])
    ])
    error_message = "public_ip.ip_version must be IPv4 or IPv6."
  }

  validation {
    condition = alltrue([
      for nic in var.network_interfaces :
      alltrue([
        for config in nic.ip_configuration :
        !(config.public_ip != null && config.public_ip.allocation_method == "Dynamic" && config.public_ip.sku == "Standard")
      ])
    ])
    error_message = "A Standard SKU public IP requires public_ip.allocation_method = \"Static\"."
  }

  # A public IP without its own zone inherits var.zone.
  validation {
    condition = alltrue([
      for nic in var.network_interfaces :
      alltrue([
        for config in nic.ip_configuration :
        !(
          config.public_ip != null &&
          config.public_ip.sku == "Basic" &&
          (
            config.public_ip.zone != null ||
            (var.zone != null && config.public_ip.zone == null)
          )
        )
      ])
    ])
    error_message = "A public IP in a zone requires public_ip.sku = \"Standard\"."
  }
}

variable "admin_username" {
  description = <<-EOT
    Login the `ssh_public_keys` grant access as. Whether SSH answers is
    governed by the engine's policy, not by Azure.
  EOT
  type        = string
  default     = "azure"
}

variable "ssh_public_keys" {
  description = <<-EOT
    Public keys in OpenSSH `authorized_keys` format, granted access as
    `admin_username`. The virtual machine takes no password, so at least one
    key is required.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.ssh_public_keys) > 0 && alltrue([for key in var.ssh_public_keys : length(trimspace(key)) > 0])
    error_message = "Provide at least one public key: the virtual machine takes no password."
  }
}

variable "initial_contact" {
  description = <<-EOT
    Initial contact data, either an `engine.cfg` exported from SMC or a cloud
    contact JSON document. Delivered through the virtual machine's custom data.
    A change replaces the virtual machine.

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

variable "os_disk" {
  description = <<-EOT
    Operating system disk, mirroring the virtual machine's `os_disk` block.

    - `caching`                - `ReadWrite` or `None`.
    - `disk_size_gb`           - size of the disk in GB. `null` uses the
      image's minimum size.
    - `storage_account_type`   - for example `StandardSSD_LRS`,
      `Premium_LRS`.
    - `disk_encryption_set_id` - ID of a disk encryption set to encrypt the
      disk with.
  EOT
  type = object({
    caching                = optional(string, "ReadWrite")
    disk_size_gb           = optional(number)
    storage_account_type   = optional(string, "StandardSSD_LRS")
    disk_encryption_set_id = optional(string)
  })
  default = {}

  validation {
    condition     = var.os_disk.caching == null || contains(["None", "ReadWrite"], var.os_disk.caching)
    error_message = "os_disk.caching must be None or ReadWrite."
  }

  validation {
    condition = contains(
      [
        "Standard_LRS",
        "StandardSSD_LRS",
        "StandardSSD_ZRS",
        "Premium_LRS",
        "Premium_ZRS",
      ],
      var.os_disk.storage_account_type,
    )
    error_message = "os_disk.storage_account_type must be one of Standard_LRS, StandardSSD_LRS, StandardSSD_ZRS, Premium_LRS, Premium_ZRS."
  }
}

variable "tags" {
  description = <<-EOT
    Tags applied to the virtual machine. The network interfaces and public
    IPs the module creates are not tagged.
  EOT
  type        = map(string)
  default     = {}
}

variable "computer_name" {
  description = <<-EOT
    Host name of the virtual machine, applied at first boot. `null` uses
    `name`. Changing it replaces the instance.
  EOT
  type        = string
  default     = null
}

variable "identity" {
  description = <<-EOT
    Managed service identity, mirroring the virtual machine's `identity`
    block. `null` configures no identity.

    - `type`         - `SystemAssigned`, `UserAssigned`, or
      `SystemAssigned, UserAssigned` (both).
    - `identity_ids` - IDs of user-assigned identities to attach. Required
      when `type` includes `UserAssigned`, and not allowed with a
      `SystemAssigned` identity alone.

    An HA pair, for example, runs its failover script under a user-assigned
    identity authorized on the Azure API.
  EOT
  type = object({
    type         = string
    identity_ids = optional(list(string))
  })
  default = null

  validation {
    condition     = var.identity == null || contains(["SystemAssigned", "UserAssigned", "SystemAssigned, UserAssigned"], var.identity.type)
    error_message = "identity.type must be SystemAssigned, UserAssigned or \"SystemAssigned, UserAssigned\"."
  }

  validation {
    condition = var.identity == null || (
      var.identity.type == "SystemAssigned" ?
      var.identity.identity_ids == null :
      var.identity.identity_ids != null && length(var.identity.identity_ids) > 0
    )
    error_message = "identity.identity_ids is required when the identity includes UserAssigned, and must be left unset for a SystemAssigned identity alone."
  }
}

variable "boot_diagnostics" {
  description = <<-EOT
    Boot diagnostics, mirroring the virtual machine's `boot_diagnostics`
    block. Stores the serial console output and screenshots.

    - `enabled`             - `true` by default. `false` stores nothing.
    - `storage_account_uri` - primary or secondary endpoint of the storage
      account that receives the diagnostics. `null` lets Azure use a managed
      storage account for the resource group.
  EOT
  type = object({
    enabled             = optional(bool, true)
    storage_account_uri = optional(string)
  })
  default = {}
}

variable "priority" {
  description = <<-EOT
    Priority of the virtual machine, mirroring `priority`: `Regular` by
    default, or `Spot` to run the engine at a lower price and let Azure evict
    it. Changing it replaces the instance.
  EOT
  type        = string
  default     = "Regular"

  validation {
    condition     = contains(["Regular", "Spot"], var.priority)
    error_message = "priority must be Regular or Spot."
  }
}

variable "eviction_policy" {
  description = <<-EOT
    What happens when a spot virtual machine is evicted for price reasons:
    `Deallocate` or `Delete`. Mirrors `eviction_policy`; it only applies with
    `priority = "Spot"`. Changing it replaces the instance.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.eviction_policy == null || contains(["Deallocate", "Delete"], var.eviction_policy)
    error_message = "eviction_policy must be Deallocate or Delete."
  }

  validation {
    condition     = var.priority != "Spot" ? var.eviction_policy == null : true
    error_message = "eviction_policy applies to spot virtual machines only; set priority = \"Spot\"."
  }
}

variable "max_bid_price" {
  description = <<-EOT
    Maximum hourly price, in US dollars, that a spot virtual machine may cost
    before it is evicted. Mirrors `max_bid_price`; it only applies with
    `priority = "Spot"`. `null` leaves the platform default (-1, never evict
    for price).
  EOT
  type        = number
  default     = null

  validation {
    condition     = var.max_bid_price == null || var.max_bid_price >= -1
    error_message = "max_bid_price must be at least -1."
  }

  validation {
    condition     = var.priority != "Spot" ? var.max_bid_price == null : true
    error_message = "max_bid_price applies to spot virtual machines only; set priority = \"Spot\"."
  }
}

variable "availability_set_id" {
  description = <<-EOT
    ID of an availability set to run the virtual machine in. Mirrors
    `availability_set_id`. An availability set and an availability zone are
    mutually exclusive in Azure.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.availability_set_id == null || var.zone == null
    error_message = "An availability set and an availability zone cannot both be set."
  }
}

variable "capacity_reservation_group_id" {
  description = <<-EOT
    ID of a capacity reservation group to allocate the virtual machine to.
    Mirrors `capacity_reservation_group_id`. Mutually exclusive with
    `availability_set_id`.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.capacity_reservation_group_id == null || var.availability_set_id == null
    error_message = "A capacity reservation group and an availability set cannot both be set."
  }
}

variable "dedicated_host_id" {
  description = <<-EOT
    ID of a dedicated host to run the virtual machine on. Mirrors
    `dedicated_host_id`. Mutually exclusive with
    `dedicated_host_group_id`.
  EOT
  type        = string
  default     = null
}

variable "dedicated_host_group_id" {
  description = <<-EOT
    ID of a dedicated host group to run the virtual machine within. Mirrors
    `dedicated_host_group_id`. Mutually exclusive with `dedicated_host_id`.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.dedicated_host_id == null || var.dedicated_host_group_id == null
    error_message = "Set either dedicated_host_id or dedicated_host_group_id, not both."
  }
}

variable "disk_controller_type" {
  description = <<-EOT
    Disk controller type for the virtual machine's disks, mirroring
    `disk_controller_type`: `SCSI` or `NVMe`. `null` lets the platform
    choose.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.disk_controller_type == null || contains(["SCSI", "NVMe"], var.disk_controller_type)
    error_message = "disk_controller_type must be SCSI or NVMe."
  }
}
