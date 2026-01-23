# Architecture Plan: Navigator Azure Deployment

**Branch**: `001-navigator-deploy` | **Date**: January 14, 2026 (Updated: January 20, 2026) | **Spec**: [spec.md](./spec.md)
**Input**: Infrastructure specification from `/specs/001-navigator-deploy/spec.md`

**Note**: This plan has been enriched with deep research. See [research.md](./research.md) for Well-Architected Framework analysis and best practices, [architecture.md](./architecture.md) for detailed infrastructure design, [quickstart.md](./quickstart.md) for step-by-step provisioning guide, and [avm-reevaluation.md](./avm-reevaluation.md) for comprehensive Azure Verified Modules analysis.

## Summary

Deploy the Navigator threat modeling application (Elixir/Phoenix) to Azure with minimal infrastructure suitable for 50-100 concurrent users. The architecture uses Azure Container Apps for serverless container hosting, Azure Database for PostgreSQL Flexible Server for persistence, and Container Apps secrets for configuration management. This design mirrors the existing AWS architecture (ECS Fargate + Aurora PostgreSQL) while leveraging Azure-managed services to minimize operational overhead. Initial deployment targets development/staging environments with the ability to scale to production through configuration-driven environment promotion using Terragrunt orchestration.

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
  - Deployment identities: Storage Blob Data Contributor role
  - Developers: Storage Blob Data Reader role (read-only)
  - Ops team: Storage Blob Data Contributor role

**Out of Scope**: This plan does NOT include creation of the above prerequisite infrastructure. If these do not exist, they must be provisioned manually or via separate bootstrap process before proceeding with implementation.

## Technical Context

**Cloud Provider**: Microsoft Azure  
**IaC Tool**: Terraform 1.9+ (latest stable as of January 2026)  
**Provider Versions**:

- azurerm ~> 4.0 (latest stable, required for Container Apps native support)
- azapi ~> 2.0 (required for session affinity - not yet available in azurerm provider)
  **Module Versions**: Direct resources only - no modules used in this implementation (follows "Prefer Resource Simplicity" principle v3.0.0). See [avm-reevaluation.md](./avm-reevaluation.md) for comprehensive analysis of Azure Verified Modules decision.  
  **State Backend**: Azure Blob Storage with state locking (azurerm backend)  
  **Environment Strategy**: Terragrunt with directory-based environments (terraform/env/{dev,staging,production}) referencing shared module (terraform/azure/)  
  **Secrets Management**: Container Apps secrets (direct injection from Terraform state)  
  **Deployment Method**: Manual deployment using Terragrunt (CI/CD out of scope, may be added later)  
  **Testing**: terraform validate, terraform plan at tier boundaries  
  **Security Scanning**: Trivy for infrastructure security scanning  
  **Cost Estimation**: Azure Cost Management + Infracost (optional)  
  **Target Environments**: dev (baseline), staging (optional), production  
  **Compliance**: Government of Canada baseline security controls

## Principles Check

This plan aligns with Navigator Azure Infrastructure Principles (v3.0.0) as follows:

### Cloud Architecture Principles

**1. Prefer Managed Services** ✅ (consolidated from "Favor Managed Services" + "Enforce Cloud Service Hierarchy" in v3.0.0)

- Uses Azure Container Apps (fully managed serverless containers with built-in secrets management)
- Uses Azure Database for PostgreSQL Flexible Server (managed database with automated backups, patching)
- Uses Azure Monitor + Application Insights (managed observability)
- Avoids self-managed VMs, container orchestration clusters, or database installations

**2. Design for Simplicity** ✅

- Baseline (Dev): Single-zone deployment, Basic/Burstable tiers, minimal networking, direct Container Apps secrets
- Enhanced (Production): Zone-redundant deployment, Standard/General Purpose tiers, essential features only
- No multi-region complexity, no service mesh, no unnecessary abstractions

**3. Design for Reliability and Resilience** ✅

