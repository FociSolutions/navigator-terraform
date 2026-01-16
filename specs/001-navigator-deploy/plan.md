# Architecture Plan: Navigator Azure Deployment

**Branch**: `001-navigator-deploy` | **Date**: January 14, 2026 | **Spec**: [spec.md](./spec.md)
**Input**: Infrastructure specification from `/specs/001-navigator-deploy/spec.md`

**Note**: This plan provides lightweight architecture decisions informed by quick research. For deep research (Well-Architected Framework analysis, detailed module configurations, and provisioning quickstart), run `/iac.enrichplan` after planning.

## Summary

Deploy the Navigator threat modeling application (Elixir/Phoenix) to Azure with minimal infrastructure suitable for 50-100 concurrent users. The architecture uses Azure Container Apps for serverless container hosting, Azure Database for PostgreSQL Flexible Server for persistence, and Azure Key Vault for secrets management. This design mirrors the existing AWS architecture (ECS Fargate + Aurora PostgreSQL) while leveraging Azure-managed services to minimize operational overhead. Initial deployment targets development/staging environments with the ability to scale to production through configuration-driven environment promotion using Terragrunt orchestration.

**Prerequisites**: This plan assumes baseline Azure infrastructure (resource groups) and Terraform state management infrastructure (Azure Storage Account for remote backend, state locking) are already provisioned and configured.

## Infrastructure Prerequisites

Before implementing this plan, ensure the following baseline infrastructure exists:

### Azure Organizational Infrastructure
- **Resource Group(s)**: Pre-existing resource groups for application infrastructure
  - Example: `navigator-dev-rg`, `navigator-prod-rg` (or single shared resource group)
  - Region: Canada Central
  - Proper RBAC permissions assigned to deployment identities

### Terraform State Management Infrastructure
- **State Storage Resource Group**: `navigator-tfstate-rg` (or equivalent)
- **Storage Accounts**: Per-environment storage accounts for Terraform state
  - Dev: `navtfstatedev` (or equivalent naming)
  - Production: `navtfstateprod` (or equivalent naming)
  - SKU: Standard LRS
  - Region: Canada Central
  - Versioning: Enabled
  - Soft delete: Enabled
- **Storage Containers**: `tfstate` container in each storage account
- **Access Control**: RBAC permissions configured
  - CI/CD service principals: Storage Blob Data Contributor role
  - Developers: Storage Blob Data Reader role (read-only)
  - Ops team: Storage Blob Data Contributor role

**Out of Scope**: This plan does NOT include creation of the above prerequisite infrastructure. If these do not exist, they must be provisioned manually or via separate bootstrap process before proceeding with implementation.

## Technical Context

**Cloud Provider**: Microsoft Azure  
**IaC Tool**: Terraform 1.9+ (latest stable as of January 2026)  
**Provider Versions**: azurerm ~> 4.0 (latest stable, required for Container Apps native support)  
**Module Versions**: Follow "Prefer Resource Simplicity" principle (v3.0.0) using direct azurerm resources as default; modules not used in this implementation  
**Curated Modules**: Azure Verified Modules (only if complex patterns require validated composition)  
**State Backend**: Azure Blob Storage with state locking (azurerm backend)  
**Environment Strategy**: Terragrunt with directory-based environments (terraform/env/{dev,staging,production}) referencing shared module (terraform/azure/)  
**Testing**: terraform validate, terraform plan at tier boundaries  
**Security Scanning**: Trivy for infrastructure security scanning  
**Cost Estimation**: Azure Cost Management + Infracost (optional)  
**Target Environments**: dev (baseline), staging (optional), production  
**Compliance**: Government of Canada baseline security controls

## Principles Check

This plan aligns with Navigator Azure Infrastructure Principles (v2.0.0) as follows:

### Cloud Architecture Principles

