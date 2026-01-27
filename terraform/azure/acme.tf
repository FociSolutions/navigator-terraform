# ============================================================================
# ACME Certificate Provisioning
# ============================================================================
# Automates Let's Encrypt SSL/TLS certificate provisioning for custom domain.
# Uses DNS-01 challenge with Azure DNS for domain validation.
#
# Lifecycle:
#   - Certificate auto-renews when min_days_remaining threshold reached (30 days)
#   - ACME provider manages challenge TXT records in Azure DNS zone
#   - Certificate exported as P12 format for Application Gateway
#
# Dependencies:
#   - Azure DNS zone must exist (dns.tf)
#   - Domain NS records must point to Azure DNS nameservers
#   - ACME provider configured in provider.tf
# ============================================================================

# ----------------------------------------------------------------------------
# ACME Account
# ----------------------------------------------------------------------------
# T026-T027: ACME account private key and registration

resource "tls_private_key" "acme_account" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "acme_registration" "main" {
  account_key_pem = tls_private_key.acme_account.private_key_pem
  email_address   = var.acme_email_address
}

# ----------------------------------------------------------------------------
# Certificate Provisioning
# ----------------------------------------------------------------------------
# T028: ACME certificate with DNS-01 challenge
# Only created when domain_name is provided

resource "acme_certificate" "main" {
  count = var.domain_name != null ? 1 : 0

  account_key_pem           = acme_registration.main.account_key_pem
  certificate_p12_password  = random_password.certificate_p12[0].result
  common_name               = var.domain_name
  min_days_remaining        = 30
  subject_alternative_names = ["*.${var.domain_name}"]

  dns_challenge {
    provider = "azuredns"

    config = {
      AZURE_SUBSCRIPTION_ID = data.azurerm_client_config.current.subscription_id
      AZURE_TENANT_ID       = data.azurerm_client_config.current.tenant_id
      AZURE_RESOURCE_GROUP  = var.resource_group_name
      AZURE_ZONE_NAME       = var.domain_name
    }
  }

  depends_on = [
    azurerm_dns_zone.main
  ]
}

# ----------------------------------------------------------------------------
# Certificate P12 Password
# ----------------------------------------------------------------------------
# T029: Random password for P12 certificate export
# Required by Application Gateway SSL certificate configuration

resource "random_password" "certificate_p12" {
  count = var.domain_name != null ? 1 : 0

  length  = 32
  special = true
}