- Baseline (Dev): Single-zone acceptable, basic health checks, deployment slots for updates
- Enhanced (Production): Zone-redundant Container Apps and PostgreSQL, auto-scaling at 70% CPU, automated backups (7-14 days retention)
- Target availability: 99.9% for internal tools (appropriate for use case)

**4. Optimize for Cost** ✅

- Baseline (Dev): Smallest SKUs (Container Apps Consumption plan, PostgreSQL Burstable B1ms), auto-shutdown schedules, direct secrets management (no additional service costs)
- Enhanced (Production): Right-sized Standard/General Purpose tiers, Azure reservations for predictable workloads
- Monthly operating cost target: $50-150/month (dev), scalable to production needs

### IaC Code Principles

**1. Prefer Resource Simplicity** ✅ (Principles v3.0.0)

- Uses direct azurerm resource blocks exclusively (azurerm_container_app, azurerm_postgresql_flexible_server, azurerm_virtual_network)
- No modules used in this implementation - all resources defined directly for maximum transparency
- **Azure Verified Modules (AVM) Re-Evaluation** (January 16, 2026): Comprehensive analysis confirmed direct resources remain optimal for Navigator's scale. See [avm-reevaluation.md](./avm-reevaluation.md) for:
  - Component-by-component cost-benefit analysis (VNet, Container Apps, PostgreSQL, ACR)
  - Quantitative metrics: Direct resources save 12-23 hours initial development, 2-3x faster debugging, 4-8x faster upgrades
  - Pre-release risk assessment: ALL AVM modules < 1.0.0 with breaking changes expected
  - GC compliance audit trail: Direct resources provide better security transparency
  - Production deployment scenarios validating direct resource approach
- Baseline environments use direct resources exclusively for maximum transparency and learning

**2. Automate Validation** ✅

- terraform validate after each file modification
- terraform plan at tier boundaries (network complete, compute complete)
- Trivy for security scanning (exposed storage, missing encryption, overly permissive network rules)
- terraform fmt for code consistency

**3. Manage Secrets Securely** ✅

- Auto-generated secrets created using Terraform `random_password` resource (PostgreSQL passwords, SECRET_KEY_BASE)
- Injected secrets passed as Terraform input variables during manual deployment
- Container Apps secrets store all sensitive configuration (encrypted by Azure platform)
- Uses Azure Managed Identities for Container Apps to access Azure resources (no stored credentials)
- Never commits secrets in code or .tfvars files (gitignored)

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
- Session Affinity: Enable session affinity for WebSocket persistence (real-time collaboration requires sticky sessions). Implemented using azapi provider via azapi_resource_action (session affinity not yet available in azurerm_container_app resource)
- Startup Command: Container runs default Phoenix startup sequence (database migrations on startup; migration failures prevent container start, requiring rollback via Container Apps revision management)

**Container Registry** (Optional, recommend for production)

- Azure Container Registry (ACR): Basic SKU (dev), Standard SKU (production)
- Geo-replication: Disabled (single region sufficient)
- Image retention policy: 30 days for untagged manifests
- Vulnerability scanning: Microsoft Defender for Cloud integration

### Data Storage

**Azure Database for PostgreSQL Flexible Server**

- Engine Version: PostgreSQL 14.x (aligns with AWS Aurora PostgreSQL 14.15 equivalent from reference architecture)
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
  - Connection string constructed from auto-generated credentials (stored in Terraform state)
  - Container Apps retrieves credentials from Container Apps secrets
  - SSL/TLS enforcement: Optional (can be disabled to match AWS reference architecture)
    - Network security: Database isolated via private endpoint (no internet access), so TLS provides defense-in-depth but not required for basic security
- Performance:
  - Connection pooling: pgBouncer (built-in PostgreSQL Flexible Server feature, similar to AWS RDS Proxy concept)
  - Query performance insights: Enabled for production troubleshooting

**Azure Storage Account** (Optional, if needed for user uploads)

