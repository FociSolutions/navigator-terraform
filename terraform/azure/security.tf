# ============================================================================
# Container Apps Network Security Group
# ============================================================================
#
# Security Justification:
# - Inbound HTTPS (443): Public web application access (Trivy AVD-AZU-0047 suppressed)
# - Outbound to Azure services: Azure Monitor (telemetry) and Container Registry
# - Outbound to PostgreSQL subnet: Database connectivity
# - Outbound to internet: OpenAI API access when enabled (Trivy AVD-AZU-0051 suppressed)
#
# Service Tag Maintenance:
# - Regional tags require suffix: ServiceName.RegionName (e.g., AzureContainerRegistry.CanadaCentral)
# - List available tags: az network list-service-tags --location canadacentral
# - Update locals.azure_service_tags when adding new Azure services
# ============================================================================

# Azure service tags for outbound connectivity (service tags are free, only data transfer costs apply)
locals {
  # Azure service tags for Container Apps outbound connectivity
  azure_service_tags = {
    "AzureMonitor"                         = 110 # Application Insights and monitoring (global tag)
    "AzureContainerRegistry.CanadaCentral" = 111 # Container registry (for future ACR migration from public ECR)
  }
}

resource "azurerm_network_security_group" "container_apps" {
  location            = var.location
  name                = local.ca_nsg_name
  resource_group_name = var.resource_group_name

  tags = merge(var.tags, {
    Environment = var.environment
    Name        = local.ca_nsg_name
  })
}

# Container Apps NSG Rules - Inbound
# NEW: Allow HTTPS from Application Gateway subnet
resource "azurerm_network_security_rule" "container_apps_inbound_appgw_https" {
  access                      = "Allow"
  destination_address_prefix  = var.container_apps_subnet_address_prefix
  destination_port_range      = "443"
  direction                   = "Inbound"
  name                        = "AllowAppGatewayHttps"
  network_security_group_name = azurerm_network_security_group.container_apps.name
  priority                    = 100
  protocol                    = "Tcp"
  resource_group_name         = var.resource_group_name
  source_address_prefix       = var.appgw_subnet_address_prefix
  source_port_range           = "*"
}

# trivy:ignore:AVD-AZU-0047 Public web application requires unrestricted HTTPS inbound access
resource "azurerm_network_security_rule" "container_apps_inbound_https" {
  access                      = "Allow"
  destination_address_prefix  = "*"
  destination_port_range      = "443"
  direction                   = "Inbound"
  name                        = "AllowHttpsInbound"
  network_security_group_name = azurerm_network_security_group.container_apps.name
  priority                    = 110
  protocol                    = "Tcp"
  resource_group_name         = var.resource_group_name
  source_address_prefix       = "*"
  source_port_range           = "*"
}

# Container Apps NSG Rules - Outbound
resource "azurerm_network_security_rule" "container_apps_outbound_postgresql" {
  access                      = "Allow"
  destination_address_prefix  = var.postgresql_subnet_address_prefix
  destination_port_range      = "5432"
  direction                   = "Outbound"
  name                        = "AllowPostgreSQLOutbound"
  network_security_group_name = azurerm_network_security_group.container_apps.name
  priority                    = 100
  protocol                    = "Tcp"
  resource_group_name         = var.resource_group_name
  source_address_prefix       = "*"
  source_port_range           = "*"
}

# Outbound rules for Azure services (use destination_address_prefix singular, not plural)
resource "azurerm_network_security_rule" "container_apps_outbound_azure_services" {
  for_each = local.azure_service_tags

  access                      = "Allow"
  destination_address_prefix  = each.key
  destination_port_range      = "443"
  direction                   = "Outbound"
  name                        = "Allow${replace(each.key, ".", "")}Outbound"
  network_security_group_name = azurerm_network_security_group.container_apps.name
  priority                    = each.value
  protocol                    = "Tcp"
  resource_group_name         = var.resource_group_name
  source_address_prefix       = "VirtualNetwork"
  source_port_range           = "*"
}

# Conditional internet outbound for OpenAI API (external endpoint)
# trivy:ignore:AVD-AZU-0051 Outbound internet required for OpenAI API integration (conditional via variable)
resource "azurerm_network_security_rule" "container_apps_outbound_internet" {
  count = var.enable_outbound_internet ? 1 : 0

  access                      = "Allow"
  destination_address_prefix  = "Internet"
  destination_port_range      = "443"
  direction                   = "Outbound"
  name                        = "AllowInternetOutbound"
  network_security_group_name = azurerm_network_security_group.container_apps.name
  priority                    = 120
  protocol                    = "Tcp"
  resource_group_name         = var.resource_group_name
  source_address_prefix       = "*"
  source_port_range           = "*"
}

# PostgreSQL Network Security Group
resource "azurerm_network_security_group" "postgresql" {
  location            = var.location
  name                = local.db_nsg_name
  resource_group_name = var.resource_group_name

  tags = merge(var.tags, {
    Environment = var.environment
    Name        = local.db_nsg_name
  })
}

# PostgreSQL NSG Rules - Inbound
resource "azurerm_network_security_rule" "postgresql_inbound_from_container_apps" {
  access                      = "Allow"
  destination_address_prefix  = "*"
  destination_port_range      = "5432"
  direction                   = "Inbound"
  name                        = "AllowPostgreSQLFromContainerApps"
  network_security_group_name = azurerm_network_security_group.postgresql.name
  priority                    = 100
  protocol                    = "Tcp"
  resource_group_name         = var.resource_group_name
  source_address_prefix       = var.container_apps_subnet_address_prefix
  source_port_range           = "*"
}

# PostgreSQL NSG Rules - Deny all other inbound
resource "azurerm_network_security_rule" "postgresql_deny_inbound" {
  access                      = "Deny"
  destination_address_prefix  = "*"
  destination_port_range      = "*"
  direction                   = "Inbound"
  name                        = "DenyAllInbound"
  network_security_group_name = azurerm_network_security_group.postgresql.name
  priority                    = 4096
  protocol                    = "*"
  resource_group_name         = var.resource_group_name
  source_address_prefix       = "*"
  source_port_range           = "*"
}

# PostgreSQL NSG Rules - Deny all outbound
resource "azurerm_network_security_rule" "postgresql_deny_outbound" {
  access                      = "Deny"
  destination_address_prefix  = "*"
  destination_port_range      = "*"
  direction                   = "Outbound"
  name                        = "DenyAllOutbound"
  network_security_group_name = azurerm_network_security_group.postgresql.name
  priority                    = 4096
  protocol                    = "*"
  resource_group_name         = var.resource_group_name
  source_address_prefix       = "*"
  source_port_range           = "*"
}

# NSG Association - Container Apps Subnet
resource "azurerm_subnet_network_security_group_association" "container_apps" {
  network_security_group_id = azurerm_network_security_group.container_apps.id
  subnet_id                 = azurerm_subnet.container_apps.id
}

# NSG Association - PostgreSQL Subnet
resource "azurerm_subnet_network_security_group_association" "postgresql" {
  network_security_group_id = azurerm_network_security_group.postgresql.id
  subnet_id                 = azurerm_subnet.postgresql.id
}
