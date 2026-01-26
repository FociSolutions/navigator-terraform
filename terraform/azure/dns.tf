# Azure DNS Configuration for Custom Domain
# T051-T054: DNS zone, A record, custom domain binding with managed certificate
# Conditional on var.domain_name being specified

# T051: Azure DNS zone for custom domain (apex domain)
# When domain_name is null/unspecified, DNS resources are not created (use Container Apps default domain)
# Note: After deployment, update domain registrar NS records to point to Azure DNS name servers
#       (from dns_zone_name_servers output in outputs.tf)
resource "azurerm_dns_zone" "main" {
  count = var.domain_name != null ? 1 : 0

  name                = var.domain_name
  resource_group_name = var.resource_group_name

  tags = merge(var.tags, {
    Environment = var.environment
    Name        = var.domain_name
  })
}

# T034: A record pointing to Application Gateway public IP address
# For apex domains (e.g., navigator-dev.demo.focisolutions.com), use A record with Application Gateway public IP
# Azure DNS routes custom domain traffic to Application Gateway (reverse proxy for internal Container Apps)
resource "azurerm_dns_a_record" "container_app" {
  count = var.domain_name != null ? 1 : 0

  name                = "@" # Root domain (e.g., navigator-dev.demo.focisolutions.com)
  zone_name           = azurerm_dns_zone.main[0].name
  resource_group_name = var.resource_group_name
  ttl                 = 300

  # T034: Point to Application Gateway public IP address (changed from Container Apps static IP)
  records = [azurerm_public_ip.appgw.ip_address]

  tags = merge(var.tags, {
    Environment = var.environment
    Name        = "app-gateway-a-record"
  })
}

# ============================================================================
# Removed Resources (T035-T039)
# ============================================================================
# The following resources have been removed as Application Gateway now handles
# SSL/TLS termination using ACME certificates (acme.tf):
#
# - azurerm_dns_txt_record.verification (T035)
#   Replaced by: ACME DNS-01 challenge TXT records (auto-managed)
#
# - azurerm_container_app_custom_domain.main (T036)
#   No longer needed: Application Gateway routes to internal Container Apps FQDN
#
# - azapi_resource.managed_certificate (T037)
#   Replaced by: ACME certificate provisioning (acme.tf)
#
# - azapi_resource_action.bind_certificate (T038)
#   No longer needed: Certificate bound to Application Gateway, not Container Apps
#
# - azapi_resource_action.unbind_certificate (T039)
#   No longer needed: No custom domain binding on Container Apps
# ============================================================================