**1. Favor Managed Services** ✅  
- Uses Azure Container Apps (fully managed serverless containers)
- Uses Azure Database for PostgreSQL Flexible Server (managed database with automated backups, patching)
- Uses Azure Key Vault (managed secrets service)
- Uses Azure Monitor + Application Insights (managed observability)
- Avoids self-managed VMs, container orchestration clusters, or database installations

**2. Design for Simplicity** ✅  
- Baseline (Dev): Single-zone deployment, Basic/Burstable tiers, minimal networking
- Enhanced (Production): Zone-redundant deployment, Standard/General Purpose tiers, essential features only
- No multi-region complexity, no service mesh, no unnecessary abstractions

**3. Design for Reliability and Resilience** ✅  
- Baseline (Dev): Single-zone acceptable, basic health checks, deployment slots for updates
- Enhanced (Production): Zone-redundant Container Apps and PostgreSQL, auto-scaling at 70% CPU, automated backups (7-14 days retention)
- Target availability: 99.9% for internal tools (appropriate for use case)

**4. Optimize for Cost** ✅  
- Baseline (Dev): Smallest SKUs (Container Apps Consumption plan, PostgreSQL Burstable B1ms), auto-shutdown schedules
- Enhanced (Production): Right-sized Standard/General Purpose tiers, Azure reservations for predictable workloads
- Monthly operating cost target: $50-150/month (dev), scalable to production needs

### IaC Code Principles

**1. Prefer Resource Simplicity** ✅ (Principles v3.0.0)  
- Uses direct azurerm resource blocks exclusively (azurerm_container_app, azurerm_postgresql_flexible_server, azurerm_virtual_network)
- No modules used in this implementation - all resources defined directly for maximum transparency
- Baseline environments use direct resources exclusively for maximum transparency and learning

**2. Validate During Development** ✅  
- terraform validate after each file modification
- terraform plan at tier boundaries (network complete, compute complete)
- Trivy for security scanning (exposed storage, missing encryption, overly permissive network rules)
- terraform fmt for code consistency

**3. Manage Secrets Securely** ✅  
- All secrets stored in Azure Key Vault (database passwords, API keys, connection strings)
- References secrets in Terraform using azurerm_key_vault_secret data sources
- Uses Azure Managed Identities for Container Apps to access Key Vault (no stored credentials)
- Never commits .tfvars files containing secrets (gitignored)

### Implementation Approaches

**Configuration-Driven Environment Strategy** ✅  
- Shared Terraform module under `terraform/azure/` containing all infrastructure definitions
- Terragrunt configuration in `terraform/env/{dev,staging,production}/terragrunt.hcl` referencing shared module
- Environment-specific inputs control SKUs, scaling limits, feature flags, backup retention
- Terragrunt auto-generates separate Azure Storage Account backends per environment
- Deployment strategy: validate in dev → promote to staging → deploy to production

## Infrastructure Architecture

**Scope**: This architecture covers application infrastructure only (Container Apps, PostgreSQL, networking, security). Prerequisite infrastructure (resource groups, Terraform state storage) is assumed to exist and is NOT included in this implementation.

### Compute Resources

**Azure Container Apps Environment**
- Environment: Serverless consumption plan (baseline) or dedicated workload profile (enhanced)
- Region: Canada Central (proximity to Government of Canada, data residency)
- VNet Integration: Custom VNet with subnet delegation for Container Apps (Microsoft.App/environments)
- Log Analytics Workspace: Centralized logging for all container apps in environment

**Navigator Container App**
- Image: Public container registry or Azure Container Registry (public.ecr.aws/cds-snc/valentine:latest initially, migrate to ACR)
- Container Resources:
  - Baseline (Dev): 0.25 vCPU, 0.5 GB memory (minimal cost)
  - Enhanced (Production): 0.5 vCPU, 1.0 GB memory (matches ECS Fargate sizing)
- Scaling Configuration:
  - Baseline (Dev): Min replicas: 0 (scale to zero), Max replicas: 2, HTTP concurrency: 10
  - Enhanced (Production): Min replicas: 1, Max replicas: 10, CPU-based scaling at 70% utilization
