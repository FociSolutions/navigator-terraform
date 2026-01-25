# Virtual Network
resource "azurerm_virtual_network" "main" {
  address_space       = var.vnet_address_space
  location            = var.location
  name                = local.vnet_name
  resource_group_name = var.resource_group_name

  tags = merge(var.tags, {
    Environment = var.environment
    Name        = local.vnet_name
  })
}

# Container Apps Subnet
resource "azurerm_subnet" "container_apps" {
  address_prefixes     = [var.container_apps_subnet_address_prefix]
  name                 = local.ca_snet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name

  delegation {
    name = "container-apps-delegation"

    service_delegation {
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
      name = "Microsoft.App/environments"
    }
  }

  # Service endpoints for Container Apps subnet
  service_endpoints = ["Microsoft.Storage"]
}

# PostgreSQL Subnet
resource "azurerm_subnet" "postgresql" {
  address_prefixes     = [var.postgresql_subnet_address_prefix]
  name                 = local.db_snet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name

  delegation {
    name = "postgresql-delegation"

    service_delegation {
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
    }
  }

  # Service endpoints for PostgreSQL subnet
  service_endpoints = ["Microsoft.Storage"]
}

# Application Gateway Subnet (Future Use)
resource "azurerm_subnet" "app_gateway" {
  address_prefixes     = [var.appgw_subnet_address_prefix]
  name                 = local.agw_snet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name

  service_endpoints = ["Microsoft.Storage"]
}

# NAT Gateway for outbound connectivity (production only)
resource "azurerm_public_ip" "nat_gateway" {
  count = var.enable_zone_redundancy ? 1 : 0

  allocation_method   = "Static"
  location            = var.location
  name                = local.natgw_pip_name
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  zones               = ["1"]

  tags = merge(var.tags, {
    Environment = var.environment
    Name        = local.natgw_pip_name
  })
}

resource "azurerm_nat_gateway" "main" {
  count = var.enable_zone_redundancy ? 1 : 0

  location            = var.location
  name                = local.natgw_name
  resource_group_name = var.resource_group_name
  sku_name            = "Standard"
  zones               = ["1"]

  tags = merge(var.tags, {
    Environment = var.environment
    Name        = local.natgw_name
  })
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  count = var.enable_zone_redundancy ? 1 : 0

  nat_gateway_id       = azurerm_nat_gateway.main[0].id
  public_ip_address_id = azurerm_public_ip.nat_gateway[0].id
}

resource "azurerm_subnet_nat_gateway_association" "container_apps" {
  count = var.enable_zone_redundancy ? 1 : 0

  nat_gateway_id = azurerm_nat_gateway.main[0].id
  subnet_id      = azurerm_subnet.container_apps.id
}
