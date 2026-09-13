data "azurerm_client_config" "current" {}

locals {
  # The engines' addresses are pinned inside each hub subnet, so a static
  # SMC interface configuration keeps working. The primary takes the even
  # hosts, the secondary the odd ones.
  addresses = {
    primary = {
      management = cidrhost(var.management_cidr, 10)
      lan        = cidrhost(var.lan_cidr, 10)
      wan        = cidrhost(var.wan_cidr, 10)
      wan_weba   = cidrhost(var.wan_cidr, 12)
      wan_webb   = cidrhost(var.wan_cidr, 14)
    }
    secondary = {
      management = cidrhost(var.management_cidr, 11)
      lan        = cidrhost(var.lan_cidr, 11)
      wan        = cidrhost(var.wan_cidr, 11)
      wan_weba   = cidrhost(var.wan_cidr, 13)
      wan_webb   = cidrhost(var.wan_cidr, 15)
    }
  }

  # The protected servers, one per subnet of the spoke virtual network,
  # pinned at host 120.
  servers = {
    a = {
      vnet   = azurerm_virtual_network.spoke
      subnet = azurerm_subnet.spoke["a"]
      ip     = cidrhost(var.spoke_a_subnet_cidr, 120)
      nsg    = azurerm_network_security_group.server_a
    }
    b = {
      vnet   = azurerm_virtual_network.spoke
      subnet = azurerm_subnet.spoke["b"]
      ip     = cidrhost(var.spoke_b_subnet_cidr, 120)
      nsg    = azurerm_network_security_group.server_b
    }
  }

  # Read by the failover script. A reserved public IP is
  # `public address,primary private address,secondary private address`.
  ha_tags = {
    FP_HA_route_table_id          = azurerm_route_table.spoke.id
    FP_HA_internal_nic_idx        = "1"
    FP_HA_primary_instance_id     = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Compute/virtualMachines/${var.name}-primary"
    FP_HA_secondary_instance_id   = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.Compute/virtualMachines/${var.name}-secondary"
    FP_HA_reserved_public_ip_vpn  = "${azurerm_public_ip.ha["vpn"].ip_address},${local.addresses.primary.wan},${local.addresses.secondary.wan}"
    FP_HA_reserved_public_ip_weba = "${azurerm_public_ip.ha["weba"].ip_address},${local.addresses.primary.wan_weba},${local.addresses.secondary.wan_weba}"
    FP_HA_reserved_public_ip_webb = "${azurerm_public_ip.ha["webb"].ip_address},${local.addresses.primary.wan_webb},${local.addresses.secondary.wan_webb}"
  }

  # The role assignment's name must be a UUID.
  ha_role_assignment_digest = md5("${var.resource_group_name}/${var.name}-ha")
  ha_role_assignment_name = format(
    "%s-%s-%s-%s-%s",
    substr(local.ha_role_assignment_digest, 0, 8),
    substr(local.ha_role_assignment_digest, 8, 4),
    substr(local.ha_role_assignment_digest, 12, 4),
    substr(local.ha_role_assignment_digest, 16, 4),
    substr(local.ha_role_assignment_digest, 20, 12)
  )
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.resource_group_tags
}

# --- Hub virtual network: the engines' subnets ---

resource "azurerm_virtual_network" "hub" {
  name                = "${var.name}-hub"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = [var.hub_vnet_cidr]
}

resource "azurerm_subnet" "hub" {
  for_each = {
    management = var.management_cidr
    lan        = var.lan_cidr
    wan        = var.wan_cidr
  }

  name                 = "${var.name}-${each.key}"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [each.value]
}

# --- Spoke virtual network: one subnet per server ---

resource "azurerm_virtual_network" "spoke" {
  name                = "${var.name}-spoke"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = [var.spoke_vnet_cidr]
}

resource "azurerm_subnet" "spoke" {
  for_each = {
    a = var.spoke_a_subnet_cidr
    b = var.spoke_b_subnet_cidr
  }

  name                 = "${var.name}-${each.key}"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [each.value]
}

# Forwarded traffic is allowed both ways: the engines forward between the
# hub and the spoke.
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "hub-to-spoke"
  resource_group_name          = azurerm_resource_group.this.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "spoke-to-hub"
  resource_group_name          = azurerm_resource_group.this.name
  virtual_network_name         = azurerm_virtual_network.spoke.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

# --- Network security groups ---

# Policy lives in the SMC, so these rules scope by source range only, not by
# port. Azure inbound is default-deny.

