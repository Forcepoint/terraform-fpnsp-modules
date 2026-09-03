variable "project_id" {
  description = "Project to deploy into."
  type        = string
}

variable "zone" {
  description = <<-EOT
    Zone to deploy into. The three subnetworks are created in its region.
  EOT
  type        = string
  default     = "europe-north1-a"
}

variable "name" {
  description = <<-EOT
    Name prefix for every resource, and the name of the engine instance.
  EOT
  type        = string
  default     = "engine"
}

variable "image" {
  description = "Self-link or name of the engine image."
  type        = string
}

variable "machine_type" {
  description = "Machine type. GCP requires at least one vCPU per interface."
  type        = string
  default     = "n2-standard-4"
}

variable "management_cidr" {
  description = "CIDR of the management subnetwork (nic0)."
  type        = string
  default     = "10.0.0.0/24"
}

variable "wan_cidr" {
  description = "CIDR of the WAN subnetwork (nic2)."
  type        = string
  default     = "10.0.100.0/24"
}

variable "lan_cidr" {
  description = <<-EOT
    CIDR of the LAN subnetwork (nic1), where protected workloads live.
  EOT
  type        = string
  default     = "10.0.1.0/24"
}

variable "allowed_cidrs" {
  description = <<-EOT
    Source ranges permitted to reach the management and WAN interfaces: the
    SMC, your administrative networks and any VPN peer the engine terminates.
    Every protocol and port is allowed from these ranges, so keep the list
    tight. Never `0.0.0.0/0`.
  EOT
  type        = list(string)
}

variable "network_tag" {
  description = <<-EOT
    Network tag applied to the engine. Targeted by the VPC firewall rules.
  EOT
  type        = string
  default     = "engine"
}

variable "protected_network_tag" {
  description = <<-EOT
    Selects which instances in the LAN network route through the engine. The
    engine must not carry it.
  EOT
  type        = string
  default     = "protected"
}

variable "server_image" {
  description = <<-EOT
    Boot image for the protected test server. Any Linux image will do; it only
    needs to originate traffic.
  EOT
  type        = string
  default     = "debian-cloud/debian-12"
}

variable "server_machine_type" {
  description = "Machine type for the protected test server."
  type        = string
  default     = "e2-small"
}

variable "server_user" {
  description = <<-EOT
    Login the `ssh_public_keys` are installed for on the test server. Unlike the
    engine, an ordinary Linux guest has no fixed account.
  EOT
  type        = string
  default     = "admin"
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
    Public keys in OpenSSH format granted SSH access to the engine.
  EOT
  type        = list(string)
  default     = []
}
