# ==============================================================================
# Azure OpenAI Integration (Optional)
# ==============================================================================
# Purpose: Conditional Azure OpenAI Cognitive Services deployment for AI features
# Status: Optional - controlled by var.create_azure_openai
# Tasks: T055, T056
# Reference: plan.md Section "Optional Components - Azure OpenAI Integration"

# Azure OpenAI Cognitive Services Account
resource "azurerm_cognitive_account" "openai" {
  count = var.create_azure_openai ? 1 : 0

  name                = local.openai_name
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "OpenAI"

  # SKU: S0 (Standard) for all environments
  sku_name = "S0"

  # Custom subdomain for API endpoint (required for OpenAI)
  custom_subdomain_name = local.openai_name

  # Authentication: Local auth enabled (API key-based)
  local_auth_enabled = true

  # Public network access configuration
  # Dev: Public access allowed for ease of testing
  # Production: Conditional based on network_acls configuration
  public_network_access_enabled = var.environment == "dev" ? true : false

  # Network ACLs (production only - restrict to VNet)
  dynamic "network_acls" {
    for_each = var.environment == "production" ? [1] : []
    content {
      default_action = "Deny"

      # Allow access from Container Apps subnet
      virtual_network_rules {
        subnet_id = azurerm_subnet.container_apps.id
      }
    }
  }

  # Managed Identity for Azure RBAC (future enhancement)
  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Component   = "ai-services"
    Service     = "openai"
  })
}

# ==============================================================================
# Container Apps Secrets for Azure OpenAI
# ==============================================================================
# Note: Azure OpenAI endpoint and API key are stored as Container Apps secrets
# The secrets are conditionally added to Container Apps in container-apps.tf:
# - AZURE_OPENAI_ENDPOINT: azurerm_cognitive_account.openai[0].endpoint
# - AZURE_OPENAI_API_KEY: azurerm_cognitive_account.openai[0].primary_access_key
# ==============================================================================
