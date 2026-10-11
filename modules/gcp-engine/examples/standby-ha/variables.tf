variable "project_id" {
  description = <<-EOT
    Project to deploy into. The project ID, not its number: the failover
    script's instance references are built from it.
  EOT
  type        = string
}

variable "name" {
  description = <<-EOT
    Name prefix for the example's resources. The engines are named
    `<name>-primary` and `<name>-secondary`.
  EOT
  type        = string
  default     = "example"

  # Leaves room for the -ha-sa suffix within the service account ID's
  # 30-character limit.
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name))
    error_message = "The name must be 2-24 characters of lowercase letters, digits or hyphens, start with a letter and not end with a hyphen."
  }
}

variable "machine_type" {
  description = <<-EOT
    Machine type for the engines. GCP requires at least one vCPU per
    interface; the default carries the three interfaces.
  EOT
  type        = string
  default     = "n2-standard-4"
}

variable "image" {
  description = <<-EOT
    Self-link or name of the engine image the engines boot from, for example
    `projects/my-project/global/images/engine-7-6-0`.
  EOT
  type        = string
}

variable "zone_primary" {
  description = <<-EOT
    Zone for the primary engine, for example `europe-north1-a`. The
    networks, the subnetworks and the servers are created in its region.
  EOT
  type        = string
  default     = "europe-north1-a"

  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+-[a-z]$", var.zone_primary))
    error_message = "zone_primary must be a GCE zone name such as europe-north1-a."
  }
}

variable "zone_secondary" {
  description = <<-EOT
    Zone for the secondary engine. Must differ from `zone_primary` and be in
    the same region.
  EOT
  type        = string
  default     = "europe-north1-b"

  validation {
    condition = (
      can(regex("^[a-z]+-[a-z0-9]+-[a-z]$", var.zone_secondary)) &&
      var.zone_secondary != var.zone_primary &&
      join("-", slice(split("-", var.zone_secondary), 0, 2)) == join("-", slice(split("-", var.zone_primary), 0, 2))
    )
    error_message = "zone_secondary must be a GCE zone name in the region of zone_primary, and differ from it: the pair spans two zones."
  }
}

variable "ssh_public_keys" {
  description = <<-EOT
    Public keys in OpenSSH `authorized_keys` format, installed for
    `gencloud` on the engines and for `server_user` on the servers at first
    boot.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.ssh_public_keys) > 0 && alltrue([for key in var.ssh_public_keys : length(trimspace(key)) > 0])
    error_message = "Provide at least one public key."
  }
}

variable "management_cidr" {
  description = <<-EOT
    CIDR of the management subnetwork (nic0). At least /28: the engines pin
    hosts 10 and 11 in it.
  EOT
  type        = string
  default     = "10.20.0.0/24"

  validation {
    condition     = can(regex("/(1[0-9]|2[0-8])$", var.management_cidr))
    error_message = "management_cidr must be a CIDR with a prefix of /10 to /28: the engines pin hosts 10 and 11 in it."
  }
}

variable "lan_cidr" {
  description = <<-EOT
    CIDR of the LAN subnetwork (nic1). At least /28: the engines pin hosts
    10 and 11 in it.
  EOT
  type        = string
  default     = "10.20.1.0/24"

  validation {
    condition     = can(regex("/(1[0-9]|2[0-8])$", var.lan_cidr))
    error_message = "lan_cidr must be a CIDR with a prefix of /10 to /28: the engines pin hosts 10 and 11 in it."
  }
}

variable "wan_cidr" {
  description = <<-EOT
    CIDR of the WAN subnetwork (nic2). At least /28: the engines pin hosts
    10 and 11 in it.
  EOT
  type        = string
  default     = "10.20.100.0/24"

  validation {
    condition     = can(regex("/(1[0-9]|2[0-8])$", var.wan_cidr))
    error_message = "wan_cidr must be a CIDR with a prefix of /10 to /28: the engines pin hosts 10 and 11 in it."
  }
}

variable "server_a_cidr" {
  description = <<-EOT
    CIDR of the server a subnetwork, in the LAN network. At least /25: the
    server is pinned at host 120.
  EOT
  type        = string
  default     = "10.20.2.0/24"

  validation {
    condition     = can(regex("/(1[0-9]|2[0-5])$", var.server_a_cidr))
    error_message = "server_a_cidr must be a CIDR with a prefix of /10 to /25: the server is pinned at host 120."
  }
}

variable "server_b_cidr" {
  description = <<-EOT
    CIDR of the server b subnetwork, in the LAN network. At least /25: the
    server is pinned at host 120. Must not overlap `server_a_cidr`.
  EOT
  type        = string
  default     = "10.20.3.0/24"

  validation {
    condition     = can(regex("/(1[0-9]|2[0-5])$", var.server_b_cidr))
    error_message = "server_b_cidr must be a CIDR with a prefix of /10 to /25: the server is pinned at host 120."
  }
}

variable "allowed_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the engines' management interfaces and the
    servers, over any protocol: the SMC, the addresses you administer the
    engines from, and the networks of any VPN peer site.
  EOT
  type        = list(string)
}

variable "network_tag" {
  description = <<-EOT
    Network tag applied to the engines. Targeted by the VPC firewall rules.
  EOT
  type        = string
  default     = "engine"
}

variable "protected_network_tag" {
  description = <<-EOT
    Selects which instances in the LAN network route through the engines.
    The engines must not carry it.
  EOT
  type        = string
  default     = "protected"
}

variable "server_image" {
  description = <<-EOT
    Boot image for the protected servers. Any Linux image will do; they only
    need to originate traffic.
  EOT
  type        = string
  default     = "debian-cloud/debian-12"
}

variable "server_user" {
  description = "Login the `ssh_public_keys` are installed for on the servers."
  type        = string
  default     = "admin"
}

variable "server_machine_type" {
  description = "Machine type for the servers."
  type        = string
  default     = "e2-small"
}

variable "wan_floating_ip" {
  description = <<-EOT
    Give the WAN interfaces (nic2) one public IP, which the failover script
    attaches to the active engine, for a policy-based VPN. `false` gives
    each engine a public IP of its own, which stays put, for a route-based
    VPN with a tunnel to each engine.
  EOT
  type        = bool
  default     = true
}

variable "enable_ha_identity" {
  description = <<-EOT
    Create the service account and the project-scoped custom role the cloud
    HA failover script runs under, and attach the service account to both
    engines.
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
