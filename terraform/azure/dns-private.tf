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