- SKU: Standard LRS (locally redundant storage, baseline) or Standard ZRS (zone-redundant, enhanced)
- Blob container for user-uploaded threat models or attachments
- Access tier: Hot (for frequently accessed data)
- Lifecycle management: Move to Cool tier after 90 days, archive after 180 days
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
- Service Endpoints: Microsoft.Storage (if using Storage Account for user uploads)

**Network Security Groups (NSGs)**

- Container Apps NSG:
  - Inbound: Allow HTTPS (443) from internet (public web application - unrestricted source is intentional and documented)
  - Outbound: Segregated by destination for least-privilege access:
    - Azure services: Allow 443 to CognitiveServices, AzureMonitor, AzureContainerRegistry (service tags)
    - Internet (conditional): Allow 443 to internet for OpenAI API integration (controlled by `enable_outbound_internet` variable; default: true for dev/staging, configurable for production based on security policy)
    - PostgreSQL: Allow 5432 to PostgreSQL subnet
- PostgreSQL NSG:
  - Inbound: Allow 5432 from Container Apps subnet only
  - Outbound: Deny all (database does not initiate outbound connections)

**Security Compliance**:

- Trivy security scan findings (AVD-AZU-0047, AVD-AZU-0051) suppressed with documented business justifications
- Inbound HTTPS from internet is required for public web application accessibility
- Outbound traffic uses service tags for Azure-managed services (recommended security practice)
- External API access (OpenAI) configurable via variable for environment-specific policies

**DNS and TLS**

- DNS Hosting: Azure DNS zone for custom domain (navigator-dev.demo.focisolutions.com, navigator.demo.focisolutions.com)
  - **Implementation**: DNS zones created by Terraform as part of infrastructure deployment
  - Domain registrar NS records must point to Azure DNS name servers (manual post-deployment configuration step)
- A Record: Points to Container Apps environment default domain or Application Gateway public IP
- TLS Certificates:
  - Type: Container Apps Managed Certificates (free, automatic renewal via DigiCert)
  - Implementation: 4-step workflow using hybrid azapi + azurerm providers
  - Validation: HTTP validation for apex domains, automated via Azure DNS
  - Provisioning: 10-20 minutes for certificate issuance and binding
  - Enforcement: HTTPS-only ingress, HTTP redirects to HTTPS
  - Details: See architecture.md Section 7 and research.md for implementation workflow

**Outbound Connectivity**

- Container Apps: VNet integration allows outbound internet access for OpenAI API calls, package downloads
- NAT Gateway: Optional for production (provides consistent outbound IP for allowlisting)
- Service Tags: Use Azure service tags for Azure OpenAI access (if using Azure OpenAI instead of OpenAI API)

### Security

**Network Security**

- Network Security Groups (NSGs):
  - Container Apps NSG:
    - Inbound: 443 from internet (unrestricted for public web application - intentional design decision, documented in terraform/azure/security.tf)
    - Outbound: Segregated rule set using service tags for Azure services (CognitiveServices, AzureMonitor, AzureContainerRegistry) and conditional internet access (controlled by `enable_outbound_internet` variable)
  - PostgreSQL NSG: Inbound 5432 from Container Apps subnet only, outbound deny all
  - Security Scanning: Trivy findings AVD-AZU-0047 (unrestricted inbound) and AVD-AZU-0051 (unrestricted outbound) suppressed with business justifications in IaC code
- Private Endpoints:
  - PostgreSQL: Private endpoint in VNet (no public internet access)
  - Storage Account: Private endpoint for blob access (production, conditional)
- TLS Enforcement:
  - Container Apps ingress: TLS 1.2+ only
  - PostgreSQL connections: Optional TLS (configurable via variable, disabled by default to match AWS reference architecture)
    - Connection isolated via private endpoint in VNet (no public internet exposure)
    - TLS provides additional encryption layer but AWS reference uses plain TCP

**Identity and Access Management (IAM)**

- Managed Identities:
  - Container Apps: System-assigned managed identity
  - ACR Integration: Managed identity for pulling container images (AcrPull role)