- Port: 4000 (Phoenix app default)
- Health Probes: HTTP liveness probe on "/" endpoint (matches ALB health check pattern)
- Ingress: HTTPS only (TLS 1.2+), external ingress for internet access
- Session Affinity: Enable session affinity for WebSocket persistence (real-time collaboration requires sticky sessions)
- Startup Command: Container runs default Phoenix startup sequence (database migrations on startup)

**Container Registry** (Optional, recommend for production)
- Azure Container Registry (ACR): Basic SKU (dev), Standard SKU (production)
- Geo-replication: Disabled (single region sufficient)
- Image retention policy: 30 days for untagged manifests
- Vulnerability scanning: Microsoft Defender for Cloud integration

### Data Storage

**Azure Database for PostgreSQL Flexible Server**
- Engine Version: PostgreSQL 16.x (latest stable version as of January 2026, aligns with AWS Aurora PostgreSQL 14.15 equivalent)
- SKU Configuration:
  - Baseline (Dev): Burstable B1ms (1 vCore, 2 GB RAM, ~$12/month), 32 GB storage
  - Enhanced (Production): General Purpose D2s_v3 (2 vCores, 8 GB RAM), 128 GB storage with auto-grow enabled
- High Availability:
  - Baseline (Dev): Single-zone (no HA), acceptable downtime for dev/testing
  - Enhanced (Production): Zone-redundant HA (automatic failover to standby in different AZ)
- Backup Strategy:
  - Automated backups: 14-day retention (matches AWS Aurora pattern)
  - Backup window: 02:00-04:00 UTC (non-business hours)
  - Point-in-time restore: Enabled (1-minute granularity within retention window)
  - Geo-redundant backup: Disabled (single-region deployment)
- Network Isolation:
  - Private endpoint in VNet (database not publicly accessible)
  - Access restricted to Container Apps subnet only via VNet integration
- Connection:
  - Connection string stored in Azure Key Vault
  - Container Apps retrieves credentials via Managed Identity
  - SSL/TLS enforcement: Required (TLS 1.2+)
- Performance:
  - Connection pooling: pgBouncer (built-in PostgreSQL Flexible Server feature, similar to AWS RDS Proxy concept)
  - Query performance insights: Enabled for production troubleshooting

**Azure Storage Account** (Optional, if needed for user uploads)
- SKU: Standard LRS (locally redundant storage, baseline) or Standard ZRS (zone-redundant, enhanced)
- Blob container for user-uploaded threat models or attachments
- Access tier: Hot (for frequently accessed data)
- Lifecycle management: Archive to Cool tier after 90 days, delete after 365 days
- Encryption: Microsoft-managed keys (platform encryption at rest)
- Private endpoint: Enabled for enhanced security (production)

### Networking

**Virtual Network (VNet)**
- Address Space: 10.240.0.0/16 (avoiding conflicts with common on-premises ranges)
- Region: Canada Central
- Subnets:
  - Container Apps Subnet: 10.240.1.0/24 (delegated to Microsoft.App/environments)
  - PostgreSQL Subnet: 10.240.2.0/24 (delegated to Microsoft.DBforPostgreSQL/flexibleServers for private endpoint)
  - Application Gateway Subnet: 10.240.3.0/24 (for future ALB-equivalent setup if needed)
- DNS: Azure-provided DNS (168.63.129.16) for private endpoint resolution
- Service Endpoints: Microsoft.Storage (if using Storage Account), Microsoft.KeyVault

**Network Security Groups (NSGs)**
- Container Apps NSG:
  - Inbound: Allow HTTPS (443) from Application Gateway subnet (or internet if no gateway), allow outbound to PostgreSQL subnet (5432) and internet (for OpenAI API)
  - Outbound: Allow 443 to internet (OpenAI/Azure OpenAI), 5432 to PostgreSQL subnet, 443 to Key Vault
