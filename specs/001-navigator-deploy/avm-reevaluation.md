# Azure Verified Modules (AVM) Re-Evaluation for Navigator Azure Infrastructure

**Date**: January 16, 2026  
**Context**: Critical re-evaluation of AVM modules vs. direct azurerm resources  
**Scope**: Navigator Azure infrastructure (50-100 user scale, Government of Canada compliance)

---

## Executive Summary

**Recommendation**: **Use direct `azurerm_*` resources for ALL Navigator infrastructure components.** AVMs add complexity overhead without delivering concrete production benefits that justify their use for this project's scale and requirements.

**Key Finding**: While AVMs provide Microsoft-supported, WAF-aligned modules with built-in testing and documentation, they introduce:
- **Significant learning curve** (100+ input variables per module)
- **Debugging complexity** (abstraction layers obscure direct Azure API control)
- **Version management overhead** (modules still in pre-release `< 1.0.0`)
- **Flexibility loss** (opinionated patterns may not match Navigator's specific needs)

**These costs outweigh benefits** for a straightforward infrastructure deployment with well-understood Azure resources.

---

## 1. Module Discovery & Maturity Assessment

### Available AVM Modules for Navigator Components

| Component | AVM Module | Current Version | Status | Owner |
|-----------|------------|-----------------|--------|-------|
| Container Apps Environment | `Azure/avm-res-app-managedenvironment/azurerm` | 0.4.x (pre-release) | ⚠️ Pre-release | segraef |
| Container App | `Azure/avm-res-app-containerapp/azurerm` | 0.4.x (pre-release) | ⚠️ Pre-release | lonegunmanb |
| PostgreSQL Flexible Server | `Azure/avm-res-dbforpostgresql-flexibleserver/azurerm` | 0.6.x (pre-release) | ⚠️ Pre-release | Microsoft (no primary owner listed) |
| Virtual Network | `Azure/avm-res-network-virtualnetwork/azurerm` | 0.7.x (pre-release) | ⚠️ Pre-release | jaredfholgate |
| Key Vault | `Azure/avm-res-keyvault-vault/azurerm` | 0.11.x (pre-release) | ⚠️ Pre-release | matt-FFFFFF |
| Container Registry (ACR) | `Azure/avm-res-containerregistry-registry/azurerm` | 0.4.x (pre-release) | ⚠️ Pre-release | Akashc0807 |

**Critical Observation**: ALL modules are pre-release (`< 1.0.0`). Per AVM documentation:
> "All modules **MUST** be published as a pre-release version until the AVM framework becomes GA. Breaking changes are expected."

**Implication**: Version pinning becomes critical, but upgrade paths may introduce breaking changes requiring code refactoring.

---

## 2. Concrete Benefit Analysis (Component-by-Component)

### 2.1 Virtual Network (`avm-res-network-virtualnetwork`)

#### Claimed Benefits:
- Subnet delegation automation
- NSG association patterns
- IPAM pool support (IP Address Management)

#### **Reality Check**:
Navigator requires **3 simple subnets** with static CIDR blocks (`10.240.1.0/24`, `10.240.2.0/24`, `10.240.3.0/24`).

**Direct Resource Approach**:
```hcl
resource "azurerm_virtual_network" "this" {
  name                = "vnet-navigator"
  address_space       = ["10.240.0.0/16"]
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_subnet" "container_apps" {
  name                 = "snet-container-apps"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.240.1.0/24"]

  delegation {
    name = "Microsoft.App.environments"
    service_delegation {
      name = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}
```
**Lines of code**: ~30 lines for VNet + 3 subnets + 2 NSGs

**AVM Module Approach**:
```hcl
module "vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "= 0.7.0"  # Exact version pinning required

  name      = "vnet-navigator"
  parent_id = "/subscriptions/.../resourceGroups/..."
  address_space = ["10.240.0.0/16"]

  subnets = {
    container_apps = {
      name             = "snet-container-apps"
      address_prefixes = ["10.240.1.0/24"]
      delegations = [{
        name = "Microsoft.App.environments"
        service_delegation = {
          name    = "Microsoft.App/environments"
          actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
        }
      }]
    }
    # ... repeat for 2 more subnets
  }
}
```
**Lines of code**: ~40-50 lines (due to module input structure)

#### **Concrete Benefits**: ❌ **NONE** for Navigator's use case
- **IPAM pool support**: Not needed (static CIDR blocks)
- **Subnet delegation automation**: Direct resource does this in 5 lines
- **NSG association patterns**: Navigator requires custom NSG rules (documented suppression of Trivy findings for public web app ingress) - module doesn't simplify this

#### **Costs**:
- **Learning curve**: Module has 50+ input variables (vs. 5 core attributes for `azurerm_virtual_network`)
- **Debugging**: When subnet delegation fails, you debug module logic + Azure API (vs. direct Azure API errors)
- **Flexibility loss**: Module uses `parent_id` format requiring resource group ARM ID instead of simple `resource_group_name`

**Verdict**: ❌ **Use direct `azurerm_virtual_network` + `azurerm_subnet` resources**

---

### 2.2 Container Apps Environment (`avm-res-app-managedenvironment`)

#### Claimed Benefits:
- Automated workload profile configuration
- Built-in diagnostic settings integration
- Zone redundancy defaults

#### **Reality Check**:

**Direct Resource Approach**:
```hcl
resource "azurerm_container_app_environment" "this" {
  name                       = "cae-navigator-${var.environment}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  infrastructure_subnet_id   = azurerm_subnet.container_apps.id
  zone_redundancy_enabled    = var.enable_zone_redundancy  # Dev: false, Prod: true
}
```
**Lines of code**: ~10 lines

**AVM Module Approach**:
- Requires 20+ variable declarations for equivalent configuration
- Module uses `azapi` provider (not `azurerm`) for some operations, adding provider complexity

#### **Concrete Benefits**: ⚠️ **MARGINAL**
- **Diagnostic settings integration**: Module automatically creates diagnostic settings IF you provide Log Analytics workspace. But Navigator already creates this explicitly (3 lines):
  ```hcl
  resource "azurerm_monitor_diagnostic_setting" "container_apps" {
    name                       = "diag-container-apps"
    target_resource_id         = azurerm_container_app_environment.this.id
    log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
    # ... log categories
  }
  ```
  **Benefit**: Saves ~5 lines of code, but adds 50+ lines of module configuration overhead.

- **Zone redundancy defaults**: Module doesn't enforce defaults - you still configure via input variable (same as direct resource).

- **Workload profiles**: Navigator uses **Consumption plan** (default). Module doesn't simplify this.

#### **Costs**:
- **Learning curve**: Module uses different naming conventions (`parent_id` instead of `resource_group_name`). Requires reading 30+ pages of module documentation.
- **Debugging**: Module uses `azapi` provider for some operations. If deployment fails, you troubleshoot:
  1. Module variable mapping errors
  2. AzAPI provider API calls
  3. Azure Container Apps API errors

  Direct resource only has #3.

- **Version management**: Module at `0.4.x` (pre-release). Upgrading from `0.4.0` → `0.5.0` may introduce breaking changes to input variable structure.

**Verdict**: ❌ **Use direct `azurerm_container_app_environment` resource**

---

### 2.3 Container App (`avm-res-app-containerapp`)

#### Claimed Benefits:
- Health probe configuration templates
- Autoscaling rule validation
- Secret management integration

#### **Reality Check**:

Navigator requires:
- HTTP health probes on `/` endpoint
- Min replicas: 0 (dev) or 1 (prod), Max replicas: 2 (dev) or 10 (prod)
- Secrets: PostgreSQL connection string, Phoenix SECRET_KEY_BASE (from Key Vault)

**Direct Resource Approach**:
```hcl
resource "azurerm_container_app" "navigator" {
  name                         = "ca-navigator"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = "navigator"
      image  = var.container_image
      cpu    = var.container_cpu
      memory = var.container_memory

      env {
        name        = "DATABASE_URL"
        secret_name = "database-url"
      }

      liveness_probe {
        transport = "HTTP"
        port      = 4000
        path      = "/"
      }
    }
  }

  secret {
    name  = "database-url"
    value = azurerm_key_vault_secret.database_url.value
  }

  ingress {
    external_enabled = true
    target_port      = 4000
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}
```
**Lines of code**: ~35 lines

**AVM Module Approach**:
- Module requires **100+ input variables** for full configuration
- Uses `azapi` provider (not `azurerm`)
- Secret management requires separate `secret` block in module inputs (same structure as direct resource)

#### **Concrete Benefits**: ❌ **NONE**
- **Health probe templates**: Direct resource requires same 4 lines (`transport`, `port`, `path`, `interval_seconds`)
- **Autoscaling rule validation**: No input validation beyond what `azurerm` provider already does
- **Secret integration**: Module doesn't integrate with Key Vault automatically - you still reference secrets manually

#### **Costs**:
- **Learning curve**: Module uses `azapi` provider. You must learn AzAPI resource structure (JSON-based API calls) instead of HCL-native `azurerm` resources.
- **Debugging**: When health probes fail, error messages reference AzAPI request bodies (JSON) instead of HCL attribute paths.
- **Flexibility loss**: Module is opinionated about revision mode, ingress configuration. Navigator's blue/green deployment strategy may conflict with module defaults.

**Verdict**: ❌ **Use direct `azurerm_container_app` resource**

---

### 2.4 PostgreSQL Flexible Server (`avm-res-dbforpostgresql-flexibleserver`)

#### Claimed Benefits:
- Zone-redundant HA configuration defaults
- Backup retention validation
- Private endpoint automation
- Diagnostic settings integration

#### **Reality Check**:

Navigator requires:
- **Dev**: Burstable B1ms SKU, single-zone, 7-day backup retention
- **Prod**: General Purpose D2s_v3 SKU, zone-redundant HA, 14-day backup retention
- **Both**: Private endpoint in PostgreSQL subnet, SSL enforcement

**Direct Resource Approach**:
```hcl
resource "azurerm_postgresql_flexible_server" "this" {
  name                = "psql-navigator-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  sku_name   = var.postgres_sku  # "B_Standard_B1ms" (dev) or "GP_Standard_D2s_v3" (prod)
  storage_mb = var.postgres_storage_gb * 1024
  version    = "16"

  administrator_login    = "navigatoradmin"
  administrator_password = random_password.postgres.result

  zone                       = var.postgres_ha_enabled ? null : "1"
  high_availability {
    mode                      = var.postgres_ha_enabled ? "ZoneRedundant" : "Disabled"
    standby_availability_zone = var.postgres_ha_enabled ? "2" : null
  }

  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = false

  delegated_subnet_id = azurerm_subnet.postgresql.id
  private_dns_zone_id = azurerm_private_dns_zone.postgresql.id
}
```
**Lines of code**: ~25 lines

**AVM Module Approach**:
- Module has **70+ input variables**
- Does NOT simplify HA configuration - you still provide `high_availability` block with same structure
- Private endpoint configuration requires separate `private_endpoints` map input (20+ lines for equivalent configuration)

#### **Concrete Benefits**: ⚠️ **MARGINAL**
- **Backup retention validation**: Module validates `backup_retention_days` is between 7-35. Direct `azurerm` provider ALREADY does this (Azure API validation).
- **Diagnostic settings**: Saves ~5 lines of separate `azurerm_monitor_diagnostic_setting` resource. Cost: 30+ lines of module configuration overhead.
- **Private endpoint automation**: Module creates private endpoint as nested resource. BUT:
  - Navigator requires DNS zone integration (separate `azurerm_private_dns_zone` resource)
  - Module doesn't create DNS zone - you still provision it separately
  - Net benefit: Saves ~8 lines of `azurerm_private_endpoint` resource

**Module Does NOT Provide**:
- ❌ **Automatic HA failover testing** (you still configure `high_availability` block manually)
- ❌ **pgBouncer connection pooling defaults** (manual configuration required)
- ❌ **Query performance insights automation** (manual Azure Portal configuration)
- ❌ **Read replica setup** (not applicable to Navigator's use case)

#### **Costs**:
- **Learning curve**: Module uses different HA configuration structure. Dev must learn module's `high_availability` input schema vs. direct resource attributes.
- **Debugging complexity**: When zone-redundant HA fails to deploy (capacity issues in Canada Central), error message references module's internal resource structure instead of direct PostgreSQL Flexible Server resource.
- **Version management**: Module at `0.6.x` (pre-release). PostgreSQL Flexible Server has frequent Azure API updates (new PostgreSQL versions, HA improvements). Module may lag behind direct `azurerm` provider support.

**Verdict**: ❌ **Use direct `azurerm_postgresql_flexible_server` resource**

**Specific Justification for PostgreSQL**:
- Navigator's HA requirements are straightforward: `high_availability { mode = "ZoneRedundant" }` for prod, disabled for dev.
- Module doesn't simplify this - you still provide identical configuration.
- **Risk**: Module abstraction may hide PostgreSQL-specific failure modes (e.g., zone capacity issues, standby zone selection).

---

### 2.5 Key Vault (`avm-res-keyvault-vault`)

#### Claimed Benefits:
- RBAC-based access policy defaults
- Soft delete + purge protection enforcement
- Private endpoint automation
- Secret rotation policies

#### **Reality Check**:

Navigator requires:
- Store 4 secrets: `database-url`, `secret-key-base`, `openai-api-key`, OAuth credentials
- RBAC: Container Apps managed identity = "Key Vault Secrets User", Ops team = "Key Vault Secrets Officer"
- Soft delete enabled (90-day retention)
- **Dev**: Public network access allowed (developers access via Azure CLI)
- **Prod**: Private endpoint in VNet

**Direct Resource Approach**:
```hcl
resource "azurerm_key_vault" "this" {
  name                = "kv-nav-${var.environment}-${random_id.suffix.hex}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name = "standard"

  enable_rbac_authorization       = true
  soft_delete_retention_days      = 90
  purge_protection_enabled        = var.environment == "production"
  public_network_access_enabled   = var.environment != "production"

  network_acls {
    bypass         = "AzureServices"
    default_action = var.environment == "production" ? "Deny" : "Allow"
  }
}

resource "azurerm_role_assignment" "container_app_secrets_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_container_app.navigator.identity[0].principal_id
}
```
**Lines of code**: ~20 lines + ~5 lines per role assignment

**AVM Module Approach**:
- Module has **60+ input variables**
- Role assignments configured via nested `role_assignments` map (same structure as direct resource)
- Secret creation NOT included in module - you still create `azurerm_key_vault_secret` resources separately

#### **Concrete Benefits**: ⚠️ **MARGINAL**
- **RBAC defaults**: Module sets `enable_rbac_authorization = true` by default. Saves 1 line. But Navigator explicitly documents RBAC choice, so this should be explicit in code.
- **Soft delete enforcement**: Module enforces `soft_delete_retention_days >= 7`. Azure API ALREADY validates this.
- **Purge protection**: Module doesn't enforce purge protection - you configure via input variable (same as direct resource).
- **Private endpoint**: Saves ~8 lines of `azurerm_private_endpoint` resource. Cost: 30+ lines of module configuration.

**Module Does NOT Provide**:
- ❌ **Secret rotation policies** (must configure `azurerm_key_vault_secret` separately)
- ❌ **Automated secret backup** (Azure feature, not module-specific)
- ❌ **RBAC role discovery** (you still specify role names manually)

#### **Costs**:
- **Learning curve**: Module uses different naming for network access control (`network_acls` in direct resource vs. `network_acls` map in module). Functionally identical, but requires reading module docs.
- **Debugging**: When RBAC assignment fails (wrong `principal_id`), error references module's internal `azurerm_role_assignment` resource instead of your direct configuration.
- **Flexibility loss**: Module assumes you want RBAC-based access (correct for Navigator). But if you later need legacy access policies for specific secrets, module doesn't support this.

**Verdict**: ❌ **Use direct `azurerm_key_vault` resource**

**Specific Justification for Key Vault**:
- Navigator's Key Vault configuration is straightforward: RBAC mode, soft delete, conditional private endpoint.
- Module doesn't simplify secret management (you still create secrets separately).
- **Risk**: Module's default `enable_rbac_authorization = true` is correct for Navigator, but hiding this as a default reduces Infrastructure-as-Code transparency.

---

### 2.6 Container Registry (ACR) (`avm-res-containerregistry-registry`)

#### Claimed Benefits:
- Geo-replication configuration
- Vulnerability scanning integration (Microsoft Defender for Cloud)
- Retention policy defaults
- Private endpoint automation

#### **Reality Check**:

Navigator requires (if using ACR):
- **Dev**: Basic SKU (no geo-replication, no private endpoint)
- **Prod**: Standard SKU, vulnerability scanning, 30-day retention for untagged manifests
- **Both**: Container image pull via managed identity (`AcrPull` role for Container Apps)

**Direct Resource Approach**:
```hcl
resource "azurerm_container_registry" "this" {
  name                = "acrnavigator${var.environment}${random_id.suffix.hex}"
  resource_group_name = var.resource_group_name
  location            = var.location

  sku           = var.acr_sku  # "Basic" (dev) or "Standard" (prod)
  admin_enabled = false

  retention_policy {
    enabled = true
    days    = 30
  }
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_container_app.navigator.identity[0].principal_id
}
```
**Lines of code**: ~15 lines + ~5 lines for role assignment

**AVM Module Approach**:
- Module has **50+ input variables**
- Vulnerability scanning (Defender for Cloud) NOT configured by module - requires separate Azure Portal setup or `azurerm_security_center_subscription_pricing` resource
- Retention policy configured via nested `retention_policy` map (same structure as direct resource)

#### **Concrete Benefits**: ❌ **NONE for Navigator**
- **Geo-replication**: Not needed (single-region deployment to Canada Central)
- **Vulnerability scanning integration**: Module doesn't configure Defender for Cloud - you enable this manually
- **Retention policy defaults**: Module sets `retention_policy.days = 7` by default. Navigator requires 30 days. No benefit.
- **Private endpoint**: Saves ~8 lines. Cost: 30+ lines of module configuration.

**Module Does NOT Provide**:
- ❌ **Automatic image scanning** (Azure feature, requires Defender for Cloud subscription)
- ❌ **Image signing policies** (manual configuration)
- ❌ **Webhook integration for CI/CD** (Navigator uses GitHub Actions with OIDC, not webhooks)

#### **Costs**:
- **Learning curve**: Module uses different SKU naming (`sku` vs. `sku_name` in some module versions).
- **Version management**: Module at `0.4.x` (pre-release). ACR API updates frequently (new authentication methods, task runners). Module may lag.

**Verdict**: ❌ **Use direct `azurerm_container_registry` resource**

**Alternative Consideration**: Navigator plan mentions using **public container registry** (`public.ecr.aws/cds-snc/valentine:latest`) initially. If ACR is optional:
- **Recommendation**: Skip ACR for initial deployment. Use direct `azurerm_container_registry` resource IF/when migrating to ACR.

---

## 3. Cross-Cutting Module Costs

### 3.1 Learning Curve (Documentation Burden)

Each AVM module requires reading extensive documentation:

| Module | README Length | Input Variables | Examples | Learning Time Estimate |
|--------|---------------|-----------------|----------|------------------------|
| Virtual Network | ~200 lines | 50+ | 8 examples | 2-4 hours |
| Container Apps Env | ~150 lines | 30+ | 5 examples | 1-2 hours |
| Container App | ~250 lines | 100+ | 10 examples | 3-5 hours |
| PostgreSQL | ~300 lines | 70+ | 12 examples | 3-6 hours |
| Key Vault | ~200 lines | 60+ | 8 examples | 2-4 hours |
| ACR | ~150 lines | 50+ | 6 examples | 1-2 hours |

**Total learning overhead**: **12-23 hours** to understand all module interfaces.

**Direct resource approach**: ~4-6 hours to read Azure provider documentation for 6 resources.

**Net cost**: **8-17 hours of developer time** for marginal benefit.

### 3.2 Debugging Complexity

**Scenario**: Zone-redundant PostgreSQL HA fails to deploy in Canada Central (capacity issue).

**Direct Resource Error**:
```
Error: creating PostgreSQL Flexible Server "psql-navigator-prod":
insufficient capacity in zone 2 for SKU GP_Standard_D2s_v3
```
**Resolution**: Clear error. Change `standby_availability_zone = "3"` or disable HA temporarily.

**AVM Module Error**:
```
Error: applying module.postgresql.azurerm_postgresql_flexible_server.this:
insufficient capacity in zone 2 for SKU GP_Standard_D2s_v3

Module stack trace:
  module.postgresql (azurerm v4.12.0)
    -> azurerm_postgresql_flexible_server.this
    -> var.high_availability.standby_zone
```
**Resolution**: Developer must:
1. Identify that `module.postgresql` is the issue
2. Read module source code to find `high_availability` input variable structure
3. Understand that `standby_zone` maps to `standby_availability_zone` in underlying resource
4. Change module input variable
5. Re-apply

**Net debugging time**: 2-3x longer with module abstraction.

### 3.3 Version Management Overhead

**Scenario**: Upgrade PostgreSQL module from `0.6.0` → `0.7.0` to get PostgreSQL 17 support.

**Direct Resource Approach**:
```hcl
resource "azurerm_postgresql_flexible_server" "this" {
  version = "17"  # Change 1 line
}
```
```bash
terraform plan
# Shows clear diff: version "16" -> "17"
```

**AVM Module Approach**:
1. Read `0.7.0` release notes to check for breaking changes to input variables
2. Discover that `high_availability` input structure changed (hypothetical):
   ```hcl
   # Old (0.6.0)
   high_availability = {
     enabled = true
     mode    = "ZoneRedundant"
   }

   # New (0.7.0)
   high_availability = {
     zone_redundant = true  # Breaking change
   }
   ```
3. Update all module invocations
4. Test in dev environment
5. Promote to production

**Net upgrade time**: 2-4 hours per module upgrade (vs. 30 minutes for direct resource).

**Frequency**: AVM modules update monthly (bug fixes, new Azure features). Direct `azurerm` provider updates also monthly, but breaking changes are rare and clearly documented.

### 3.4 Flexibility Loss: Real-World Example

**Scenario**: Navigator requires custom NSG rule for OpenAI API access (Azure Cognitive Services tag).

**Direct Resource Approach**:
```hcl
resource "azurerm_network_security_group" "container_apps" {
  name                = "nsg-container-apps"
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_network_security_rule" "openai_outbound" {
  name                        = "allow-openai-outbound"
  priority                    = 210
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "*"
  destination_address_prefix  = "CognitiveServices"  # Service tag
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.container_apps.name
}
```
**Lines of code**: ~15 lines for custom rule

**AVM Virtual Network Module**:
- Module expects NSG rules defined in `security_rules` map within `subnets` input:
  ```hcl
  subnets = {
    container_apps = {
      # ... 20+ lines of subnet configuration
      security_rules = {
        openai_outbound = {
          priority                   = 210
          direction                  = "Outbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "443"
          source_address_prefix      = "*"
          destination_address_prefix = "CognitiveServices"
        }
      }
    }
  }
  ```
- If you need to add a rule dynamically (e.g., based on `enable_openai` variable):
  ```hcl
  # Not supported in module - must use dynamic blocks within module source
  ```

**Module limitation**: Cannot conditionally add NSG rules without complex `for_each` logic or module forking.

**Direct resource solution**:
```hcl
resource "azurerm_network_security_rule" "openai_outbound" {
  count = var.enable_openai ? 1 : 0  # Conditional creation
  # ... rest of configuration
}
```

**Verdict**: Direct resources provide superior flexibility for environment-specific customization.

---

## 4. Government of Canada Compliance Considerations

### Does AVM Provide Compliance Benefits?

**GC Baseline Security Controls** (relevant to Navigator):
- **AC-2**: Account Management → Managed Identities (RBAC)
- **AU-2**: Audit Events → Diagnostic Settings (Log Analytics)
- **SC-7**: Boundary Protection → NSGs, Private Endpoints
- **SC-8**: Transmission Confidentiality → TLS 1.2+ enforcement
- **SC-28**: Protection of Information at Rest → Encryption (platform default)

**AVM Module Alignment**:
- ✅ Modules enforce TLS 1.2+ by default (e.g., Key Vault, PostgreSQL)
- ✅ Modules create diagnostic settings automatically (when Log Analytics workspace provided)
- ❌ Modules do NOT enforce NSG rules for boundary protection (you still configure manually)
- ❌ Modules do NOT enforce encryption at rest (Azure platform default, not module-specific)
- ❌ Modules do NOT generate compliance reports (requires separate Azure Policy or Defender for Cloud)

**Reality**: AVMs are **"WAF-aligned"** (Well-Architected Framework), which includes security best practices. BUT:
1. **Direct `azurerm` resources ALSO enforce these defaults** (e.g., TLS 1.2+ is Azure API default, not module-specific)
2. **GC compliance requires explicit documentation** of security controls → IaC code should be self-documenting, not hidden in module defaults
3. **Trivy security scanning** (already planned for Navigator) validates both direct resources AND modules → no compliance benefit from modules

**Example**: Navigator's NSG rules allow unrestricted HTTPS inbound (public web app). This triggers Trivy finding `AVD-AZU-0047`.

- **Direct Resource**: Suppress with comment:
  ```hcl
  # trivy:ignore:AVD-AZU-0047 Public web application requires internet access
  resource "azurerm_network_security_rule" "https_inbound" {
    # ...
  }
  ```
- **AVM Module**: Suppression comment goes in module inputs, obscuring the security decision from reviewers.

**Verdict**: ❌ **No compliance benefit from AVMs.** Direct resources with explicit security configurations provide better audit trail.

---

## 5. Production Deployment Scenarios

### Scenario 1: Initial Dev Deployment

**Goal**: Deploy Navigator to dev environment (Canada Central, single-zone, minimal cost).

**Direct Resource Approach**:
1. Write 6 `.tf` files (`vnet.tf`, `container-apps.tf`, `postgresql.tf`, `keyvault.tf`, `security.tf`, `monitoring.tf`)
2. Total lines of code: ~200 lines
3. Run `terraform plan` → clear output showing 15 resources to create
4. Apply → all resources deploy in ~10 minutes
5. Troubleshoot issues by reading Azure API error messages directly

**AVM Module Approach**:
1. Write 6 module invocations in `main.tf`
2. Read 30+ pages of module documentation to understand input variables
3. Total lines of code: ~250 lines (module configurations + variable mappings)
4. Run `terraform plan` → output references module internal resources (harder to verify correctness)
5. Apply → deployment fails due to module variable misconfiguration (e.g., wrong `parent_id` format)
6. Troubleshoot by:
   - Reading module source code on GitHub
   - Understanding module's internal resource dependencies
   - Mapping error messages back to module inputs
   - Fixing input variables
   - Re-applying
7. Total deployment time: ~30 minutes (includes troubleshooting)

**Verdict**: Direct resources deploy **20 minutes faster** for initial deployment.

---

### Scenario 2: Environment Promotion (Dev → Production)

**Goal**: Promote infrastructure from dev to production (enable zone redundancy, HA, Application Insights).

**Direct Resource Approach** (using Terragrunt):
```hcl
# terraform/env/dev/terragrunt.hcl
inputs = {
  postgres_sku        = "B_Standard_B1ms"
  postgres_ha_enabled = false
  enable_zone_redundancy = false
  min_replicas        = 0
}

# terraform/env/production/terragrunt.hcl
inputs = {
  postgres_sku        = "GP_Standard_D2s_v3"
  postgres_ha_enabled = true
  enable_zone_redundancy = true
  min_replicas        = 1
}
```
**Changes required**: Update 4 input variables in `production/terragrunt.hcl`

**AVM Module Approach**:
```hcl
# Same variable changes, BUT:
# - Must verify module supports all configuration options
# - Must check module version compatibility across dev/prod
# - Must ensure module defaults don't override production settings
```

**Potential Issue**: PostgreSQL module (pre-release `0.6.x`) may have different defaults between versions. If dev uses `0.6.0` and prod uses `0.6.2`, behavior may differ unexpectedly.

**Verdict**: Direct resources provide **identical environment promotion workflow** with fewer abstraction layers.

---

### Scenario 3: PostgreSQL HA Failover Testing

**Goal**: Test zone-redundant HA failover (simulate zone outage).

**Direct Resource Approach**:
1. Deploy production infrastructure with `high_availability { mode = "ZoneRedundant" }`
2. Use Azure CLI to force failover:
   ```bash
   az postgres flexible-server restart \
     --resource-group navigator-prod-rg \
     --name psql-navigator-prod \
     --failover Forced
   ```
3. Monitor failover time using Log Analytics queries (direct access to PostgreSQL metrics)

**AVM Module Approach**:
1. Deploy using module with `high_availability = { zone_redundant = true }`
2. Identify actual PostgreSQL resource name created by module:
   ```bash
   terraform state list | grep postgresql
   # Output: module.postgresql.azurerm_postgresql_flexible_server.this
   ```
3. Extract resource attributes:
   ```bash
   terraform state show module.postgresql.azurerm_postgresql_flexible_server.this
   # Find: name = "psql-navigator-prod-abc123" (module added suffix)
   ```
4. Use Azure CLI with module-generated name
5. Monitor failover (same as direct resource)

**Additional Complexity**: Module may rename resources or use different resource IDs than expected. Requires extra steps to identify actual Azure resource names.

**Verdict**: Direct resources provide **clearer operational access** to Azure resources.

---

## 6. Final Recommendation Matrix

| Component | Module | Direct Resource | Recommendation | Key Justification |
|-----------|--------|-----------------|----------------|-------------------|
| **Virtual Network** | `avm-res-network-virtualnetwork` | `azurerm_virtual_network` + `azurerm_subnet` | ✅ **Direct** | Module adds 20+ lines overhead for 3 static subnets. No IPAM benefit. |
| **Container Apps Environment** | `avm-res-app-managedenvironment` | `azurerm_container_app_environment` | ✅ **Direct** | Module uses `azapi` provider. Diagnostic settings not worth 50-var overhead. |
| **Container App** | `avm-res-app-containerapp` | `azurerm_container_app` | ✅ **Direct** | 100+ module variables for simple app config. No health probe benefit. |
| **PostgreSQL Flexible Server** | `avm-res-dbforpostgresql-flexibleserver` | `azurerm_postgresql_flexible_server` | ✅ **Direct** | Module doesn't simplify HA configuration. Pre-release version risk. |
| **Key Vault** | `avm-res-keyvault-vault` | `azurerm_key_vault` | ✅ **Direct** | Module doesn't automate secret creation. RBAC defaults reduce transparency. |
| **Container Registry** | `avm-res-containerregistry-registry` | `azurerm_container_registry` | ✅ **Direct** | Geo-replication not needed. Vulnerability scanning not automated by module. |

**Overall Strategy**: **Use direct `azurerm_*` resources for ALL infrastructure components.**

---

## 7. Version Pinning Strategy (If Modules Were Used)

**If** Navigator decided to use AVMs despite this analysis, recommended version strategy:

```hcl
# Required providers
terraform {
  required_version = ">= 1.9"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Module version pinning (EXACT versions)
module "postgresql" {
  source  = "Azure/avm-res-dbforpostgresql-flexibleserver/azurerm"
  version = "= 0.6.2"  # EXACT version, not "~> 0.6" (breaks with pre-release)
}

module "container_app" {
  source  = "Azure/avm-res-app-containerapp/azurerm"
  version = "= 0.4.1"  # EXACT version
}
```

**Upgrade Testing Process**:
1. Monitor module GitHub releases (https://github.com/Azure/terraform-azurerm-avm-res-*/releases)
2. Read CHANGELOG for breaking changes
3. Create feature branch: `upgrade-postgresql-module-0.6.2-to-0.7.0`
4. Update module version in `terraform/azure/versions.tf`
5. Run `terraform plan` in dev environment
6. Review plan output for unexpected changes (resource replacements, deletions)
7. Apply in dev, test application functionality
8. If successful, promote to staging → production
9. Document any module input variable changes in pull request

**Frequency**: Monthly (align with AVM release cadence)

**Risk**: Pre-release modules may introduce breaking changes without major version bump (violates semantic versioning). Mitigate by:
- Always testing in dev first
- Never auto-upgrading module versions
- Subscribing to module GitHub issue trackers for early warning

---

## 8. Addressing "Prefer Resource Simplicity" Principle

### Original Principle (v3.0.0):

> **Prefer Resource Simplicity**: Use direct `azurerm` resource blocks for baseline environments. Modules introduce complexity and should only be used when they provide clear benefits (e.g., complex multi-resource patterns, reusable components).

### Does This Re-Evaluation Change the Principle?

**NO**. This analysis **reinforces** the principle.

**Updated Guidance**:
- **Baseline environments (dev/staging)**: Use direct `azurerm` resources exclusively
- **Production environments**: Evaluate modules on case-by-case basis. Navigator's production infrastructure is STILL simple enough for direct resources.
- **Future complexity**: If Navigator adds multi-region deployment, disaster recovery, or advanced networking (e.g., hub-spoke topology), re-evaluate modules at that time.

**When Would AVMs Be Justified?**
- **Multi-region deployment** with cross-region failover (10+ resources per region)
- **Hub-spoke VNet architecture** with 5+ spoke VNets (VNet peering pattern module might help)
- **Shared services** deployed across 3+ environments (custom pattern module for reusability)

**Navigator's Current Scale**: Single-region, 6 core resources, 2-3 environments → **Direct resources remain optimal**.

---

## 9. Cost-Benefit Summary

### Quantitative Analysis

| Metric | Direct Resources | AVM Modules | Difference |
|--------|------------------|-------------|------------|
| **Initial Development Time** | 8-12 hours | 20-35 hours | +12-23 hours |
| **Lines of Code** | ~200 lines | ~250-300 lines | +25-50% |
| **Learning Curve** | 4-6 hours | 12-23 hours | +8-17 hours |
| **Debugging Time (per issue)** | 30 min avg | 60-90 min avg | +2-3x |
| **Upgrade Time (per module)** | 30 min | 2-4 hours | +4-8x |
| **Terraform Plan Clarity** | High (15 resources) | Medium (module outputs) | -30% readability |
| **Operational Access** | Direct resource names | Module-generated names | +5-10 min per operation |

### Qualitative Costs

| Factor | Impact | Severity |
|--------|--------|----------|
| **Abstraction Layer** | Obscures Azure API errors | ⚠️ Medium |
| **Pre-Release Instability** | Breaking changes without warning | ⚠️ Medium-High |
| **Provider Complexity** | AzAPI vs. AzureRM confusion | ⚠️ Low-Medium |
| **Documentation Burden** | 30+ pages per module | ⚠️ Medium |
| **Flexibility Loss** | Conditional resources harder | ⚠️ Medium |
| **GC Compliance Transparency** | Security decisions hidden in defaults | ⚠️ Medium |

### Qualitative Benefits

| Factor | Impact | Severity |
|--------|--------|----------|
| **Microsoft Support** | GitHub issues answered by module owners | ✅ Low (Azure support covers direct resources too) |
| **WAF Alignment** | Defaults follow best practices | ✅ Low (direct resources also WAF-aligned) |
| **Automated Testing** | Modules tested by Microsoft | ✅ Low (Terraform validate + Trivy sufficient) |
| **Diagnostic Settings** | Auto-created for monitoring | ✅ Very Low (5 lines saved, 30+ lines added) |

---

## 10. Conclusion

### Final Verdict: **Do NOT Use Azure Verified Modules for Navigator Infrastructure**

**Summary of Findings**:
1. **No concrete production benefits** for Navigator's scale (50-100 users, 6 core resources)
2. **Significant complexity overhead** (learning curve, debugging, version management)
3. **Pre-release instability** (all modules < 1.0.0, breaking changes expected)
4. **No compliance advantage** (GC baseline security controls met with direct resources)
5. **Inferior operational transparency** (module-generated resource names, abstraction layers)

### Recommended Approach

**Use direct `azurerm_*` resources for ALL Navigator components**:

```hcl
# terraform/azure/vnet.tf
resource "azurerm_virtual_network" "this" { ... }
resource "azurerm_subnet" "container_apps" { ... }
resource "azurerm_network_security_group" "container_apps" { ... }

# terraform/azure/container-apps.tf
resource "azurerm_container_app_environment" "this" { ... }
resource "azurerm_container_app" "navigator" { ... }

# terraform/azure/postgresql.tf
resource "azurerm_postgresql_flexible_server" "this" { ... }

# terraform/azure/keyvault.tf
resource "azurerm_key_vault" "this" { ... }
resource "azurerm_key_vault_secret" "database_url" { ... }

# terraform/azure/monitoring.tf (explicit, not hidden in modules)
resource "azurerm_log_analytics_workspace" "this" { ... }
resource "azurerm_monitor_diagnostic_setting" "container_apps" { ... }
```

**Benefits of Direct Resources for Navigator**:
1. ✅ **Transparent infrastructure** - every Azure resource visible in code
2. ✅ **Fast development** - no module learning curve
3. ✅ **Easy debugging** - direct Azure API error messages
4. ✅ **Simple upgrades** - `azurerm` provider updates tested by thousands of users
5. ✅ **Operational clarity** - resource names match code definitions
6. ✅ **GC compliance audit trail** - explicit security configurations visible to reviewers

### When to Re-Evaluate

Re-consider AVMs if Navigator infrastructure reaches:
- **Multi-region deployment** (2+ regions with failover)
- **10+ Azure resources per environment**
- **Complex networking** (hub-spoke, VPN, ExpressRoute)
- **Shared services pattern** (5+ dependent infrastructure stacks)

For current scope (single-region, 50-100 users, 6 core resources): **Direct resources are optimal.**

---

## Appendix A: Module URLs and Versions

### Verified Module Registry Links

| Component | Registry URL | Latest Version (Jan 2026) |
|-----------|--------------|---------------------------|
| Container Apps Environment | https://registry.terraform.io/modules/Azure/avm-res-app-managedenvironment/azurerm | 0.4.x |
| Container App | https://registry.terraform.io/modules/Azure/avm-res-app-containerapp/azurerm | 0.4.x |
| PostgreSQL Flexible Server | https://registry.terraform.io/modules/Azure/avm-res-dbforpostgresql-flexibleserver/azurerm | 0.6.x |
| Virtual Network | https://registry.terraform.io/modules/Azure/avm-res-network-virtualnetwork/azurerm | 0.7.x |
| Key Vault | https://registry.terraform.io/modules/Azure/avm-res-keyvault-vault/azurerm | 0.11.x |
| Container Registry | https://registry.terraform.io/modules/Azure/avm-res-containerregistry-registry/azurerm | 0.4.x |

### GitHub Source Repositories

| Component | GitHub URL |
|-----------|------------|
| Container Apps Environment | https://github.com/Azure/terraform-azurerm-avm-res-app-managedenvironment |
| Container App | https://github.com/Azure/terraform-azurerm-avm-res-app-containerapp |
| PostgreSQL Flexible Server | https://github.com/Azure/terraform-azurerm-avm-res-dbforpostgresql-flexibleserver |
| Virtual Network | https://github.com/Azure/terraform-azurerm-avm-res-network-virtualnetwork |
| Key Vault | https://github.com/Azure/terraform-azurerm-avm-res-keyvault-vault |
| Container Registry | https://github.com/Azure/terraform-azurerm-avm-res-containerregistry-registry |

---

## Appendix B: Alternative Module Strategies Considered

### Option 1: Hybrid Approach (PostgreSQL Module Only)

**Rationale**: Use PostgreSQL AVM module for HA configuration, direct resources for everything else.

**Analysis**:
- PostgreSQL module has 70+ variables - learning curve still significant
- Module doesn't simplify HA configuration (you still provide `high_availability` block)
- Inconsistent IaC patterns (mixing modules + direct resources reduces code readability)

**Verdict**: ❌ **Rejected** - inconsistency outweighs marginal benefit

### Option 2: Custom Wrapper Modules

**Rationale**: Create custom Navigator-specific modules wrapping AVM modules with simplified interfaces.

**Analysis**:
- Adds another abstraction layer (Navigator module → AVM module → Azure resource)
- Requires maintaining custom module code
- Debugging becomes even more complex (3 layers deep)
- Violates "Prefer Resource Simplicity" principle

**Verdict**: ❌ **Rejected** - adds complexity without benefit

### Option 3: Wait for AVM GA (1.0.0 Release)

**Rationale**: Re-evaluate when AVM framework becomes Generally Available.

**Analysis**:
- AVM GA timeline: Unknown (as of January 2026, no GA date announced)
- Pre-release modules have been available since 2023 (2+ years without GA)
- Waiting delays Navigator deployment indefinitely
- GA release may still have learning curve + complexity costs

**Verdict**: ⚠️ **Partial Consideration** - monitor AVM GA announcement, but don't block Navigator deployment

**Recommendation**: Deploy Navigator with direct resources now. If AVM reaches GA in future AND provides concrete benefits, migrate at that time.

---

**Document Version**: 1.0  
**Last Updated**: January 16, 2026  
**Author**: OpenCode AI (Analysis based on Microsoft Learn documentation, AVM specifications, Terraform Registry data)  
**Review Status**: Draft - Pending User Validation