- Role-Based Access Control (RBAC):
  - Container Apps Contributor: Operators deploy app revisions, view logs
  - PostgreSQL Administrator: Database schema management
  - PostgreSQL User: Application runtime access (connection string)
  - Terraform State Storage: Storage Blob Data Contributor (operators read/write state during deployment)
- Deployment Identity:
  - Manual deployment using Azure CLI authenticated user or service principal
  - Scoped to resource group with least-privilege permissions
  - No CI/CD automation (out of current scope, may be added later)

**Secrets Management**

**Strategy**: Direct Container Apps secrets (no Key Vault required)

**Secret Categories**:

1. **Auto-Generated Secrets** (created by Terraform during deployment):

   - PostgreSQL admin password (`random_password` resource)
   - PostgreSQL application user password (`random_password` resource)
   - Phoenix SECRET_KEY_BASE (generated cryptographically via `random_password`)
   - Storage: Terraform state file (encrypted at rest in Azure Storage Account)

2. **Injected Secrets** (provided at deployment time):
   - Azure OpenAI API key and endpoint (if using Azure OpenAI, conditional)
   - Google OAuth client ID and secret (if using Google auth, conditional)
   - Microsoft OAuth credentials (if using Azure AD B2C, conditional)
   - Storage: Passed as Terraform input variables during manual deployment

**Container Apps Secret Injection**:

- Auto-generated secrets: Retrieved from Terraform state, injected into Container Apps secrets
- Injected secrets: Passed as Terraform input variables, stored as Container Apps secrets
- Environment variables: Reference Container Apps secrets (e.g., `secretRef: "db-conn-str"`)
- Secret rotation: Update Terraform variables → re-run `terragrunt apply` → Container Apps restarts with new secrets
- Container Apps secrets: Encrypted by Azure platform, accessible only to running app instances

**Security Considerations**:

- State backend: Encrypted at rest with Microsoft-managed keys, RBAC-controlled access (Storage Blob Data Contributor)
- Container Apps secrets: Platform-encrypted, isolated per app instance
- Future enhancement: Terraform 1.10+ ephemeral values will prevent secrets appearing in plan output
- Terraform state access: Limited to deployment identities, audit logged via Azure Monitor
- No secrets in code: All sensitive values parameterized as Terraform variables
- State file security: Stored in Azure Blob Storage with versioning, soft delete, and private network access (production)

**Data Encryption**

- Encryption at Rest:
  - PostgreSQL: Automatic encryption with Microsoft-managed keys (platform default)
  - Storage Account: AES-256 encryption with Microsoft-managed keys
  - Terraform State: Encryption enabled on Azure Storage Account (Microsoft-managed keys)
  - Container Apps secrets: Platform-encrypted by Azure (AES-256)
- Encryption in Transit:
  - Internet-facing traffic: TLS 1.2+ enforced (Container Apps ingress, Storage Account access)
  - PostgreSQL connections: TLS optional (configurable, disabled by default to match AWS reference)
    - Network isolation provides primary security control (private endpoint, NSG restrictions)
    - TLS provides defense-in-depth encryption layer when enabled

**Security Scanning and Monitoring**

- Microsoft Defender for Cloud (post-deployment manual configuration):
  - Defender for Containers: Vulnerability scanning for ACR images, runtime threat detection
  - Defender for Databases: PostgreSQL threat detection, vulnerability assessments
- Trivy: Infrastructure-as-code security scanning during Terraform development and container image vulnerability scanning
- Azure Policy: Enforce compliance (require encryption, private endpoints, TLS versions)

### Environment Configuration

**Environment Strategy**: Terragrunt with shared Terraform module, environment-specific configuration files

**Environments**:

1. **Development (dev)** - baseline environment for development and testing
2. **Staging (staging)** - optional, production-like validation (future)
3. **Production (production)** - mirrors AWS production environment

**Configuration Differences** (Terragrunt `inputs` block):