- PostgreSQL NSG:
  - Inbound: Allow 5432 from Container Apps subnet only
  - Outbound: Deny all (database does not initiate outbound connections)

**DNS and TLS**
- DNS Hosting: Azure DNS zone for custom domain (navigator-dev.cdssandbox.xyz, valentine.cds-snc.ca)
  - **Prerequisite**: DNS zones must exist before implementation or will be created in tasks
- A Record: Points to Container Apps environment default domain or Application Gateway public IP
- TLS Certificates:
  - Baseline (Dev): Container Apps Managed Certificates (free, automatic renewal)
  - Enhanced (Production): Azure Key Vault certificates or App Gateway Managed Certificates
  - Validation: DNS validation (automated via Azure DNS integration)
  - Enforcement: HTTPS-only ingress, HTTP redirects to HTTPS

**Outbound Connectivity**
- Container Apps: VNet integration allows outbound internet access for OpenAI API calls, package downloads
- NAT Gateway: Optional for production (provides consistent outbound IP for allowlisting)
- Service Tags: Use Azure service tags for Azure OpenAI access (if using Azure OpenAI instead of OpenAI API)

### Security

**Network Security**
- Network Security Groups (NSGs):
  - Container Apps NSG: Inbound 443 from internet (or Application Gateway), outbound to PostgreSQL (5432), internet (443 for APIs), Key Vault (443)
  - PostgreSQL NSG: Inbound 5432 from Container Apps subnet only, outbound deny all
- Private Endpoints:
  - PostgreSQL: Private endpoint in VNet (no public internet access)
  - Key Vault: Private endpoint for enhanced security (production, conditional)
  - Storage Account: Private endpoint for blob access (production, conditional)
- TLS Enforcement:
  - Container Apps ingress: TLS 1.2+ only
  - PostgreSQL connections: Require SSL/TLS (enforced at database level)
  - Key Vault access: HTTPS only

**Identity and Access Management (IAM)**
- Managed Identities:
  - Container Apps: System-assigned managed identity with Key Vault Secrets User role (read secrets)
  - ACR Integration: Managed identity for pulling container images (AcrPull role)
- Role-Based Access Control (RBAC):
  - Container Apps Contributor: Developers can deploy app revisions, view logs
  - Key Vault Secrets Officer: Ops team manages secrets (write access)
  - Key Vault Secrets User: Container Apps read-only secret access
  - PostgreSQL Administrator: Database schema management (humans)
  - PostgreSQL User: Application runtime access (Managed Identity or connection string)
- Service Principal (CI/CD):
  - GitHub OIDC Federated Credential: No long-lived secrets for GitHub Actions
  - Scoped to resource group, least-privilege permissions (Contributor on Container App, read-only on Key Vault)

**Secrets Management**
- Azure Key Vault:
  - SKU: Standard (baseline), Premium (enhanced, HSM-backed keys)
  - Secrets stored:
    - PostgreSQL connection string (admin and app user credentials)
    - Azure OpenAI API key and endpoint (or OpenAI API key)
    - Phoenix SECRET_KEY_BASE (generated, not example from docker-compose.yml)
    - OAuth credentials (Google, Microsoft - conditional based on environment)
  - Access policy model: Azure RBAC (modern, recommended over legacy access policies)
  - Soft delete: Enabled (90-day retention for accidental deletion recovery)
  - Purge protection: Enabled for production (prevents permanent deletion during retention)
  - Private endpoint: Enabled for production (no public internet access, conditional)
- Secret References:
  - Container Apps references Key Vault secrets via secret URI
  - Secrets injected as environment variables at container startup
  - Automatic secret refresh on container restart (manual trigger or new revision deployment)

**Data Encryption**
- Encryption at Rest:
  - PostgreSQL: Automatic encryption with Microsoft-managed keys (platform default)
  - Storage Account: AES-256 encryption with Microsoft-managed keys
  - Key Vault: Option to use customer-managed keys (CMK) via Azure Key Vault for enhanced control (production)
