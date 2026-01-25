# Managed Identities and RBAC Configuration
#
# This file contains:
# - System-assigned and user-assigned managed identities
# - RBAC role assignments for resource access
# - Service principal configurations for CI/CD
#
# Note: System-assigned identities for specific resources (e.g., Container Apps)
# are defined in their respective resource files and referenced here for RBAC.

# RBAC Role Assignments
#
# Phase 3: Compute & Data Tier
# - Container Apps managed identity → AcrPull role (conditional on var.create_acr)

# T044: Container Apps managed identity → AcrPull role (conditional on var.create_acr)
resource "azurerm_role_assignment" "container_app_acr_pull" {
  count = var.create_acr ? 1 : 0

  principal_id         = azurerm_container_app.navigator.identity[0].principal_id
  role_definition_name = "AcrPull"
  scope                = azurerm_container_registry.main[0].id
}
