# One subnet per interface: Azure forbids two interfaces of one engine in the
# same subnet.

locals {
  # The engine's addresses are pinned at host 10 of each CIDR, so a static
  # SMC interface configuration keeps working. cidrhost() needs a prefix of
  # at most /28 for host 10, so the CIDRs must be /28 or larger.
  subnets = {
    management = { cidr = var.management_cidr, engine_ip = cidrhost(var.management_cidr, 10) }
    lan        = { cidr = var.lan_cidr, engine_ip = cidrhost(var.lan_cidr, 10) }
    wan        = { cidr = var.wan_cidr, engine_ip = cidrhost(var.wan_cidr, 10) }
  }

  # The protected test server, in the LAN subnet.
  server_ip = cidrhost(var.lan_cidr, 120)

  # More specific than the default route, so this traffic bypasses the
  # engine.
  lan_bypass_routes = concat(
    [for i, cidr in var.control_bypass_cidrs : {
      name           = "bypass-${i}"
      address_prefix = cidr
      next_hop_type  = "Internet"
    }],
    var.enable_bastion ? [{
      name           = "to-bastion"
      address_prefix = var.bastion_subnet_cidr
      next_hop_type  = "VnetLocal"
    }] : []
  )
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "this" {
  name                = "${var.name}-vnet"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = [var.vnet_cidr]
}

resource "azurerm_subnet" "this" {
  for_each = local.subnets

  name                 = "${var.name}-${each.key}"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.cidr]
}

# Azure requires this exact subnet name.
resource "azurerm_subnet" "bastion" {
  count                = var.enable_bastion ? 1 : 0
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.bastion_subnet_cidr]
}

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

  # Own virtual network included, so engines in it reach each other.
  security_rule {
    name                       = "allow-vnet"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.vnet_cidr
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

resource "azurerm_network_security_group" "wan" {
  name                = "${var.name}-allow-wan"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "allow-admins-and-peers"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = var.allowed_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-vnet"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.vnet_cidr
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

resource "azurerm_network_security_group" "lan" {
  name                = "${var.name}-allow-lan"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "allow-lan"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.lan_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-ssh-to-server"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.allowed_cidrs
    destination_address_prefix = "*"
  }

  dynamic "security_rule" {
    for_each = var.enable_bastion ? [1] : []

    content {
      name                       = "allow-bastion-ssh"
      priority                   = 1002
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefix      = var.bastion_subnet_cidr
      destination_address_prefix = "*"
    }
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
  subnet_id                 = azurerm_subnet.this["management"].id
  network_security_group_id = azurerm_network_security_group.management.id
}

resource "azurerm_subnet_network_security_group_association" "wan" {
  subnet_id                 = azurerm_subnet.this["wan"].id
  network_security_group_id = azurerm_network_security_group.wan.id
}

resource "azurerm_subnet_network_security_group_association" "lan" {
  subnet_id                 = azurerm_subnet.this["lan"].id
  network_security_group_id = azurerm_network_security_group.lan.id
}

# Attached to the LAN subnet only, so the engine's own traffic does not loop
# through itself.
resource "azurerm_route_table" "lan" {
  name                = "${var.name}-lan-rt"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  route {
    name                   = "default-via-engine"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.subnets.lan.engine_ip
  }

  dynamic "route" {
    for_each = local.lan_bypass_routes

    content {
      name           = route.value.name
      address_prefix = route.value.address_prefix
      next_hop_type  = route.value.next_hop_type
    }
  }
}

resource "azurerm_subnet_route_table_association" "lan" {
  subnet_id      = azurerm_subnet.this["lan"].id
  route_table_id = azurerm_route_table.lan.id
}

# Standard SKU, for the native client.
resource "azurerm_public_ip" "bastion" {
  count               = var.enable_bastion ? 1 : 0
  name                = "${var.name}-bastion-pip"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_bastion_host" "this" {
  count               = var.enable_bastion ? 1 : 0
  name                = "${var.name}-bastion"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "Standard"

  tunneling_enabled = true

  ip_configuration {
    name                 = "bastion"
    subnet_id            = azurerm_subnet.bastion[0].id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }
}

module "engine" {
  source = "github.com/Forcepoint/terraform-fpnsp-modules//modules/azure-engine"

  name                = var.name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  size                = var.size

  source_image = {
    sku     = var.engine_image_sku
    version = var.engine_image_version
  }

  network_interfaces = [
    {
      ip_configuration = [
        {
          subnet_id                     = azurerm_subnet.this["management"].id
          private_ip_address_allocation = "Static"
          private_ip_address            = local.subnets.management.engine_ip
          public_ip                     = {}
        },
      ]
    },
    {
      ip_configuration = [
        {
          subnet_id                     = azurerm_subnet.this["lan"].id
          private_ip_address_allocation = "Static"
          private_ip_address            = local.subnets.lan.engine_ip
        },
      ]
    },
    {
      ip_configuration = [
        {
          subnet_id                     = azurerm_subnet.this["wan"].id
          private_ip_address_allocation = "Static"
          private_ip_address            = local.subnets.wan.engine_ip
          public_ip                     = {}
        },
      ]
    },
  ]

  admin_username  = var.admin_username
  ssh_public_keys = var.ssh_public_keys

  initial_contact = var.initial_contact
}

# A workload to verify the route end to end.
resource "azurerm_public_ip" "server" {
  name                = "${var.name}-server-pip"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "server" {
  name                = "${var.name}-server"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "ip-server"
    subnet_id                     = azurerm_subnet.this["lan"].id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.server_ip
    public_ip_address_id          = azurerm_public_ip.server.id
  }
}

resource "azurerm_linux_virtual_machine" "server" {
  name                = "${var.name}-server"
  admin_username      = var.server_user
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  size                = var.server_machine_type

  network_interface_ids = [
    azurerm_network_interface.server.id,
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