- Encryption in Transit:
  - All connections: TLS 1.2+ enforced (Container Apps ingress, PostgreSQL connections, Key Vault access)
  - Internal VNet traffic: Optional TLS for Container Apps to PostgreSQL (enforced at database level)

**Security Scanning and Monitoring**
- Microsoft Defender for Cloud (post-deployment manual configuration):
  - Defender for Containers: Vulnerability scanning for ACR images, runtime threat detection
  - Defender for Databases: PostgreSQL threat detection, vulnerability assessments
  - Defender for Key Vault: Unusual access pattern detection
- Trivy: Infrastructure-as-code security scanning during Terraform development and container image vulnerability scanning
- Azure Policy: Enforce compliance (require encryption, private endpoints, TLS versions)

### Environment Configuration

**Environment Strategy**: Terragrunt with shared Terraform module, environment-specific configuration files

**Environments**:
1. **Development (dev)** - baseline environment for development and testing
2. **Staging (staging)** - optional, production-like validation (future)
3. **Production (production)** - mirrors AWS production environment

**Configuration Differences** (Terragrunt `inputs` block):

| Parameter | Dev | Staging | Production |
|-----------|-----|---------|------------|
| `container_cpu` | 0.25 vCPU | 0.5 vCPU | 0.5 vCPU |
| `container_memory` | 0.5 GB | 1.0 GB | 1.0 GB |
| `min_replicas` | 0 (scale to zero) | 1 | 1 |
| `max_replicas` | 2 | 5 | 10 |
| `postgres_sku` | Burstable B1ms | General Purpose D2s_v3 | General Purpose D4s_v3 |
| `postgres_storage_gb` | 32 GB | 64 GB | 128 GB |
| `postgres_ha_enabled` | false | true | true |
| `backup_retention_days` | 7 | 14 | 14 |
| `enable_application_insights` | false | true | true |
| `enable_auto_shutdown` | true (evenings/weekends) | false | false |
| `enable_zone_redundancy` | false | true | true |
| `domain_name` | navigator-dev.cdssandbox.xyz | navigator-staging.cds-snc.ca | valentine.cds-snc.ca |
| `create_google_auth` | false (Azure AD B2C) | false (Azure AD B2C) | true (Google OAuth) |
| `create_azure_ad_b2c` | true | true | false |

**Conditional Resource Creation** (using Terraform `count` expressions in shared module):
- `count = var.create_application_insights ? 1 : 0` - Application Insights for production monitoring
- `count = var.enable_auto_shutdown ? 1 : 0` - Auto-shutdown schedules for dev cost savings
- `count = var.create_google_auth ? 1 : 0` - Google OAuth integration for production
- `count = var.create_azure_ad_b2c ? 1 : 0` - Azure AD B2C for dev/staging authentication

**State Isolation**:
- Terragrunt auto-generates separate Azure Storage Account backends per environment
- Backend configuration:
  - Storage Account: navtfstatedev (dev), navtfstateprod (production)
  - Container: `tfstate`
  - Key: `navigator.terraform.tfstate`
  - Encryption: Enabled (Microsoft-managed keys)
  - State locking: Native Azure Blob Storage lease-based locking
- Environment-specific tags: `Environment=dev|staging|production`, `CostCenter=navigator`, `Project=valentine`

**Deployment Strategy**:
1. Validate changes in dev environment first (terraform plan, apply, manual testing)
2. Promote configuration to staging (production-like validation)
3. Deploy to production (manual approval gate in GitHub Actions)
4. Resource naming: Environment prefixes (nav-dev-*, nav-staging-*, nav-prod-*)
5. GitHub Actions workflows:
   - Dev/Staging: Auto-deploy on merge to main branch (oidc authentication)
   - Production: Deploy only on release publication (manual trigger, require approval)

### Complexity Level

**Baseline Complexity** (Development/User-Testing Environment)

