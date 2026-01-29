provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }

    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}

provider "acme" {
  server_url = var.acme_server_url
}

# Azure client configuration data source
# Used by ACME provider for explicit DNS zone authentication
data "azurerm_client_config" "current" {}
