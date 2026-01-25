# Azure Container Registry (Optional)
# T050-T051: Conditional ACR for container images
#
# ACR is optional and controlled by var.create_acr (defaults to false)
# - Development: Use public ECR (public.ecr.aws/cds-snc/valentine:latest)
# - Production: Optional ACR for private container registry

# T050: Azure Container Registry (conditional on var.create_acr)
resource "azurerm_container_registry" "main" {
  count = var.create_acr ? 1 : 0

  location            = var.location
  name                = local.acr_name
  resource_group_name = var.resource_group_name
  sku                 = var.environment == "production" ? "Standard" : "Basic"

  admin_enabled                 = false # Use managed identity authentication
  public_network_access_enabled = var.environment == "production" ? false : true

  # Geo-replication (not needed for single-region deployment)
  # georeplications = []

  # Note: retention_policy_in_days is only supported on Premium SKU
  # Since we use Basic (dev) or Standard (production), we cannot use retention policies

  tags = merge(var.tags, {
    Environment = var.environment
    Name        = local.acr_name
  })
}

# T051: Grant Container App managed identity AcrPull role (conditional on var.create_acr)
# This is defined in identity.tf as it's an RBAC assignment