**Purpose**: Initial deployment for development, testing, and pilot usage (50-100 concurrent users)

**Rationale**:
- Use case: Internal Government of Canada tool for threat modeling (not business-critical during development)
- Acceptable downtime: 85% availability target suitable for dev/testing (non-production SLOs)
- Cost optimization: $50-150/month operating cost target requires minimal resource allocation
- Simplicity: Single-zone deployment, smallest SKUs, basic monitoring sufficient for initial deployment

**Architecture Decisions**:
- Single-zone deployment (no zone redundancy)
- Container Apps Consumption plan (serverless, scale to zero)
- PostgreSQL Burstable B1ms SKU (1 vCore, 2 GB RAM)
- No Application Gateway (Container Apps direct ingress acceptable for dev)
- Managed Certificates (free, automatic)
- Basic monitoring (Container Apps default metrics, no Application Insights)
- Auto-shutdown schedules (evenings, weekends to reduce cost)

**Enhanced Complexity** (Staging/Production Environments)

**Purpose**: Production deployment for live user workloads requiring higher availability and performance

**Rationale**:
- Use case: Production threat modeling tool for Government of Canada teams (internal tool, not public-facing)
- Availability requirement: 99.9% target (appropriate for internal tools, not mission-critical)
- Performance: Support 50-100 concurrent users with <2s page load time, <500ms database p95
- Reliability: Automated failover, backups, monitoring for operational excellence

**Architecture Decisions**:
- Zone-redundant deployment (Container Apps and PostgreSQL HA across availability zones)
- PostgreSQL General Purpose D2s_v3+ SKU (2+ vCores, right-sized for workload)
- Auto-scaling enabled (scale out at 70% CPU, scale in at 30%)
- Application Insights for APM and distributed tracing
- Automated backups with 14-day retention, point-in-time restore
- Comprehensive monitoring, alerting, and log analytics
- Optional Application Gateway with WAF for enhanced security (if required by compliance)

**Complexity Progression Path**:
- Start with Baseline for initial deployment (minimize cost, rapid iteration)
- Promote to Enhanced when ready for production workloads (controlled via Terragrunt environment variables)
- No infrastructure code changes required (configuration-driven promotion)

### State Management

**Backend Configuration**: Azure Blob Storage with azurerm backend

**Prerequisites**: This plan assumes the following state management infrastructure already exists:
- Resource Group: `navigator-tfstate-rg` (or equivalent) for Terraform state storage
- Storage Accounts per environment: `navtfstate<env>` (e.g., navtfstatedev, navtfstateprod)
- Storage containers: `tfstate` container in each storage account
- RBAC permissions: Service principals/users have Storage Blob Data Contributor role

**Storage Account Setup** (reference for existing infrastructure):
- Storage Account per environment: `navtfstate<env>` (e.g., navtfstatedev, navtfstateprod)
- Region: Canada Central (co-located with infrastructure resources)
- SKU: Standard LRS (locally redundant, sufficient for state files)
- Container: `tfstate`
- Access tier: Hot (frequent access during development/deployment)
- Public access: Disabled (private state storage)

**State File Configuration**:
```hcl
terraform {
  backend "azurerm" {
    resource_group_name   = "navigator-tfstate-rg"
    storage_account_name  = "navtfstate<env>"  # e.g., navtfstatedev
    container_name        = "tfstate"
    key                   = "navigator.terraform.tfstate"
    use_azuread_auth      = true  # Use Azure AD authentication (no storage access keys)
  }
}
```

**Terragrunt Auto-Generation**:
- Terragrunt generates `backend.tf` automatically from `remote_state` configuration in `terragrunt.hcl`
- Environment-specific state files (no shared state across dev/staging/production)
- References existing state storage infrastructure (does not create storage accounts)

**State Locking**:
- Mechanism: Azure Blob Storage lease-based locking (native feature, no separate lock table needed like DynamoDB)
- Prevents concurrent Terraform operations on same state file
- Automatic lock acquisition/release during terraform plan/apply
- Lock timeout: 15 minutes (configurable)

