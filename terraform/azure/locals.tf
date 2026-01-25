# Naming Convention Locals
# Centralized naming patterns following .github/instructions/terraform.instructions.md

locals {
  # Base naming components
  name_prefix = "nav-${var.environment}"

  # Hash for global uniqueness (deterministic)
  uniqueness_suffix = substr(sha256("${var.resource_group_name}-${var.environment}"), 0, 8)

  # Networking
  vnet_name      = "${local.name_prefix}-vnet"
  ca_snet_name   = "${local.name_prefix}-ca-snet"
  db_snet_name   = "${local.name_prefix}-db-snet"
  agw_snet_name  = "${local.name_prefix}-agw-snet"
  ca_nsg_name    = "${local.name_prefix}-ca-nsg"
  db_nsg_name    = "${local.name_prefix}-db-nsg"
  natgw_pip_name = "${local.name_prefix}-natgw-pip"
  natgw_name     = "${local.name_prefix}-natgw"
  db_vnet_link   = "${local.name_prefix}-db-vnet-link"

  # Compute
  law_name = "${local.name_prefix}-law"
  cae_name = "${local.name_prefix}-cae"
  ca_name  = local.name_prefix                                    # Single instance, no -001 suffix
  acr_name = "nav${var.environment}acr${local.uniqueness_suffix}" # No hyphens for ACR

  # Data
  psql_name = "${local.name_prefix}-psql"
  db_name   = "navigator" # Keep database name as-is

  # Storage
  st_name     = "nav${var.environment}st${local.uniqueness_suffix}"
  st_pe_name  = "${local.name_prefix}-st-pe"
  st_psc_name = "${local.name_prefix}-st-psc"

  # Cognitive Services
  openai_name = "${local.name_prefix}-openai"
}
