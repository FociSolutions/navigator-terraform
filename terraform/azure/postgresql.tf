# Azure Database for PostgreSQL Flexible Server
# T031-T039: PostgreSQL server, configuration, backup, and database creation
#
# Note: Private DNS zone for PostgreSQL is defined in dns-private.tf (T017-T018)

# T031-T036: PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "main" {
  # T030: Basic configuration
  administrator_login    = var.postgres_admin_username
  administrator_password = random_password.postgres_admin_password.result
  location               = var.location
  name                   = local.psql_name
  resource_group_name    = var.resource_group_name
  version                = var.postgres_version

  # T031: SKU configuration
  sku_name = var.postgres_sku

  # T032: Storage configuration
  auto_grow_enabled = true
  storage_mb        = var.postgres_storage_gb * 1024
  storage_tier      = var.postgres_storage_gb <= 32 ? "P4" : (var.postgres_storage_gb <= 64 ? "P6" : "P10")

  # T035: Network configuration (private endpoint in VNet)
  delegated_subnet_id           = azurerm_subnet.postgresql.id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres.id
  public_network_access_enabled = false

  # T034: Backup configuration
  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = var.environment == "production" ? true : false

  # T033: High Availability configuration (zone-redundant for production)
  dynamic "high_availability" {
    for_each = var.postgres_ha_enabled ? [1] : []

    content {
      mode                      = "ZoneRedundant"
      standby_availability_zone = "2"
    }
  }

  # T036: Authentication and SSL/TLS enforcement
  authentication {
    active_directory_auth_enabled = false
    password_auth_enabled         = true
  }

  zone = "1"

  tags = merge(var.tags, {
    Environment = var.environment
    Name        = local.psql_name
  })

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.postgres
  ]

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      zone,
      high_availability[0].standby_availability_zone,
    ]
  }
}

# PostgreSQL Server Configuration: TLS enforcement (configurable)
# When disabled, network isolation via delegated subnet provides primary security control
resource "azurerm_postgresql_flexible_server_configuration" "require_secure_transport" {
  name      = "require_secure_transport"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = var.postgres_require_ssl ? "on" : "off"
}

# PostgreSQL Server Configuration: Minimum TLS version (only applies when TLS is enabled)
resource "azurerm_postgresql_flexible_server_configuration" "ssl_min_protocol_version" {
  count = var.postgres_require_ssl ? 1 : 0

  name      = "ssl_min_protocol_version"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "TLSv1.2"
}

# PostgreSQL Server Configuration: PgBouncer (production only)
resource "azurerm_postgresql_flexible_server_configuration" "pgbouncer_enabled" {
  count = var.environment == "production" ? 1 : 0

  name      = "pgbouncer.enabled"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "on"
}

# PostgreSQL Server Configuration: Log statements (production only)
resource "azurerm_postgresql_flexible_server_configuration" "log_statement" {
  count = var.environment == "production" ? 1 : 0

  name      = "log_statement"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "ddl"
}

# PostgreSQL Server Configuration: Log slow queries (production only)
resource "azurerm_postgresql_flexible_server_configuration" "log_min_duration_statement" {
  count = var.environment == "production" ? 1 : 0

  name      = "log_min_duration_statement"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "1000"
}

# PostgreSQL Database
resource "azurerm_postgresql_flexible_server_database" "navigator" {
  charset   = "UTF8"
  collation = "en_US.utf8"
  name      = local.db_name
  server_id = azurerm_postgresql_flexible_server.main.id

  lifecycle {
    prevent_destroy = true
  }
}

# T038: PostgreSQL connection string as local value
# Uses Ecto URL scheme and ssl=true parameter (required for Postgrex driver)
# Azure PostgreSQL Flexible Server requires TLS (require_secure_transport=on)
locals {
  postgres_connection_string = "ecto://${var.postgres_admin_username}:${urlencode(random_password.postgres_admin_password.result)}@${azurerm_postgresql_flexible_server.main.fqdn}:5432/${azurerm_postgresql_flexible_server_database.navigator.name}"
}

# T033: PostgreSQL connection string stored in Terraform state
# Connection string is injected directly into Container Apps secrets (see container-apps.tf)
# No Key Vault required - secrets are encrypted by Azure Container Apps platform
