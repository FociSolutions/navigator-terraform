# Container Apps Outputs
output "container_apps_environment_id" {
  description = "ID of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.id
}

output "container_apps_fqdn" {
  description = "FQDN of the Navigator Container App (internal-only, accessible via Application Gateway)"
  value       = azurerm_container_app.navigator.ingress[0].fqdn
}

output "container_apps_url" {
  description = "Full HTTPS URL of the Navigator application (internal-only, accessible via Application Gateway)"
  value       = "https://${azurerm_container_app.navigator.ingress[0].fqdn}"
}

# T044: Container Apps Private DNS outputs
output "private_dns_zone_name" {
  description = "Name of the Private DNS zone for custom domain resolution"
  value       = var.domain_name != null ? azurerm_private_dns_zone.container_apps[0].name : ""
}

output "container_apps_internal_fqdn" {
  description = "Internal FQDN for Container Apps (resolved via Private DNS)"
  value       = azurerm_container_app_environment.main.default_domain
}

# T042: Application Gateway outputs
output "appgw_public_ip" {
  description = "Public IP address of the Application Gateway"
  value       = azurerm_public_ip.appgw.ip_address
}

output "appgw_fqdn" {
  description = "FQDN of the Application Gateway public IP (if configured)"
  value       = azurerm_public_ip.appgw.fqdn != null ? azurerm_public_ip.appgw.fqdn : ""
}

# T043: ACME Certificate outputs
output "certificate_expiry" {
  description = "Expiry date of the ACME certificate (empty if domain_name not configured)"
  value       = var.domain_name != null ? acme_certificate.main[0].certificate_not_after : ""
  sensitive   = false
}

# PostgreSQL Outputs
output "postgresql_fqdn" {
  description = "Fully qualified domain name of the PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.main.fqdn
  sensitive   = true
}

output "postgresql_server_id" {
  description = "ID of the PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.main.id
}

# DNS Outputs (conditional on var.domain_name)
output "dns_zone_name" {
  description = "Name of the Azure DNS zone (for manual NS record configuration at domain registrar)"
  value       = var.domain_name != null ? azurerm_dns_zone.main[0].name : ""
}

output "dns_zone_nameservers" {
  description = "Name servers for the DNS zone (update these at your domain registrar to delegate DNS to Azure)"
  value       = var.domain_name != null ? azurerm_dns_zone.main[0].name_servers : []
}

output "custom_domain_url" {
  description = "Custom domain URL (if domain_name is configured)"
  value       = var.domain_name != null ? "https://${var.domain_name}" : ""
}

# Network Outputs
output "vnet_id" {
  description = "ID of the Virtual Network"
  value       = azurerm_virtual_network.main.id
}

output "container_apps_subnet_id" {
  description = "ID of the Container Apps subnet"
  value       = azurerm_subnet.container_apps.id
}

output "postgresql_subnet_id" {
  description = "ID of the PostgreSQL subnet"
  value       = azurerm_subnet.postgresql.id
}

# Managed Identity Outputs
output "container_app_identity_principal_id" {
  description = "Principal ID of the Container App managed identity"
  value       = azurerm_container_app.navigator.identity[0].principal_id
}

# Monitoring Outputs
output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace for Container Apps logging and monitoring"
  value       = azurerm_log_analytics_workspace.container_apps.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.container_apps.name
}

# Storage Account Outputs (if created)
output "storage_account_name" {
  description = "Name of the Storage Account (empty if storage account not created)"
  value       = var.create_storage_account ? azurerm_storage_account.uploads[0].name : ""
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint for the Storage Account (empty if storage account not created)"
  value       = var.create_storage_account ? azurerm_storage_account.uploads[0].primary_blob_endpoint : ""
}