resource "azurerm_network_security_group" "management" {
  name                = "${var.name}-allow-management"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "allow-admins-and-smc"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = var.allowed_cidrs
    destination_address_prefix = "*"
  }

  # Own virtual network included, so the engines reach each other.
  security_rule {
    name                       = "allow-hub"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.hub_vnet_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-outbound"
    priority                   = 1000
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# The LAN interface is the servers' next hop, and the failover script probes
# the primary over it.
resource "azurerm_network_security_group" "lan" {
  name                = "${var.name}-allow-lan"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "allow-vnets"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = [var.hub_vnet_cidr, var.spoke_vnet_cidr]
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-outbound"
    priority                   = 1000
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Open by design: the engine's policy decides what reaches the servers.
resource "azurerm_network_security_group" "wan" {
  name                = "${var.name}-allow-wan"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "allow-internet"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "0.0.0.0/0"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-outbound"
    priority                   = 1000
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "server_a" {
  name                = "${var.name}-allow-server-a"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "allow-ssh"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.allowed_cidrs
    destination_address_prefix = "*"
  }

  # Traffic sourced from the hub.
  security_rule {
    name                       = "allow-engines"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.hub_vnet_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-outbound"
    priority                   = 1000
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "server_b" {
  name                = "${var.name}-allow-server-b"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "allow-ssh"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.allowed_cidrs
    destination_address_prefix = "*"
  }

  # Traffic sourced from the hub.
  security_rule {
    name                       = "allow-engines"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.hub_vnet_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-outbound"
    priority                   = 1000
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "management" {
  subnet_id                 = azurerm_subnet.hub["management"].id
  network_security_group_id = azurerm_network_security_group.management.id
}

resource "azurerm_subnet_network_security_group_association" "lan" {
  subnet_id                 = azurerm_subnet.hub["lan"].id
  network_security_group_id = azurerm_network_security_group.lan.id
}

resource "azurerm_subnet_network_security_group_association" "wan" {
  subnet_id                 = azurerm_subnet.hub["wan"].id
  network_security_group_id = azurerm_network_security_group.wan.id
}

resource "azurerm_subnet_network_security_group_association" "server_a" {
  subnet_id                 = azurerm_subnet.spoke["a"].id
  network_security_group_id = azurerm_network_security_group.server_a.id
}

resource "azurerm_subnet_network_security_group_association" "server_b" {
  subnet_id                 = azurerm_subnet.spoke["b"].id
  network_security_group_id = azurerm_network_security_group.server_b.id
}

# --- Routing: the servers' egress goes through the engines ---

# One table for both server subnets. The failover script rewrites the next
# hop to the active engine.

resource "azurerm_route_table" "spoke" {
  name                = "${var.name}-spoke-rt"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  route {
    name                   = "default-via-engine"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.addresses.primary.lan
  }

  dynamic "route" {
    for_each = var.enable_control_bypass ? var.allowed_cidrs : []

    content {
      name           = "to-allowed-${replace(route.value, "/", "-")}"
      address_prefix = route.value
      next_hop_type  = "Internet"
    }
  }
}

resource "azurerm_subnet_route_table_association" "spoke" {
  for_each = azurerm_subnet.spoke

  subnet_id      = each.value.id
  route_table_id = azurerm_route_table.spoke.id
}

# --- The pair's reserved public IPs ---

# Left unattached: the failover script attaches each to the active engine's
# WAN interface. Zone-redundant, as the engines sit in different zones.

resource "azurerm_public_ip" "ha" {
  for_each = toset(["vpn", "weba", "webb"])

  name                = "${var.name}-ha-${each.value}-pip"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

# --- The failover identity ---

resource "azurerm_user_assigned_identity" "ha" {
  count               = var.enable_ha_identity ? 1 : 0
  name                = "${var.name}-ha-identity"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
}

resource "azurerm_role_definition" "ha" {
  count       = var.enable_ha_identity ? 1 : 0
  name        = "${var.name}-ha"
  description = "Actions the Forcepoint NGFW cloud HA failover script needs in this resource group."
  scope       = azurerm_resource_group.this.id

  permissions {
    actions = [
      "Microsoft.Compute/virtualMachines/read",
      "Microsoft.Compute/virtualMachines/write",
      "Microsoft.Compute/virtualMachines/instanceView/read",
      "Microsoft.Network/routeTables/read",
      "Microsoft.Network/routeTables/write",
      "Microsoft.Network/routeTables/routes/write",
      "Microsoft.Network/publicIPAddresses/read",
      "Microsoft.Network/publicIPAddresses/write",
      "Microsoft.Network/publicIPAddresses/join/action",
      "Microsoft.Network/networkInterfaces/read",
      "Microsoft.Network/networkInterfaces/write",
      "Microsoft.Network/virtualNetworks/subnets/read",
      "Microsoft.Network/virtualNetworks/subnets/join/action",
    ]
  }
}

resource "azurerm_role_assignment" "ha" {
  count              = var.enable_ha_identity ? 1 : 0
  name               = local.ha_role_assignment_name
  scope              = azurerm_resource_group.this.id
  role_definition_id = azurerm_role_definition.ha[0].role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.ha[0].principal_id
}

# --- The engines ---

# The failover script attaches the reserved public IPs outside of Terraform.
# The engines depend on them, so a destroy deletes the engines' interfaces,
# and the attachments with them, before the public IPs.

module "primary" {
  source = "github.com/Forcepoint/terraform-fpnsp-modules//modules/azure-engine"

  name                = "${var.name}-primary"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  size                = var.size
  zone                = var.zone_primary

  source_image = { version = var.engine_image_version }

  network_interfaces = [
    {
      ip_configuration = [
        {
          primary                       = true
          subnet_id                     = azurerm_subnet.hub["management"].id
          private_ip_address_allocation = "Static"
          private_ip_address            = local.addresses.primary.management
          public_ip                     = {}
        },
      ]
    },
    {
      ip_configuration = [
        {
          primary                       = true
          subnet_id                     = azurerm_subnet.hub["lan"].id
          private_ip_address_allocation = "Static"
          private_ip_address            = local.addresses.primary.lan
        },
      ]
    },
    {
      ip_configuration = [
        {
          primary                       = true
          subnet_id                     = azurerm_subnet.hub["wan"].id
          private_ip_address_allocation = "Static"
          private_ip_address            = local.addresses.primary.wan
        },
        {
          name                          = "ip-wan-2"
          subnet_id                     = azurerm_subnet.hub["wan"].id
          private_ip_address_allocation = "Static"
          private_ip_address            = local.addresses.primary.wan_weba
        },
        {
          name                          = "ip-wan-3"
          subnet_id                     = azurerm_subnet.hub["wan"].id
          private_ip_address_allocation = "Static"
          private_ip_address            = local.addresses.primary.wan_webb
        },
      ]
    },
  ]

  admin_username  = var.admin_username
  ssh_public_keys = var.ssh_public_keys

  initial_contact = var.initial_contact_primary

  identity = var.enable_ha_identity ? {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.ha[0].id]
  } : null

  tags = local.ha_tags

  depends_on = [azurerm_public_ip.ha]
}

module "secondary" {
  source = "github.com/Forcepoint/terraform-fpnsp-modules//modules/azure-engine"

  name                = "${var.name}-secondary"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  size                = var.size
  zone                = var.zone_secondary

  source_image = { version = var.engine_image_version }

  network_interfaces = [
    {
      ip_configuration = [
        {
          primary                       = true
          subnet_id                     = azurerm_subnet.hub["management"].id
          private_ip_address_allocation = "Static"
          private_ip_address            = local.addresses.secondary.management
          public_ip                     = {}
        },
      ]
    },
    {
      ip_configuration = [
        {
          primary                       = true
          subnet_id                     = azurerm_subnet.hub["lan"].id
          private_ip_address_allocation = "Static"
          private_ip_address            = local.addresses.secondary.lan
        },
      ]
    },
    {
      ip_configuration = [
        {
          primary                       = true
          subnet_id                     = azurerm_subnet.hub["wan"].id
          private_ip_address_allocation = "Static"
          private_ip_address            = local.addresses.secondary.wan
        },
        {
          name                          = "ip-wan-2"
          subnet_id                     = azurerm_subnet.hub["wan"].id
          private_ip_address_allocation = "Static"
          private_ip_address            = local.addresses.secondary.wan_weba
        },
        {
          name                          = "ip-wan-3"
          subnet_id                     = azurerm_subnet.hub["wan"].id
          private_ip_address_allocation = "Static"
          private_ip_address            = local.addresses.secondary.wan_webb
        },
      ]
    },
  ]

  admin_username  = var.admin_username
  ssh_public_keys = var.ssh_public_keys

  initial_contact = var.initial_contact_secondary

  identity = var.enable_ha_identity ? {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.ha[0].id]
  } : null

  tags = local.ha_tags

  depends_on = [azurerm_public_ip.ha]
}

# --- The protected servers ---

resource "azurerm_public_ip" "server" {
  for_each = local.servers

  name                = "${var.name}-server-${each.key}-pip"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "server" {
  for_each = local.servers

  name                = "${var.name}-server-${each.key}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "ip-server"
    subnet_id                     = each.value.subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
    public_ip_address_id          = azurerm_public_ip.server[each.key].id
  }
}

resource "azurerm_linux_virtual_machine" "server" {
  for_each = local.servers

  name                = "${var.name}-server-${each.key}"
  admin_username      = var.server_user
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  size                = var.server_machine_type

  network_interface_ids = [
    azurerm_network_interface.server[each.key].id,
  ]

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  dynamic "admin_ssh_key" {
    for_each = var.ssh_public_keys

    content {
      username   = var.server_user
      public_key = trimspace(admin_ssh_key.value)
    }
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }
}