| Parameter                     | Dev                                  | Staging                      | Production                       |
| ----------------------------- | ------------------------------------ | ---------------------------- | -------------------------------- |
| `container_cpu`               | 0.25 vCPU                            | 0.5 vCPU                     | 0.5 vCPU                         |
| `container_memory`            | 0.5 GB                               | 1.0 GB                       | 1.0 GB                           |
| `min_replicas`                | 0 (scale to zero)                    | 1                            | 1                                |
| `max_replicas`                | 2                                    | 5                            | 10                               |
| `postgres_sku`                | Burstable B1ms                       | General Purpose D2s_v3       | General Purpose D4s_v3           |
| `postgres_storage_gb`         | 32 GB                                | 64 GB                        | 128 GB                           |
| `postgres_ha_enabled`         | false                                | true                         | true                             |
| `postgres_require_ssl`        | false                                | false                        | true (optional)                  |
| `backup_retention_days`       | 7                                    | 14                           | 14                               |
| `enable_application_insights` | false                                | true                         | true                             |
| `enable_auto_shutdown`        | true (evenings/weekends)             | false                        | false                            |
| `enable_zone_redundancy`      | false                                | true                         | true                             |
| `domain_name`                 | navigator-dev.demo.focisolutions.com | navigator-staging.cds-snc.ca | navigator.demo.focisolutions.com |
| `enable_outbound_internet`    | true                                 | true                         | true                             |
| `create_google_auth`          | false (Azure AD B2C)                 | false (Azure AD B2C)         | true (Google OAuth)              |
| `create_azure_ad_b2c`         | true                                 | true                         | false                            |

**Conditional Resource Creation** (using Terraform `count` expressions in shared module):

- `count = var.enable_application_insights ? 1 : 0` - Application Insights for production monitoring
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
3. Deploy to production (manual deployment with explicit approval)
4. Resource naming: Environment prefixes (nav-dev-_, nav-staging-_, nav-prod-)

**Manual Deployment Commands**:

```bash
# Development environment
cd terraform/env/dev
terragrunt plan    # Review changes before applying
terragrunt apply   # Deploy infrastructure

# Production environment
cd terraform/env/production
terragrunt plan    # Review production changes
terragrunt apply   # Deploy to production (requires explicit approval)
```

**Deployment Prerequisites**:

- Azure CLI authenticated with appropriate subscription
- Terraform and Terragrunt installed locally
- Access to Terraform state storage (Storage Blob Data Contributor role)
- Injected secrets prepared (OAuth credentials, API keys if applicable)

**Note**: CI/CD automation (GitHub Actions, Azure DevOps) is out of scope for initial implementation. Manual deployment provides explicit control and approval workflow. CI/CD can be added as future enhancement.

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
- Direct Container Apps secrets (no Key Vault overhead)

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
- Access control: Azure RBAC (Storage Blob Data Contributor role for deployment identities)
- Network restrictions: Private endpoint for production (no public internet access to state storage)

**Versioning and Backup**:

- Blob versioning: Enabled (automatic versioning of state file changes)
- Retention: 30-day version retention (allows rollback to previous state within 30 days)
- Soft delete: Enabled (14-day retention for accidental deletion recovery)
- Lifecycle policy: Archive versions older than 30 days to Cool tier (cost optimization)

**Access Control and Auditing**:

