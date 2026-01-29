# Azure Container Apps
# T038-T048: Container Apps Environment, Log Analytics, Navigator Container App

# T040: Log Analytics Workspace for Container Apps logging
resource "azurerm_log_analytics_workspace" "container_apps" {
  location            = var.location
  name                = local.law_name
  resource_group_name = var.resource_group_name
  retention_in_days   = var.environment == "production" ? 90 : 30
  sku                 = "PerGB2018"

  daily_quota_gb = var.environment == "production" ? 10 : 1

  tags = merge(var.tags, {
    Environment = var.environment
    Name        = local.law_name
  })
}

# T038-T039: Container Apps Environment with VNet integration
resource "azurerm_container_app_environment" "main" {
  location                   = var.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.container_apps.id
  logs_destination           = "log-analytics"
  name                       = local.cae_name
  resource_group_name        = var.resource_group_name

  public_network_access          = "Disabled"
  internal_load_balancer_enabled = true
  infrastructure_subnet_id       = azurerm_subnet.container_apps.id
  zone_redundancy_enabled        = var.enable_zone_redundancy

  infrastructure_resource_group_name = "ME_${local.cae_name}_${var.resource_group_name}_${var.location}"
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Name        = local.cae_name
  })
}

# Container App Environment Certificate for Custom Domain
# Uploads the ACME certificate to Container Apps Environment to enable custom domain binding
resource "azurerm_container_app_environment_certificate" "main" {
  count = var.domain_name != null ? 1 : 0

  name                         = "${local.name_prefix}-cert"
  container_app_environment_id = azurerm_container_app_environment.main.id
  certificate_blob_base64      = acme_certificate.main[0].certificate_p12
  certificate_password         = random_password.certificate_p12[0].result

  tags = var.tags
}

