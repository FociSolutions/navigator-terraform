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

# T052: A record pointing to Container Apps Environment static IP address
# For apex domains (e.g., navigator-dev.demo.focisolutions.com), use A record with Container Apps Environment static IP
# Azure DNS routes custom domain traffic to Container Apps Environment
resource "azurerm_dns_a_record" "container_app" {
  count = var.domain_name != null ? 1 : 0

  name                = "@" # Root domain (e.g., navigator-dev.demo.focisolutions.com)
  zone_name           = azurerm_dns_zone.main[0].name
  resource_group_name = var.resource_group_name
  ttl                 = 300

  # Point to Container Apps Environment static IP address
  # Container Apps Environment provides a dedicated static IP for external ingress
  records = [azurerm_container_app_environment.main.static_ip_address]

  tags = merge(var.tags, {
    Environment = var.environment
    Name        = "container-app-a-record"
  })
}

# Domain verification TXT record for Container Apps custom domain
# Required for Azure to verify domain ownership before binding
# The asuid prefix is required by Azure, but trimmed from the custom domain name property
resource "azurerm_dns_txt_record" "verification" {
  count = var.domain_name != null ? 1 : 0

  name                = "asuid" # Domain verification prefix required by Azure
  zone_name           = azurerm_dns_zone.main[0].name
  resource_group_name = var.resource_group_name
  ttl                 = 300

  record {
    value = azurerm_container_app.navigator.custom_domain_verification_id
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Name        = "domain-verification"
  })
}

# T053: Add custom domain to Container App (STEP 1: Initial binding without certificate)
# This satisfies Azure's requirement that the domain must be bound to the container app
# before a managed certificate can be created for it
# See: https://github.com/hashicorp/terraform-provider-azurerm/issues/21866#issuecomment-2455147510
resource "azurerm_container_app_custom_domain" "main" {
  count = var.domain_name != null ? 1 : 0

  name             = var.domain_name
  container_app_id = azurerm_container_app.navigator.id

  # DNS records must exist for domain verification before binding
  depends_on = [
    azurerm_dns_a_record.container_app,
    azurerm_dns_txt_record.verification
  ]

  # Azure will populate certificate fields asynchronously, ignore changes to prevent resource recreation
  lifecycle {
    ignore_changes = [
      certificate_binding_type,
      container_app_environment_certificate_id,
    ]
  }
}

# T054: Create Azure Managed Certificate (STEP 2: Certificate creation)
# Now that the custom domain is bound to the container app, Azure allows certificate creation
# This resource creates a free managed certificate with automatic renewal by Azure
resource "azapi_resource" "managed_certificate" {
  count = var.domain_name != null ? 1 : 0

  type      = "Microsoft.App/managedEnvironments/managedCertificates@2024-03-01"
  name      = replace(var.domain_name, ".", "-") # Certificate name: dots replaced with hyphens
  parent_id = azurerm_container_app_environment.main.id
  location  = var.location

  body = {
    properties = {
      subjectName             = var.domain_name
      domainControlValidation = "HTTP" # HTTP validation for apex domains with A records
    }
  }

  # CRITICAL: Custom domain must be added to container app FIRST
  # Otherwise Azure returns: RequireCustomHostnameInEnvironment error
  depends_on = [
    azurerm_container_app_custom_domain.main
  ]

  response_export_values = ["*"]

  timeouts {
    create = "20m" # Certificate provisioning can take 10-15 minutes
    delete = "10m"
  }
}

# T055: Bind managed certificate to custom domain (STEP 3: Certificate binding on apply)
# Uses azapi_resource_action to PATCH the container app's ingress configuration
# This updates the existing custom domain binding to use the managed certificate
resource "azapi_resource_action" "bind_certificate" {
  count = var.domain_name != null ? 1 : 0

  resource_id = azurerm_container_app.navigator.id
  type        = "Microsoft.App/containerApps@2024-03-01"
  method      = "PATCH"
  when        = "apply" # Execute during terraform apply

  body = {
    properties = {
      configuration = {
        ingress = {
          customDomains = [
            {
              bindingType   = "SniEnabled"
              name          = var.domain_name
              certificateId = azapi_resource.managed_certificate[0].output.id
            }
          ]
        }
      }
    }
  }
}

# T056: Unbind custom domain on destroy (STEP 4: Cleanup on terraform destroy)
# Removes custom domain binding before deleting the certificate
# This prevents deletion errors when tearing down infrastructure
resource "azapi_resource_action" "unbind_certificate" {
  count = var.domain_name != null ? 1 : 0

  resource_id = azurerm_container_app.navigator.id
  type        = "Microsoft.App/containerApps@2024-03-01"
  method      = "PATCH"
  when        = "destroy" # Execute during terraform destroy

  body = {
    properties = {
      configuration = {
        ingress = {
          customDomains = []
        }
      }
    }
  }
}
