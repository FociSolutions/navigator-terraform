# Architecture Plan: Internal Container Apps with Reverse Proxy

**Branch**: `002-internal-ca` | **Date**: 2026-01-25 | **Spec**: [spec.md](./spec.md)
**Input**: Infrastructure specification from `/specs/002-internal-ca/spec.md`

**Note**: This plan implements a secure reverse proxy architecture by converting existing publicly exposed Container Apps to internal-only access with Application Gateway as the public entry point. For deep research, module specs, and quickstart guide, run `/iac.enrichplan` after planning.

## Summary

This architecture secures the existing Navigator application deployment by converting the Container Apps environment from public to internal-only ingress and routing all external traffic through Azure Application Gateway as a reverse proxy. The implementation provides defense-in-depth security, centralized SSL/TLS termination, optional Web Application Firewall protection, and maintains WebSocket support for Phoenix LiveView real-time features. The infrastructure leverages existing VNet resources where possible and adds Application Gateway with backend health probes, session affinity, and network security group restrictions to enforce internal-only access patterns.

## Technical Context

**Cloud Provider**: Microsoft Azure (Canada Central region)
**IaC Tool**: Terraform >= 1.8.0 (Terraform >= 1.9+ recommended for production)
**Provider Versions**:
- hashicorp/azurerm >= 4.0, < 5.0 (use ~> 4.58 for latest stable features)
- Azure/azapi ~> 2.0 (for session affinity configuration)
- hashicorp/random ~> 3.0 (for secret generation)

**Module Versions**:
- Azure/avm-res-network-applicationgateway/azurerm = 0.4.3 (Azure Verified Module - OPTIONAL, user preference for existing resources)
- Direct resource definitions preferred per project principles (Prefer Resource Simplicity)

**Curated Modules**: Azure Verified Modules (AVM) available but not required per user request to prefer existing resources
**State Backend**: Azure Blob Storage with Terragrunt orchestration (configured in terraform/env/{dev,production}/terragrunt.hcl)
**Environment Strategy**: Terragrunt-based directory structure with environment-specific input files (dev, production)
**Testing**: terraform test (.tftest.hcl files), manual validation of security posture
**Security Scanning**: trivy config terraform/ (required for security validation)
**Cost Estimation**: Azure Pricing Calculator (manual estimates for Application Gateway sizing)
**Target Environments**: dev (minimal configuration), production (zone redundancy, enhanced capacity)
**Compliance**: Government of Canada ITSG-33 alignment, defense-in-depth security requirements

## Principles Check

### Architecture Principles Alignment

**✅ Prefer Managed Services**: Application Gateway is a fully managed Azure PaaS service providing reverse proxy, SSL termination, and optional WAF capabilities without operational overhead. Meets baseline requirement for managed platform services.

**✅ Design for Simplicity**:
- Baseline (Dev): Single Application Gateway instance (no zone redundancy), basic SKU tier (Standard_v2), minimal backend pool configuration
- Enhanced (Production): Zone-redundant Application Gateway (Standard_v2 with availability zones), enhanced monitoring, production-grade capacity settings

**✅ Design for Reliability and Resilience**:
- Baseline (Dev): Basic health probes every 30 seconds, single gateway instance acceptable for development workloads
- Enhanced (Production): Zone-redundant deployment across availability zones, comprehensive health checks with 30-second intervals, backend pool supports auto-scaling Container Apps (2-10 replicas)

**✅ Optimize for Cost**:
- Baseline (Dev): Standard_v2 tier (smallest viable size), fixed capacity (no auto-scaling), WAF optional/disabled to reduce costs
- Enhanced (Production): Right-sized Standard_v2 tier with auto-scaling (2-10 units), reserved capacity consideration for 12-month commitment

### IaC Code Principles Alignment

**✅ Prefer Resource Simplicity**: User explicitly requested to prefer existing resources and avoid unnecessary modules. Plan uses direct `azurerm_application_gateway` resource definitions rather than Azure Verified Module wrapper. Module available as optional fallback if resource complexity increases.

**✅ Automate Validation and Deployment**: Existing CI/CD patterns maintained. Plan requires `terraform validate`, `terraform fmt`, and `trivy config terraform/` checks before deployment. Testing in dev environment required before production rollout.

**✅ Manage Secrets Securely**: SSL/TLS certificates stored in Azure Key Vault (existing resource). Application Gateway references certificates via managed identity access (no hardcoded credentials). NSG rules enforce least-privilege network access patterns.