**Encryption and Security**:
- Encryption at rest: Microsoft-managed keys (platform default)
- Encryption in transit: HTTPS-only access (enforced by storage account policy)
- Access control: Azure RBAC (Storage Blob Data Contributor role for CI/CD service principal)
- Network restrictions: Private endpoint for production (no public internet access to state storage)

**Versioning and Backup**:
- Blob versioning: Enabled (automatic versioning of state file changes)
- Retention: 30-day version retention (allows rollback to previous state within 30 days)
- Soft delete: Enabled (14-day retention for accidental deletion recovery)
- Lifecycle policy: Archive versions older than 30 days to Cool tier (cost optimization)

**Access Control and Auditing**:
- IAM Roles:
  - CI/CD Service Principal: Storage Blob Data Contributor (read/write state files)
  - Developers: Storage Blob Data Reader (read-only, cannot modify state directly)
  - Ops Team: Storage Blob Data Contributor + Owner (full access for emergency recovery)
- Diagnostic settings: Enable logging for state storage access (audit trail)
- Monitor with Azure Monitor: Alert on unusual access patterns (e.g., state file deletions, concurrent access attempts)

**State File Organization**:
- One state file per environment (terraform workspace NOT used, directory-based environments preferred)
- State file naming: `navigator.terraform.tfstate` (consistent across environments)
- Environment isolation: Separate storage accounts per environment for complete isolation
- No shared state across environments (prevents accidental cross-environment impact)

**Disaster Recovery**:
- Backup strategy: Blob versioning provides automatic point-in-time recovery
- Recovery procedure: Restore previous version of state file if corruption detected
- Testing: Periodic validation of state file integrity (`terraform plan` should show no changes)
- Emergency recovery: Manual state reconstruction from live infrastructure if state lost (last resort)

## Project Structure

### Documentation (this infrastructure)

```text
specs/001-navigator-deploy/
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

Following the valentine-terraform AWS reference architecture pattern (Terragrunt + shared module):

```text
terraform/
├── azure/                          # Shared Terraform module (infrastructure definitions)
│   ├── versions.tf                 # Terraform and provider version constraints
│   ├── provider.tf                 # Azure provider configuration
│   ├── variables.tf                # Input variable declarations (all configurable parameters)
│   ├── outputs.tf                  # Output value declarations
│   ├── vnet.tf                     # Virtual Network, subnets, NSGs
│   ├── container-apps.tf           # Container Apps Environment and Navigator app
│   ├── postgresql.tf               # PostgreSQL Flexible Server
│   ├── keyvault.tf                 # Key Vault for secrets management
│   ├── dns.tf                      # Azure DNS zone and records
│   ├── monitoring.tf               # Application Insights, Log Analytics (conditional)
│   ├── identity.tf                 # Managed Identities, RBAC role assignments
│   ├── security.tf                 # Network Security Groups, Private Endpoints
│   ├── storage.tf                  # Storage Account (optional, for user uploads)
│   ├── auth-b2c.tf                 # Azure AD B2C configuration (conditional)
│   ├── auth-google.tf              # Google OAuth configuration (conditional)
│   ├── gh-oidc.tf                  # GitHub OIDC federated credentials
│   └── templates/
│       └── container-env.json      # Container Apps environment variables template
│
└── env/                            # Environment-specific configurations (Terragrunt)
    ├── dev/
    │   ├── terragrunt.hcl          # Dev environment configuration
    │   └── Makefile                # Dev deployment shortcuts
    └── production/
        ├── terragrunt.hcl          # Production environment configuration
        └── Makefile                # Production deployment shortcuts

.github/workflows/
├── terraform-plan.yml              # Terraform plan on pull requests
├── terraform-apply-dev.yml         # Auto-deploy dev on merge to main
└── terraform-apply-prod.yml        # Deploy production on release (manual approval)

