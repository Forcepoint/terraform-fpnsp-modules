variable "resource_group_name" {
  description = <<-EOT
    Name of the resource group for the example. Created by it; `destroy`
    removes it with everything in it.
  EOT
  type        = string
}

variable "location" {
  description = <<-EOT
    Azure location to deploy into. The virtual network, subnets and the
    engine are created in it.
  EOT
  type        = string
  default     = "westeurope"
}

variable "name" {
  description = "Name prefix for every resource, and the name of the engine virtual machine."
  type        = string
  default     = "example"
}

variable "size" {
  description = <<-EOT
    Virtual machine size for the engine, for example `Standard_B4ms`. See
    the template's marketplace listing for the sizes it supports.
  EOT
  type        = string
  default     = "Standard_B4ms"
}

variable "engine_image_version" {
  description = <<-EOT
    Template version the engine boots from, for example `7.5.1`.
  EOT
  type        = string
  default     = "7.3.5"
}

variable "admin_username" {
  description = "Login the `ssh_public_keys` grant access as on the engine."
  type        = string
  default     = "azure"
}

variable "vnet_cidr" {
  description = "CIDR of the virtual network."
  type        = string
  default     = "10.0.0.0/16"
}

variable "management_cidr" {
  description = "CIDR of the management subnet (nic0)."
  type        = string
  default     = "10.0.0.0/24"
}

variable "lan_cidr" {
  description = "CIDR of the LAN subnet (nic1), where protected workloads live."
  type        = string
  default     = "10.0.1.0/24"
}

variable "wan_cidr" {
  description = "CIDR of the WAN subnet (nic2)."
  type        = string
  default     = "10.0.100.0/24"
}

variable "enable_bastion" {
  description = "Deploy Azure Bastion for access to the protected server; it bills from deployment."
  type        = bool
  default     = false
}

variable "bastion_subnet_cidr" {
  description = <<-EOT
    CIDR of the `AzureBastionSubnet`, inside `vnet_cidr`. Azure requires at
    least a /26.
  EOT
  type        = string
  default     = "10.0.200.0/26"

  validation {
    condition     = can(tonumber(regex("^.*?/([0-9]+)$", var.bastion_subnet_cidr)[0]) <= 26)
    error_message = "The Bastion subnet must be at least a /26: Azure requires 64 addresses or more."
  }
}

variable "enable_control_bypass" {
  description = "Route the workloads' traffic to `allowed_cidrs` around the engine, so the workloads stay reachable from those ranges when the engine is down."
  type        = bool
  default     = true
}

variable "allowed_cidrs" {
  description = <<-EOT
    Source ranges permitted to reach the management and WAN interfaces: the
    SMC, your administrative networks and any VPN peer the engine terminates.
    Every protocol and port is allowed from these ranges, so keep the list
    tight. Never `0.0.0.0/0`. By default, workload traffic to these ranges
    bypasses the engine, so the workloads stay reachable from them when the
    engine is down.
  EOT
  type        = list(string)
}

variable "server_user" {
  description = "Login the `ssh_public_keys` are installed for on the test server."
  type        = string
  default     = "azureuser"
}

variable "server_machine_type" {
  description = "Virtual machine size for the protected test server."
  type        = string
  default     = "Standard_B1s"
}

variable "initial_contact" {
  description = <<-EOT
    `engine.cfg` exported from the SMC, or a cloud contact document.
  EOT
  type        = string
  default     = null
  sensitive   = true
}

variable "ssh_public_keys" {
  description = <<-EOT
    Public keys in OpenSSH format, installed for `admin_username` on the
    engine and for `server_user` on the test server.
  EOT
  type        = list(string)
}