### Deviation Justifications

**None required**: All principles satisfied at appropriate complexity level for each environment tier.

## Infrastructure Architecture

### Compute Resources

**Application Gateway** (Reverse Proxy):
- **Dev Environment**:
  - SKU: Standard_v2 (smallest production-capable tier)
  - Capacity: Fixed 1 instance (no auto-scaling for cost savings)
  - Zone Redundancy: Disabled
  - Frontend: Single public IP address with HTTPS listener (port 443)
  - Backend Pool: Container Apps environment internal FQDN
  - Health Probe: HTTP probe to `/` on port 4000, 30-second interval, 20-second timeout
  - Session Affinity: Cookie-based affinity enabled for WebSocket persistence
  - Request Routing: Basic rule from frontend listener to backend pool

- **Production Environment**:
  - SKU: Standard_v2
  - Capacity: Auto-scaling 2-10 instances based on request count and CPU metrics
  - Zone Redundancy: Enabled (zones 1, 2, 3 for 99.99% SLA)
  - Frontend: Single public IP address with HTTPS listener (port 443)
  - Backend Pool: Container Apps environment internal FQDN (supports 2-10 backend instances)
  - Health Probe: HTTP probe to `/` on port 4000, 30-second interval, 20-second timeout, 3 failure threshold
  - Session Affinity: Cookie-based affinity enabled for WebSocket persistence
  - Request Routing: Path-based routing rules (if needed for future multi-service scenarios)
  - Header Rewrite: Inject `X-Forwarded-Host` header with original host value for OIDC redirect compatibility

**Web Application Firewall (Optional)**:
- **All Environments**: WAF optional and configurable via `var.appgw_enable_waf` (user requested WAF not be immediate requirement)
  - Same WAF configuration across dev and production for consistency
  - If enabled: OWASP CRS 3.2 ruleset in Prevention or Detection mode
  - Custom rules for IP allowlist/blocklist (if required)
  - Request size limits and rate limiting policies
- **Default**: WAF disabled (`appgw_enable_waf = false`) to reduce costs and complexity

**Container Apps** (Backend - Existing):
- **Modification Required**: Hardcode ingress to `external_enabled = false` when Application Gateway is enabled (controlled by `var.enable_application_gateway`)
- **Logic**: Use conditional expression: `external_enabled = var.enable_application_gateway ? false : true`
- **No other changes**: Existing scaling, health probes, and container configuration unchanged
- Container Apps will only accept traffic from Application Gateway subnet via private networking

### Data Storage

**No changes to existing data storage**:
- PostgreSQL Flexible Server: Continues operating on delegated subnet with private DNS integration
- Azure Key Vault: Used for SSL/TLS certificate storage and Application Gateway managed identity access
- Azure Storage Account: Unchanged (if configured)
- Azure OpenAI: Unchanged (if configured)

### Networking

**Virtual Network** (Existing - Modified):
- **VNet**: 10.240.0.0/16 (existing)
- **Container Apps Subnet**: 10.240.1.0/24 (existing, delegated to Microsoft.App/environments)
- **PostgreSQL Subnet**: 10.240.2.0/24 (existing, delegated to Microsoft.DBforPostgreSQL/flexibleServers)
- **Application Gateway Subnet**: 10.240.3.0/24 (existing subnet already created, will be activated)
  - Subnet delegation: None (Application Gateway does not use delegated subnets)
  - Subnet NSG: MUST NOT have NSG attached (Azure platform limitation for Application Gateway)
  - Service Endpoints: Microsoft.Storage (for diagnostic logs)

**Public IP Address** (New):
- **Dev**: Standard SKU, Static allocation, Single zone
- **Production**: Standard SKU, Static allocation, Zone-redundant (zones 1,2,3)
- DNS Label: `navigator-{environment}-appgw` (e.g., `navigator-dev-appgw.canadacentral.cloudapp.azure.com`)

**Network Security Groups** (Modified):
- **Container Apps NSG** (Automatically Modified when Application Gateway is enabled):
  - **Remove**: Existing rule allowing 0.0.0.0/0 on port 443
  - **Add**: Allow HTTPS (443) from Application Gateway subnet (10.240.3.0/24) ONLY
  - **Add**: Allow HTTP (80) from Application Gateway subnet (10.240.3.0/24) for backend communication
  - **Logic**: Conditional resource - NSG rules automatically updated when `var.enable_application_gateway = true`
  - **Rationale**: Enforce defense-in-depth by restricting Container Apps to receive traffic only from Application Gateway

