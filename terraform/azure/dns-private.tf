# Private DNS Zones and VNet Links
# T017-T018: PostgreSQL private DNS zone
#
# Private DNS zones enable name resolution for Azure services using private endpoints
# within the VNet without exposing services to the public internet.

# T017: Private DNS Zone for PostgreSQL
resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = var.resource_group_name

  tags = merge(var.tags, {
    Environment = var.environment
    Name        = "postgres-private-dns"
  })
}

# T018: Link PostgreSQL Private DNS Zone to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = local.db_vnet_link
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  resource_group_name   = var.resource_group_name
  virtual_network_id    = azurerm_virtual_network.main.id

  tags = merge(var.tags, {
    Environment = var.environment
  })
}

# ============================================================================
# Private DNS Zone for Custom Domain
# ============================================================================
#
# Purpose: Enable Application Gateway to resolve custom domain to Container Apps
# Zone Name: Custom domain (e.g., navigator-dev.demo.focisolutions.com)
# A Records: Root (@) pointing to Container Apps static IP
#
# This allows Application Gateway (in same VNet) to resolve the custom domain
# to Container Apps internal IP, preserving the Host header for Phoenix.
#
# Note: Conditional on var.domain_name being specified

# Private DNS Zone for Custom Domain
resource "azurerm_private_dns_zone" "container_apps" {
  count = var.domain_name != null ? 1 : 0

  name                = var.domain_name
  resource_group_name = var.resource_group_name

  tags = merge(var.tags, {
    Environment = var.environment
    Name        = "custom-domain-private-dns"
  })
}

# Link Custom Domain Private DNS Zone to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "container_apps" {
  count = var.domain_name != null ? 1 : 0

  name                  = "${local.name_prefix}-custom-dns-link"
  private_dns_zone_name = azurerm_private_dns_zone.container_apps[0].name
  resource_group_name   = var.resource_group_name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false

  tags = merge(var.tags, {
    Environment = var.environment
  })
}

# Root A Record (custom-domain → Container Apps static IP)
resource "azurerm_private_dns_a_record" "container_apps_root" {
  count = var.domain_name != null ? 1 : 0

  name                = "@"
  zone_name           = azurerm_private_dns_zone.container_apps[0].name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_container_app_environment.main.static_ip_address]

  tags = merge(var.tags, {
    Environment = var.environment
  })
}
