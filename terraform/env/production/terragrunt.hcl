# Terragrunt configuration for production environment
terraform {
  source = "${get_repo_root()}//terraform/azure"
}

# Remote state configuration
remote_state {
  backend = "azurerm"

  config = {
    resource_group_name  = "navigator-tfstate-rg"
    storage_account_name = "navtfstateprod"
    container_name       = "tfstate"
    key                  = "navigator.terraform.tfstate"
    use_azuread_auth     = true
  }
}

# Production environment inputs
inputs = {
  # Environment Configuration
  environment         = "production"
  location            = "canadacentral"
  resource_group_name = "navigator-prod-rg"

  # Container Apps Configuration (production sizing)
  container_cpu    = 0.5
  container_memory = "1.0Gi"
  min_replicas     = 1  # Always keep 1 instance running
  max_replicas     = 10

  # PostgreSQL Configuration (General Purpose tier with HA)
  postgres_sku          = "GP_Standard_D2s_v3"
  postgres_storage_gb   = 128
  postgres_ha_enabled   = true  # Zone-redundant HA
  backup_retention_days = 14
  postgres_require_ssl  = false  # TLS optional (can be enabled for defense-in-depth)

  # Storage Configuration
  create_storage_account = false
  storage_account_sku    = "Standard_ZRS"  # Zone-redundant storage

  # DNS Configuration
  domain_name = "navigator.demo.focisolutions.com"

  # Application Gateway Configuration
  appgw_sku_name     = "WAF_v2"       # WAF_v2 for production (includes Web Application Firewall)
  appgw_tier         = "WAF_v2"
  appgw_capacity_min = 2              # Higher minimum for production availability
  appgw_capacity_max = 10
  enable_waf         = true           # Enable WAF for production security
  waf_mode           = "Prevention"   # Block malicious requests (use "Detection" for testing)

  # ACME Certificate Configuration (Let's Encrypt)
  acme_server_url    = "https://acme-v02.api.letsencrypt.org/directory"  # Production endpoint
  acme_email_address = get_env("ACME_EMAIL_ADDRESS")

  # Feature Flags
  enable_http_redirect = true  # Redirect HTTP → HTTPS

  # High Availability
  enable_zone_redundancy = true

  # Azure OpenAI (optional)
  #TODO: Only creates the OpenAI instance, not the model deployment
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
    Environment = "production"
    Project     = "valentine"
    ManagedBy   = "terraform"
    CostCenter  = "navigator"
  }
}