- **Application Gateway Subnet**:
  - **No NSG Allowed**: Azure Application Gateway requires subnet without NSG (platform requirement)
  - Traffic control managed via Application Gateway's built-in firewall rules and WAF policies

**DNS Configuration**:
- **Custom Domain** (Optional - controlled by `var.domain_name`):
  - **DNS Zone**: Existing Azure DNS zone managed in `dns.tf` (conditional on `var.domain_name != null`)
  - **A Record Update**: Modify existing `azurerm_dns_a_record.container_app` to point to Application Gateway public IP instead of Container Apps Environment static IP
    - **Before**: `records = [azurerm_container_app_environment.main.static_ip_address]`
    - **After**: `records = [azurerm_public_ip.app_gateway[0].ip_address]` (when Application Gateway enabled)
  - **TXT Record**: Domain verification record unchanged (not needed for Application Gateway)
  - **Custom Domain Binding**: Remove Container Apps custom domain binding resources (not needed when using Application Gateway)
- **Internal DNS**: Container Apps internal FQDN unchanged, used as Application Gateway backend pool target

**NAT Gateway** (Existing - Unchanged):
- Production environment retains NAT Gateway for outbound connectivity (zone 1)
- Dev environment has no NAT Gateway (cost optimization)

### Security

**Network Isolation**:
- **Container Apps Ingress**: Changed to `external_enabled = false` (internal-only access)
- **NSG Rules**: Container Apps subnet restricted to accept traffic ONLY from Application Gateway subnet (10.240.3.0/24)
- **No Direct Internet Access**: Container Apps endpoints not accessible from public internet (validated via external network scan)

**SSL/TLS Configuration**:
- **Certificate Storage**: Azure Key Vault (existing resource) OR Application Gateway-managed certificates
- **Application Gateway**:
  - Minimum TLS Version: TLS 1.2 (enforced on frontend listener)
  - Backend HTTPS: Application Gateway → Container Apps communication uses HTTPS (internal Container Apps endpoint)
  - **Certificate Management Options**:
    - **Option 1**: Use existing Key Vault integration (Application Gateway managed identity accesses certificates)
    - **Option 2**: Use Application Gateway-managed certificates (similar to Container Apps managed certificates)
  - Custom Domain: If `var.domain_name` is specified, SSL certificate for custom domain bound to frontend listener
- **Container Apps Custom Domain Binding**: Remove when Application Gateway is enabled
  - Remove `azurerm_container_app_custom_domain` resource (not needed - domain terminates at Application Gateway)
  - Remove `azapi_resource.managed_certificate` (Application Gateway handles certificates)
  - Remove certificate binding/unbinding actions (Application Gateway manages TLS termination)

**Identity and Access Management**:
- **Application Gateway Managed Identity**: System-assigned managed identity created for Application Gateway
- **Key Vault Access Policy**: Grant Application Gateway managed identity "Get" permission for secrets/certificates
- **Container Apps Managed Identity**: Existing identity unchanged (used for ACR image pull, Azure OpenAI access)

**Web Application Firewall** (Optional):
- **All Environments**: Optional configuration based on security requirements (controlled by `var.appgw_enable_waf`)
  - Same WAF policy configuration for dev and production (consistency for testing)
  - OWASP CRS 3.2 ruleset (detection or prevention mode)
  - Custom exclusion rules for false positive mitigation
  - Logging to Log Analytics workspace for security monitoring
- **Default**: Disabled to reduce costs and complexity

**Secrets Management**:
- **No New Secrets**: Existing secrets (database credentials, OAuth keys, Phoenix secret key) remain in Container Apps configuration
- **Certificate Storage**: SSL/TLS certificates stored in Azure Key Vault with RBAC access control
- **No Hardcoded Values**: All sensitive configuration passed via Terraform variables (marked sensitive = true)

### Environment Configuration

**Environment Strategy**: Terragrunt-based configuration with environment-specific input files

**Dev Environment** (`terraform/env/dev/terragrunt.hcl`):
```hcl
inputs = {
  # Application Gateway Configuration
  enable_application_gateway = true
  appgw_sku_name            = "Standard_v2"
  appgw_sku_tier            = "Standard_v2"
  appgw_capacity_min        = 1
  appgw_capacity_max        = 1  # Fixed capacity, no auto-scaling
  appgw_enable_waf          = false
  appgw_zone_redundancy     = false
}
```