.specify/                           # Project management (existing)
├── memory/
│   └── principles.md               # Infrastructure principles (v2.0.0)
└── scripts/
    ├── bash/
    │   ├── setup-plan.sh           # Planning workflow script
    │   └── update-agent-context.sh # Agent context update script
    └── ...

README.md                           # Root project documentation
.gitignore                          # Ignore Terraform state, .tfvars, .terraform/
```

**Structure Decision**: Option 2 (Terraform Infrastructure with Terragrunt orchestration)

**Rationale**:
- Mirrors existing AWS architecture (valentine-terraform repository pattern)
- Shared Terraform module (`terraform/azure/`) enables DRY principles (no code duplication across environments)
- Terragrunt orchestration (`terraform/env/{dev,production}/`) provides environment-specific configuration via `inputs` block
- Service-per-file organization (vnet.tf, container-apps.tf, postgresql.tf) improves maintainability and navigation
- Supports environment promotion via configuration (change Terragrunt inputs, not Terraform code)
- GitHub Actions workflows automate deployment with environment-appropriate controls (auto-deploy dev, manual approval for production)

**File Organization**:
- `versions.tf`: Terraform >= 1.9, azurerm ~> 4.0 version constraints
- `provider.tf`: Azure provider with subscription_id, features {} block
- Service-specific files: Group related resources (vnet.tf contains VNet, subnets, NSGs; container-apps.tf contains environment and app)
- Conditional resources: Use `count = var.create_<feature> ? 1 : 0` pattern for environment-specific features
- Templates: Container environment variables, startup scripts if needed

**Terragrunt Configuration**:
- `source = "../..//azure"`: Reference shared module from environment directory
- `inputs {}`: Environment-specific parameters (SKUs, scaling, feature flags, domain names)
- `remote_state`: Auto-generate Azure Storage backend configuration
- `dependencies`: Manage deployment order if needed (network before compute)

**Deployment Workflow**:
1. Developer changes shared module (`terraform/azure/*.tf`)
2. Open pull request → GitHub Actions runs `terraform plan` for dev environment (show preview)
3. Merge to main → Auto-deploy to dev environment (validate changes)
4. Create release → Manual approval workflow deploys to production (controlled promotion)
5. Terragrunt ensures consistent infrastructure pattern across environments

## Complexity Tracking

> No principles violations requiring justification. This plan adheres to all Navigator Azure Infrastructure Principles (v2.0.0).

## Implementation Scope Summary

### In Scope (This Plan)
- Azure Container Apps environment and Navigator application
- Azure Database for PostgreSQL Flexible Server
- Virtual Network, subnets, and Network Security Groups
- Azure Key Vault for secrets management
- Managed Identities and RBAC role assignments
- DNS configuration (Azure DNS zone)
- Monitoring and logging (Application Insights, Log Analytics)
- Authentication configuration (Azure AD B2C or Google OAuth)
- GitHub OIDC integration for CI/CD
- Optional: Azure Container Registry, Storage Account

### Out of Scope (Prerequisites)
- Azure resource groups (must exist before implementation)
- Terraform state storage infrastructure (Storage Accounts, containers)
- RBAC permissions for state storage access
- Azure subscription setup and billing configuration

### Deployment Prerequisites Checklist

Before running `/iac.implement`, verify:
- [ ] Resource groups exist: `navigator-dev-rg`, `navigator-prod-rg` (or equivalent)
- [ ] State storage exists: `navigator-tfstate-rg` resource group
- [ ] State storage accounts exist: `navtfstatedev`, `navtfstateprod`
- [ ] State containers exist: `tfstate` container in each storage account
- [ ] RBAC configured: Service principals/users have appropriate Storage Blob Data roles
- [ ] Azure CLI authenticated with appropriate subscription
- [ ] Terraform 1.9+ installed
- [ ] Terragrunt installed (if using Terragrunt orchestration)

If any prerequisites are missing, they must be created manually before proceeding with infrastructure implementation.