# T041-T048: Navigator Container App
resource "azurerm_container_app" "navigator" {
  container_app_environment_id = azurerm_container_app_environment.main.id
  name                         = local.ca_name
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"

  # T047: System-assigned managed identity
  identity {
    type = "SystemAssigned"
  }

  # T042: Secrets configuration - Direct secret values from Terraform state
  # Secrets are encrypted by Azure Container Apps platform

  # PostgreSQL connection string
  secret {
    name  = "db-url"
    value = local.postgres_connection_string
  }

  # Phoenix SECRET_KEY_BASE
  secret {
    name  = "phoenix-key"
    value = random_password.phoenix_secret_key_base.result
  }

  # Google OAuth Client ID (conditional on var.google_client_id)
  dynamic "secret" {
    for_each = var.google_client_id != null ? [1] : []
    content {
      name  = "google-client-id"
      value = var.google_client_id
    }
  }

  # Google OAuth Client Secret (conditional on var.google_client_secret)
  dynamic "secret" {
    for_each = var.google_client_secret != null ? [1] : []
    content {
      name  = "google-client-secret"
      value = var.google_client_secret
    }
  }

  # Microsoft Entra ID Client ID (conditional on var.microsoft_client_id)
  dynamic "secret" {
    for_each = var.microsoft_client_id != null ? [1] : []
    content {
      name  = "microsoft-client-id"
      value = var.microsoft_client_id
    }
  }

  # Microsoft Entra ID Client Secret (conditional on var.microsoft_client_secret)
  dynamic "secret" {
    for_each = var.microsoft_client_secret != null ? [1] : []
    content {
      name  = "microsoft-client-secret"
      value = var.microsoft_client_secret
    }
  }

  # Microsoft Entra ID Tenant ID (conditional on var.microsoft_tenant_id)
  dynamic "secret" {
    for_each = var.microsoft_tenant_id != null ? [1] : []
    content {
      name  = "microsoft-tenant-id"
      value = var.microsoft_tenant_id
    }
  }

  # Azure OpenAI endpoint secret (conditional on var.create_azure_openai)
  dynamic "secret" {
    for_each = var.create_azure_openai ? [1] : []
    content {
      name  = "openai-endpoint"
      value = azurerm_cognitive_account.openai[0].endpoint
    }
  }

  # Azure OpenAI API key secret (conditional on var.create_azure_openai)
  dynamic "secret" {
    for_each = var.create_azure_openai ? [1] : []
    content {
      name  = "openai-key"
      value = azurerm_cognitive_account.openai[0].primary_access_key
    }
  }

  template {
    # T042-T043: Container resource configuration and scaling
    max_replicas = var.max_replicas
    min_replicas = var.min_replicas

    # T044: Scaling rules (dev: HTTP concurrency, production: CPU-based)
    dynamic "http_scale_rule" {
      for_each = var.environment == "dev" ? [1] : []
      content {
        concurrent_requests = 10
        name                = "http-scale-rule"
      }
    }

    dynamic "custom_scale_rule" {
      for_each = var.environment == "production" ? [1] : []
      content {
        custom_rule_type = "cpu"
        metadata = {
          type  = "Utilization"
          value = "70"
        }
        name = "cpu-scale-rule"
      }
    }

    container {
      # T041: Container image
      image = var.container_image
      name  = "navigator"

      # T042: Resource allocation
      cpu    = var.container_cpu
      memory = var.container_memory

      # T048: Environment variables with Key Vault secret references
      env {
        name        = "DATABASE_URL"
        secret_name = "db-url"
      }

      env {
        name        = "SECRET_KEY_BASE"
        secret_name = "phoenix-key"
      }

      env {
        name  = "PORT"
        value = tostring(var.container_port)
      }

      env {
        name  = "PHX_HOST"
        value = var.domain_name != null ? var.domain_name : "${local.ca_name}.${azurerm_container_app_environment.main.default_domain}"
      }

      # Google OAuth Client ID (conditional on var.google_client_id)
      dynamic "env" {
        for_each = var.google_client_id != null ? [1] : []
        content {
          name        = "GOOGLE_CLIENT_ID"
          secret_name = "google-client-id"
        }
      }

      # Google OAuth Client Secret (conditional on var.google_client_secret)
      dynamic "env" {
        for_each = var.google_client_secret != null ? [1] : []
        content {
          name        = "GOOGLE_CLIENT_SECRET"
          secret_name = "google-client-secret"
        }
      }

      # Microsoft Entra ID Client ID (conditional on var.microsoft_client_id)
      dynamic "env" {
        for_each = var.microsoft_client_id != null ? [1] : []
        content {
          name        = "MICROSOFT_CLIENT_ID"
          secret_name = "microsoft-client-id"
        }
      }

      # Microsoft Entra ID Client Secret (conditional on var.microsoft_client_secret)
      dynamic "env" {
        for_each = var.microsoft_client_secret != null ? [1] : []
        content {
          name        = "MICROSOFT_CLIENT_SECRET"
          secret_name = "microsoft-client-secret"
        }
      }

      # Microsoft Entra ID Tenant ID (conditional on var.microsoft_tenant_id)
      dynamic "env" {
        for_each = var.microsoft_tenant_id != null ? [1] : []
        content {
          name        = "MICROSOFT_TENANT_ID"
          secret_name = "microsoft-tenant-id"
        }
      }

      dynamic "env" {
        for_each = var.create_azure_openai ? [1] : []

        content {
          name        = "AZURE_OPENAI_ENDPOINT"
          secret_name = "openai-endpoint"
        }
      }

      dynamic "env" {
        for_each = var.create_azure_openai ? [1] : []

        content {
          name        = "AZURE_OPENAI_KEY"
          secret_name = "openai-key"
        }
      }

      # T045: HTTP liveness probe
      liveness_probe {
        failure_count_threshold = 3
        initial_delay           = 10
        interval_seconds        = 30
        path                    = "/"
        port                    = var.container_port
        timeout                 = 5
        transport               = "HTTP"
      }

      # Readiness probe (optional, recommended for production)
      readiness_probe {
        failure_count_threshold = 3
        initial_delay           = 0
        interval_seconds        = 10
        path                    = "/"
        port                    = var.container_port
        success_count_threshold = 1
        timeout                 = 5
        transport               = "HTTP"
      }

      # Startup probe (for slow startup)
      startup_probe {
        failure_count_threshold = 30
        initial_delay           = 0
        interval_seconds        = 10
        path                    = "/"
        port                    = var.container_port
        timeout                 = 5
        transport               = "HTTP"
      }
    }
  }

  # T045: Ingress configuration
  # T033: Internal-only - traffic routes via Application Gateway
  # Note: Custom domain binding moved to separate azurerm_container_app_custom_domain resource (azurerm 4.x requirement)
  ingress {
    allow_insecure_connections = true # Allow HTTP from Application Gateway (TLS terminated at App Gateway)
    external_enabled           = true
    target_port                = var.container_port

    # Note: custom_domain is read-only in azurerm 4.x
    # Use azurerm_container_app_custom_domain resource instead (see below)

    # IP Security Restriction: Allow all traffic (adjust for production)
    ip_security_restriction {
      action           = "Allow"
      ip_address_range = "0.0.0.0/0"
      name             = "allow-all"
    }

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Name        = local.ca_name
  })
}

# Custom Domain Binding for Container App
# Required in azurerm 4.x - inline custom_domain config removed from ingress block
# Binds the custom domain to the Container App with SNI-enabled certificate
resource "azurerm_container_app_custom_domain" "main" {
  count = var.domain_name != null ? 1 : 0

  name                                     = var.domain_name
  container_app_id                         = azurerm_container_app.navigator.id
  container_app_environment_certificate_id = azurerm_container_app_environment_certificate.main[0].id
  certificate_binding_type                 = "SniEnabled"

  depends_on = [
    azurerm_container_app_environment_certificate.main,
    azapi_resource_action.navigator_session_affinity
  ]
}

# T039b: Session affinity configuration using azapi provider
# Required for Phoenix LiveView WebSocket persistence (sticky sessions)
# NOTE: Session affinity not yet available in azurerm_container_app resource (as of v4.x)
# Uses azapi_resource_action to PATCH Container App after creation via Azure ARM REST API
resource "azapi_resource_action" "navigator_session_affinity" {
  type        = "Microsoft.App/containerApps@2024-03-01"
  resource_id = azurerm_container_app.navigator.id
  action      = "" # Empty action = direct resource update
  method      = "PATCH"

  body = {
    properties = {
      configuration = {
        ingress = {
          stickySessions = {
            affinity = "sticky"
          }
        }
      }
    }
  }

  # Only run this action on apply (not on destroy)
  when = "apply"

  depends_on = [azurerm_container_app.navigator]
}