**Production Environment** (`terraform/env/production/terragrunt.hcl`):
```hcl
inputs = {
  # Application Gateway Configuration
  enable_application_gateway = true
  appgw_sku_name            = "Standard_v2"
  appgw_sku_tier            = "Standard_v2"
  appgw_capacity_min        = 2
  appgw_capacity_max        = 10
  appgw_enable_waf          = false  # Optional, user preference
  appgw_zone_redundancy     = true   # Zones 1,2,3

  # Container Apps Scaling (Unchanged)
  min_replicas = 2
  max_replicas = 10
}
```

**Variable Differences**:
- Application Gateway capacity: Dev (1 fixed), Production (2-10 auto-scaling)
- Zone redundancy: Dev (disabled), Production (enabled across zones 1,2,3)
- WAF: Optional in both environments (same configuration if enabled for consistency)

**Implementation Defaults** (hardcoded in Terraform, not exposed as variables):
- Container Apps ingress: Always `external_enabled = false` when Application Gateway is enabled
- NSG rules: Always restrict Container Apps subnet to Application Gateway subnet only (no opt-in variable)
- WAF configuration: If enabled, uses same OWASP CRS ruleset and policies across all environments

### Complexity Level

**Baseline (Dev Environment)**:
- Purpose: Development, testing, cost-optimized environment for validating reverse proxy architecture
- Application Gateway: Single instance, Standard_v2 tier, no auto-scaling, no zone redundancy
- WAF: Optional (same configuration as production if enabled for consistency)
- Monitoring: Basic Application Gateway metrics (request count, response time, backend health)
- Cost: ~$100-150/month additional for Application Gateway (smallest configuration without WAF)

**Enhanced (Production Environment)**:
- Purpose: Production workload with enhanced availability and security posture
- Application Gateway: Zone-redundant (zones 1,2,3), auto-scaling 2-10 instances, Standard_v2 tier
- WAF: Optional (same configuration as dev if enabled for consistency)
- Monitoring: Comprehensive metrics and alerts (backend failures, unhealthy instances, 5xx errors, latency > 200ms)
- High Availability: Multi-zone deployment, automated failover, backend health probes every 30 seconds
- Cost: ~$250-400/month for Application Gateway (zone-redundant, auto-scaling configuration without WAF)

**Rationale**: Dev environment prioritizes cost efficiency and simplicity for development/testing workflows. Production environment provides zone-redundant deployment for reliability requirements while maintaining cost efficiency through right-sized auto-scaling policies.

### State Management

**Backend**: Azure Blob Storage with Terragrunt orchestration (existing configuration)

**Configuration**:
- **Storage Account**: Environment-specific (navtfstatedev, navtfstateprod)
- **Container**: tfstate
- **State File**: navigator.terraform.tfstate
- **Authentication**: Azure AD authentication (use_azuread_auth = true)
- **Locking**: Azure Blob Storage native locking mechanism
- **Encryption**: AES-256 server-side encryption (default for Azure Storage)

**State Isolation**:
- Separate state files per environment (dev, production)
- State managed via Terragrunt remote_state configuration in terraform/env/{environment}/terragrunt.hcl
- No shared state between environments (complete isolation)

**Backup Strategy**:
- Azure Blob Storage versioning enabled on state container
- Retention: 30-day version history for rollback capability
- Access Control: Restricted to CI/CD service principals and authorized operators via Azure RBAC

**Workspace Usage**: Single workspace per environment (no Terraform workspaces, environment separation via directory structure and Terragrunt)

## Project Structure

### Documentation (this infrastructure)

```text
specs/002-internal-ca/
├── spec.md              # Infrastructure specification (technology-agnostic) - /iac.specify
├── plan.md              # This file - architecture plan - /iac.plan
├── tasks.md             # Implementation tasks - /iac.tasks
│
│   # Optional enrichment artifacts (run /iac.enrichplan if needed):
├── research.md          # Deep research: Well-Architected Framework, curated modules
├── architecture.md      # Detailed infrastructure architecture design
├── modules.md           # Module specifications (if using custom modules)
└── quickstart.md        # Step-by-step provisioning guide
```

### Source Code (repository root)

