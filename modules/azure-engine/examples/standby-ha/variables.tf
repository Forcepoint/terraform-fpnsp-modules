variable "resource_group_name" {
  description = <<-EOT
    Name of the resource group for the example. Created by it; `destroy`
    removes it with everything in it.
  EOT
  type        = string
}

variable "resource_group_tags" {
  description = <<-EOT
    Tags applied to the resource group.
  EOT
  type        = map(string)
  default     = {}
}

variable "location" {
  description = <<-EOT
    Azure location to deploy into. The virtual networks, subnets, the
    engines and the servers are created in it.
  EOT
  type        = string
  default     = "westeurope"
}

variable "name" {
  description = <<-EOT
    Name prefix for the example's resources. The engines are named
    `<name>-primary` and `<name>-secondary`.
  EOT
  type        = string
  default     = "example"

  # Leaves room for the -secondary suffix within the module's name limit.
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,45}[a-z0-9]$", var.name))
    error_message = "The name must be 2-47 characters of lowercase letters, digits or hyphens, start with a letter and not end with a hyphen."
  }
}

variable "size" {
  description = <<-EOT
    Virtual machine size for the engines, for example `Standard_B4ms`. See
    the template's marketplace listing for the sizes it supports. The
    default carries the three interfaces.
  EOT
  type        = string
  default     = "Standard_B4ms"
}

variable "engine_image_version" {
  description = <<-EOT
    Template version the engines boot from, for example `7.5.1`.
  EOT
  type        = string
  default     = "7.3.5"
}

variable "zone_primary" {
  description = "Availability zone for the primary engine."
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 2, 3], var.zone_primary)
    error_message = "zone_primary must be 1, 2 or 3."
  }
}

variable "zone_secondary" {
  description = "Availability zone for the secondary engine."
  type        = number
  default     = 2

  validation {
    condition     = contains([1, 2, 3], var.zone_secondary) && var.zone_secondary != var.zone_primary
    error_message = "zone_secondary must be 1, 2 or 3, and differ from zone_primary: the pair spans two zones."
  }
}

variable "admin_username" {
  description = "Login the `ssh_public_keys` grant access as on the engines."
  type        = string
  default     = "azure"
}

variable "ssh_public_keys" {
  description = "Public keys in OpenSSH `authorized_keys` format, installed on the engines and the servers at first boot."
  type        = list(string)

  validation {
    condition     = length(var.ssh_public_keys) > 0 && alltrue([for key in var.ssh_public_keys : length(trimspace(key)) > 0])
    error_message = "Provide at least one public key."
  }
}

variable "hub_vnet_cidr" {
  description = "CIDR of the hub virtual network, which holds the engines' subnets."
  type        = string
  default     = "10.0.0.0/16"
}

variable "management_cidr" {
  description = "CIDR of the management subnet (nic0), inside `hub_vnet_cidr`."
  type        = string
  default     = "10.0.0.0/24"
}

variable "lan_cidr" {
  description = "CIDR of the LAN subnet (nic1), inside `hub_vnet_cidr`."
  type        = string
  default     = "10.0.1.0/24"
}

variable "wan_cidr" {
  description = <<-EOT
    CIDR of the WAN subnet (nic2), inside `hub_vnet_cidr`. At least /27:
    the engines pin hosts 10 through 15 in it, the primary on the even
    hosts and the secondary on the odd ones.
  EOT
  type        = string
  default     = "10.0.100.0/24"

  validation {
    condition     = can(regex("/(0|[1-9]|1[0-9]|2[0-7])$", var.wan_cidr))
    error_message = "wan_cidr must be a CIDR with a prefix of at most /27: the engines pin hosts 10 through 15 in it."
  }
}

variable "spoke_vnet_cidr" {
  description = "CIDR of the spoke virtual network, which holds the servers' subnets."
  type        = string
  default     = "10.1.0.0/16"
}

variable "spoke_a_subnet_cidr" {
  description = "CIDR of the server a subnet, inside `spoke_vnet_cidr`."
  type        = string
  default     = "10.1.0.0/24"
}

variable "spoke_b_subnet_cidr" {
  description = "CIDR of the server b subnet, inside `spoke_vnet_cidr`. Must not overlap `spoke_a_subnet_cidr`."
  type        = string
  default     = "10.1.1.0/24"
}

variable "allowed_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the engines' management interfaces and to open
    SSH to the servers. With the control bypass enabled, their traffic to
    the administrative networks also keeps flowing when an engine is down.
  EOT
  type        = list(string)
}

variable "server_user" {
  description = "Login the `ssh_public_keys` are installed for on the servers."
  type        = string
  default     = "azureuser"
}

variable "server_machine_type" {
  description = "Virtual machine size for the servers."
  type        = string
  default     = "Standard_B1s"
}

variable "enable_control_bypass" {
  description = <<-EOT
    Route the servers' traffic to `allowed_cidrs` around the engines, so the
    servers stay reachable from those ranges when an engine is down.
  EOT
  type        = bool
  default     = true
}

variable "enable_ha_identity" {
  description = <<-EOT
    Create the user-assigned identity and the resource-group-scoped role
    the cloud HA failover script runs under, and attach the identity to
    both engines.
  EOT
  type        = bool
  default     = true
}

variable "initial_contact_primary" {
  description = <<-EOT
    Initial contact data for the primary engine: an `engine.cfg` exported
    from the SMC, or a cloud contact JSON document. `null` boots an
    unconfigured engine.
  EOT
  type        = string
  default     = null
  sensitive   = true
}

variable "initial_contact_secondary" {
  description = <<-EOT
    Initial contact data for the secondary engine: an `engine.cfg` exported
    from the SMC, or a cloud contact JSON document. `null` boots an
    unconfigured engine.
  EOT
  type        = string
  default     = null
  sensitive   = true
}
