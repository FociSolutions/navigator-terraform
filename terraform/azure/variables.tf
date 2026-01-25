# Environment Configuration
variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "canadacentral"
}

variable "resource_group_name" {
  description = "Name of the resource group for application infrastructure"
  type        = string
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default = {
    Project    = "valentine"
    ManagedBy  = "terraform"
    CostCenter = "navigator"
  }
}

# Network Configuration
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.240.0.0/16"]
}

variable "container_apps_subnet_address_prefix" {
  description = "Address prefix for Container Apps subnet"
  type        = string
  default     = "10.240.1.0/24"
}

variable "postgresql_subnet_address_prefix" {
  description = "Address prefix for PostgreSQL subnet"
  type        = string
  default     = "10.240.2.0/24"
}

variable "appgw_subnet_address_prefix" {
  description = "Address prefix for Application Gateway subnet (future use)"
  type        = string
  default     = "10.240.3.0/24"
}

# Container Apps Configuration
variable "container_cpu" {
  description = "CPU allocation for container (vCPU)"
  type        = number
  default     = 0.5
}

variable "container_memory" {
  description = "Memory allocation for container (e.g., 0.5Gi, 1.0Gi)"
  type        = string
  default     = "1Gi"
}

variable "min_replicas" {
  description = "Minimum number of container replicas"
  type        = number
  default     = 0
}

variable "max_replicas" {
  description = "Maximum number of container replicas"
  type        = number
  default     = 2
}

variable "container_image" {
  description = "Container image for Navigator application"
  type        = string
  default     = "public.ecr.aws/cds-snc/valentine:latest"
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 4000
}

# PostgreSQL Configuration
variable "postgres_sku" {
  description = "PostgreSQL SKU (e.g., B_Standard_B1ms, GP_Standard_D2s_v3)"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgres_storage_gb" {
  description = "PostgreSQL storage size in GB"
  type        = number
  default     = 32
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "14"
}

variable "postgres_ha_enabled" {
  description = "Enable PostgreSQL zone-redundant high availability"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
}

variable "postgres_require_ssl" {
  description = "Require SSL/TLS for PostgreSQL connections (require_secure_transport server parameter). When false, network isolation via delegated subnet provides primary security control."
  type        = bool
  default     = false
}

variable "postgres_admin_username" {
  description = "PostgreSQL administrator username"
  type        = string
  default     = "psqladmin"
  sensitive   = true
}

# Storage Account Configuration
variable "create_storage_account" {
  description = "Create Azure Storage Account for user uploads"
  type        = bool
  default     = false
}

variable "storage_account_sku" {
  description = "Storage Account SKU (Standard_LRS, Standard_ZRS)"
  type        = string
  default     = "Standard_LRS"
}

# Azure Container Registry Configuration
variable "create_acr" {
  description = "Create Azure Container Registry for container images"
  type        = bool
  default     = false
}

# DNS Configuration
variable "domain_name" {
  description = "Custom domain name for the application"
  type        = string
  default     = null
}

# Monitoring Configuration (Reserved for future use)
# Application Insights monitoring can be added in future iterations

# Cost Optimization
variable "enable_zone_redundancy" {
  description = "Enable zone redundancy for resources"
  type        = bool
  default     = false
}

variable "create_azure_openai" {
  description = "Create Azure OpenAI Cognitive Services resource"
  type        = bool
  default     = false
}

# Network Security Configuration
variable "enable_outbound_internet" {
  description = "Enable outbound internet access from Container Apps (required for OpenAI API integration)"
  type        = bool
  default     = true
}

# Authentication Configuration (Optional)
# These credentials are passed as Container Apps secrets when provided via TF_VAR_ environment variables
# See architecture.md line 124-125 for authentication approach

variable "google_client_id" {
  description = "Google OAuth 2.0 Client ID for authentication (optional, passed via TF_VAR_google_client_id)"
  type        = string
  default     = null
  sensitive   = true
}

variable "google_client_secret" {
  description = "Google OAuth 2.0 Client Secret (optional, passed via TF_VAR_google_client_secret)"
  type        = string
  default     = null
  sensitive   = true
}

variable "microsoft_client_id" {
  description = "Microsoft Entra ID Application Client ID (optional, passed via TF_VAR_microsoft_client_id)"
  type        = string
  default     = null
  sensitive   = true
}

variable "microsoft_client_secret" {
  description = "Microsoft Entra ID Application Client Secret (optional, passed via TF_VAR_microsoft_client_secret)"
  type        = string
  default     = null
  sensitive   = true
}

variable "microsoft_tenant_id" {
  description = "Microsoft Entra ID Tenant ID (optional, passed via TF_VAR_microsoft_tenant_id)"
  type        = string
  default     = null
  sensitive   = true
}
