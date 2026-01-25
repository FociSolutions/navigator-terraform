# Azure Storage Account (Optional)
# T050-T054: Storage Account for user uploads (conditional on var.create_storage_account)

# T050-T051: Storage Account
resource "azurerm_storage_account" "uploads" {
  count = var.create_storage_account ? 1 : 0

  account_replication_type = var.storage_account_sku
  account_tier             = "Standard"
  location                 = var.location
  name                     = local.st_name
  resource_group_name      = var.resource_group_name

  access_tier                   = "Hot"
  https_traffic_only_enabled    = true
  min_tls_version               = "TLS1_2"
  public_network_access_enabled = var.environment == "production" ? false : true

  blob_properties {
    # T053: Lifecycle management policy
    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  network_rules {
    bypass                     = ["AzureServices"]
    default_action             = var.environment == "production" ? "Deny" : "Allow"
    virtual_network_subnet_ids = var.environment == "production" ? [] : [azurerm_subnet.container_apps.id]
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Name        = local.st_name
  })
}

# T052: Blob container for user uploads
resource "azurerm_storage_container" "user_uploads" {
  count = var.create_storage_account ? 1 : 0

  name                  = "user-uploads"
  storage_account_id    = azurerm_storage_account.uploads[0].id
  container_access_type = "private"
}

# T053: Storage lifecycle management
resource "azurerm_storage_management_policy" "lifecycle" {
  count = var.create_storage_account ? 1 : 0

  storage_account_id = azurerm_storage_account.uploads[0].id

  rule {
    enabled = true
    name    = "move-to-cool-tier"

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = 90
      }
    }

    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["user-uploads/"]
    }
  }

  rule {
    enabled = true
    name    = "move-to-archive-tier"

    actions {
      base_blob {
        tier_to_archive_after_days_since_modification_greater_than = 180
      }
    }

    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["user-uploads/"]
    }
  }
}

# T055: Storage private endpoint (conditional on var.create_storage_account && var.environment == "production")
resource "azurerm_private_endpoint" "storage_blob" {
  count = var.create_storage_account && var.environment == "production" ? 1 : 0

  location            = var.location
  name                = local.st_pe_name
  resource_group_name = var.resource_group_name
  subnet_id           = azurerm_subnet.container_apps.id

  private_service_connection {
    is_manual_connection           = false
    name                           = local.st_psc_name
    private_connection_resource_id = azurerm_storage_account.uploads[0].id
    subresource_names              = ["blob"]
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Name        = local.st_pe_name
  })
}
