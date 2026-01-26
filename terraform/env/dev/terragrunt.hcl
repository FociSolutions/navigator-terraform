# Terragrunt configuration for dev environment
terraform {
  source = "${get_repo_root()}//terraform/azure"
}

# Remote state configuration
remote_state {
  backend = "azurerm"

  config = {
    resource_group_name  = "navigator-tfstate-rg"
    storage_account_name = "navtfstatedev"
    container_name       = "tfstate"
    key                  = "navigator.terraform.tfstate"
    use_azuread_auth     = true
  }
}

# Development environment inputs
inputs = {
  # Environment Configuration
  environment         = "dev"
  location            = "canadacentral"
  resource_group_name = "navigator-dev-rg"

  # Container Apps Configuration (minimal for dev)
  container_cpu    = 0.5
  container_memory = "1Gi"
  min_replicas     = 0  # Scale to zero for cost savings
  max_replicas     = 2

  # PostgreSQL Configuration (Burstable tier for dev)
  postgres_sku          = "B_Standard_B1ms"
  postgres_storage_gb   = 32
  postgres_ha_enabled   = false
  backup_retention_days = 7
  postgres_require_ssl  = false  # TLS optional for dev (network isolation provides security)

  # Storage Configuration
  create_storage_account = false
  storage_account_sku    = "Standard_LRS"

  # DNS Configuration
  domain_name = "navigator-dev.demo.focisolutions.com"

  # Application Gateway Configuration
  appgw_sku_name     = "Standard_v2"
  appgw_tier         = "Standard_v2"
  appgw_capacity_min = 1
  appgw_capacity_max = 2
  enable_waf         = false  # WAF requires WAF_v2 tier (additional cost)
  # waf_mode         = "Prevention"  # Only used if enable_waf = true

  # ACME Certificate Configuration (Let's Encrypt)
  acme_server_url    = "https://acme-staging-v02.api.letsencrypt.org/directory"  # Staging for dev
  acme_email_address = get_env("ACME_EMAIL_ADDRESS")

  # Feature Flags
  enable_http_redirect = true  # Redirect HTTP → HTTPS

  # Monitoring (disabled for dev to reduce costs)
  enable_application_insights = false

  # Cost Optimization
  enable_auto_shutdown   = true
  enable_zone_redundancy = false

  # Azure OpenAI (optional)
  create_azure_openai = true

  # Network Security
  enable_outbound_internet = true

  # Authentication (Optional - uncomment as needed)
  # Set environment variables before deployment:
  # export GOOGLE_CLIENT_ID="..." GOOGLE_CLIENT_SECRET="..."
  # export MICROSOFT_CLIENT_ID="..." MICROSOFT_CLIENT_SECRET="..." MICROSOFT_TENANT_ID="..."
  google_client_id         = get_env("GOOGLE_CLIENT_ID")
  google_client_secret     = get_env("GOOGLE_CLIENT_SECRET")
  # microsoft_client_id      = get_env("MICROSOFT_CLIENT_ID")
  # microsoft_client_secret  = get_env("MICROSOFT_CLIENT_SECRET")
  # microsoft_tenant_id      = get_env("MICROSOFT_TENANT_ID")

  # Tags
  tags = {
    Environment = "dev"
    Project     = "valentine"
    ManagedBy   = "terraform"
    CostCenter  = "navigator"
  }
}