- IAM Roles:
  - Deployment Identities: Storage Blob Data Contributor (read/write state files)
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
│   # Enrichment artifacts (completed via /iac.enrichplan):
├── research.md          # Deep research: Well-Architected Framework, Azure Verified Modules, best practices
├── architecture.md      # Detailed infrastructure architecture design with component specifications
└── quickstart.md        # Step-by-step provisioning guide for dev and production environments
```

### Source Code (repository root)

Following the valentine-terraform AWS reference architecture pattern (Terragrunt + shared module):

```text
terraform/
├── azure/                          # Shared Terraform module (infrastructure definitions)
│   ├── versions.tf                 # Terraform and provider version constraints
│   ├── provider.tf                 # Azure provider configuration
│   ├── variables.tf                # Input variable declarations
│   ├── outputs.tf                  # Output value declarations
│   ├── vnet.tf                     # Virtual Network, subnets, NSGs
│   ├── container-apps.tf           # Container Apps Environment and Navigator app
│   ├── postgresql.tf               # PostgreSQL Flexible Server (includes random_password for credentials)
│   ├── dns.tf                      # Azure DNS zone and records
│   ├── monitoring.tf               # Application Insights, Log Analytics (conditional)
│   ├── identity.tf                 # Managed Identities, RBAC role assignments
│   ├── security.tf                 # Network Security Groups, Private Endpoints
│   ├── storage.tf                  # Storage Account (optional, for user uploads)
│   ├── auth-b2c.tf                 # Azure AD B2C configuration (conditional)
│   ├── auth-google.tf              # Google OAuth configuration (conditional)
│   ├── auth-openai.tf              # Azure OpenAI Cognitive Services (conditional)
│   └── templates/
│       └── container-env.json      # Container Apps environment variables template
│
└── env/                            # Environment-specific configurations (Terragrunt)
    ├── dev/
    │   └── terragrunt.hcl          # Dev environment configuration
    └── production/
        └── terragrunt.hcl          # Production environment configuration

.specify/                           # Project management (existing)
├── memory/
│   └── principles.md               # Infrastructure principles (v3.0.0)
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
- Manual deployment workflow provides explicit control and approval for infrastructure changes

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

**Manual Deployment Workflow**:

1. Developer changes shared module (`terraform/azure/*.tf`)
2. Test in dev environment: `cd terraform/env/dev && terragrunt plan && terragrunt apply`
3. Validate changes work as expected in dev
4. Deploy to production: `cd terraform/env/production && terragrunt plan && terragrunt apply`
5. Terragrunt ensures consistent infrastructure pattern across environments

**Note**: CI/CD automation can be added later as an enhancement (e.g., GitHub Actions for automated terraform plan on PRs, automated apply on merge).

## Complexity Tracking

> No principles violations requiring justification. This plan adheres to all Navigator Azure Infrastructure Principles (v3.0.0).

## Implementation Scope Summary

### In Scope (This Plan)

- Azure Container Apps environment and Navigator application
- Azure Database for PostgreSQL Flexible Server
- Virtual Network, subnets, and Network Security Groups
- Container Apps secrets for sensitive configuration (no Key Vault required)
- Managed Identities and RBAC role assignments
- DNS configuration (Azure DNS zone)
- Monitoring and logging (Application Insights, Log Analytics)
- Authentication configuration (Azure AD B2C or Google OAuth)
- Manual deployment workflow using Terragrunt
- Optional: Azure Container Registry, Storage Account

### Out of Scope (Prerequisites)

- Azure resource groups (must exist before implementation)
- Terraform state storage infrastructure (Storage Accounts, containers)
- RBAC permissions for state storage access
- Azure subscription setup and billing configuration

### Out of Scope (Future Enhancements)

- CI/CD pipeline automation (GitHub Actions, Azure DevOps)
- Automated deployment workflows
- GitHub OIDC integration for service principals
- Multi-region deployment or disaster recovery
- Advanced monitoring/observability beyond Application Insights

### Deployment Prerequisites Checklist

Before running `/iac.implement`, verify:

- [ ] Resource groups exist: `navigator-dev-rg`, `navigator-prod-rg` (or equivalent)
- [ ] State storage exists: `navigator-tfstate-rg` resource group
- [ ] State storage accounts exist: `navtfstatedev`, `navtfstateprod`
- [ ] State containers exist: `tfstate` container in each storage account
- [ ] RBAC configured: Deployment identities have appropriate Storage Blob Data roles
- [ ] Azure CLI authenticated with appropriate subscription
- [ ] Terraform 1.9+ installed
- [ ] Terragrunt installed (if using Terragrunt orchestration)
- [ ] Injected secrets prepared (OAuth credentials, API keys if applicable)

If any prerequisites are missing, they must be created manually before proceeding with infrastructure implementation.