```text
terraform/
├── azure/                      # Terraform infrastructure code (existing)
│   ├── versions.tf            # Provider version constraints (existing, unchanged)
│   ├── provider.tf            # Azure provider configuration (existing, unchanged)
│   ├── locals.tf              # Naming conventions (modified: add Application Gateway names)
│   ├── variables.tf           # Variable declarations (modified: add Application Gateway variables)
│   ├── outputs.tf             # Output declarations (modified: add Application Gateway public IP output)
│   │
│   │   # Networking Resources (Modified)
│   ├── vnet.tf                # VNet and subnets (existing, activate Application Gateway subnet)
│   ├── security.tf            # NSG rules (MODIFIED: conditional rules restrict Container Apps to Application Gateway subnet)
│   │
│   │   # New Application Gateway Resources
│   ├── application-gateway.tf # Application Gateway resource definition, public IP, backend pool, health probes
│   ├── appgw-waf.tf           # WAF policy configuration (conditional on var.appgw_enable_waf)
│   │
│   │   # Compute Resources (Modified)
│   ├── container-apps.tf      # Container Apps (MODIFIED: conditional external_enabled based on Application Gateway)
│   ├── identity.tf            # Managed identities (modified: add Application Gateway identity)
│   │
│   │   # Data Storage (Unchanged)
│   ├── postgresql.tf          # PostgreSQL Flexible Server (existing, unchanged)
│   ├── storage.tf             # Storage Account (existing, unchanged)
│   ├── auth-openai.tf         # Azure OpenAI (existing, unchanged)
│   ├── secrets.tf             # Key Vault secrets (existing, unchanged)
│   │
│   │   # DNS Configuration (Modified)
│   ├── dns.tf                 # DNS zone and A record (MODIFIED: update A record to point to Application Gateway IP)
│   │                          # Remove Container Apps custom domain binding resources (not needed with Application Gateway)
│   │
│   │   # Monitoring (Existing)
│   └── (other files...)       # Other existing infrastructure files
│
└── env/                        # Environment-specific configurations (Terragrunt)
    ├── dev/
    │   └── terragrunt.hcl     # Dev environment inputs (MODIFIED: add Application Gateway config)
    └── production/
        └── terragrunt.hcl     # Production environment inputs (MODIFIED: add Application Gateway config)
```

**Structure Decision**: Existing Terraform Infrastructure (Option 2) with organized file structure by resource type. New resources added to dedicated `application-gateway.tf` file to maintain clear separation of concerns. Existing files modified minimally (container-apps.tf, security.tf, locals.tf, variables.tf) to integrate reverse proxy architecture. Terragrunt orchestration pattern preserved for environment-specific configuration.

**File Organization Rationale**:
- `application-gateway.tf`: All Application Gateway resources (gateway, public IP, backend pool, listeners, rules, health probes)
- `appgw-waf.tf`: WAF policy configuration (conditional, optional feature)
- `security.tf`: NSG rule modifications (conditional - automatically restrict Container Apps when Application Gateway enabled)
- `container-apps.tf`: Conditional ingress logic (`external_enabled = var.enable_application_gateway ? false : true`)
- `dns.tf`: Update A record to point to Application Gateway public IP instead of Container Apps static IP (conditional on `var.domain_name`)
  - Remove Container Apps custom domain binding resources (`azurerm_container_app_custom_domain`, `azapi_resource.managed_certificate`, certificate binding actions)
  - Keep DNS zone and A record resources, update A record target
- `outputs.tf`: Export Application Gateway public IP
- Environment-specific configuration managed via Terragrunt input files (no code duplication)

## Complexity Tracking

> **No violations requiring justification**

All infrastructure decisions align with project principles at appropriate complexity levels:
- Managed services used (Application Gateway PaaS)
- Simplicity prioritized (direct resources, minimal configuration)
- Reliability scaled appropriately (dev: single zone, production: multi-zone)
- Cost optimized per environment tier (dev: minimal capacity, production: right-sized auto-scaling)
- Resource simplicity maintained (direct `azurerm_application_gateway` resource, not wrapped in module)
- Secrets managed securely (Key Vault integration, no hardcoded credentials)

---

**Next Steps**:
1. Run `/iac.tasks` to generate implementation tasks breaking down this plan into actionable steps
2. OR run `/iac.enrichplan` first for deep research on Azure Well-Architected Framework, detailed module configurations, and provisioning quickstart guide
3. Validate plan with security team for NSG rule changes and defense-in-depth architecture
4. Estimate costs for Application Gateway using Azure Pricing Calculator (Standard_v2 tier, Canada Central region)
