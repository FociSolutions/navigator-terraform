# Secrets Management
# T024-T025: Random password generation for auto-generated secrets
#
# Auto-generated secrets (created by Terraform):
# - PostgreSQL admin password
# - Phoenix SECRET_KEY_BASE
#
# Storage strategy (dual-mode based on var.use_key_vault):
# - Mode A (use_key_vault=false, DEFAULT): Stored in Terraform state, injected into Container Apps secrets
# - Mode B (use_key_vault=true, OPTIONAL): Stored in Azure Key Vault, Container Apps references via secret URI

# T024: PostgreSQL admin password
resource "random_password" "postgres_admin_password" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"

  lifecycle {
    ignore_changes = [
      length,
      special,
      override_special,
    ]
  }
}

# T025: Phoenix SECRET_KEY_BASE (64-char cryptographic random, no special chars)
resource "random_password" "phoenix_secret_key_base" {
  length  = 64
  special = false

  lifecycle {
    ignore_changes = [
      length,
      special,
    ]
  }
}
