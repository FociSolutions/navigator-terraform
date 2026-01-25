# Architecture Plan: Internal Container Apps with Reverse Proxy

**Branch**: `002-internal-ca` | **Date**: 2026-01-25 | **Spec**: [spec.md](./spec.md)
**Input**: Infrastructure specification from `/specs/002-internal-ca/spec.md`

**Note**: This template is filled in by the `/iac.plan` command. For deep research, module specs, and quickstart guide, run `/iac.enrichplan` after planning.

## Summary

This plan implements a defense-in-depth security architecture for the Navigator application by converting the existing publicly exposed Azure Container Apps deployment to an internal-only configuration with external traffic routed through Azure Application Gateway. The Application Gateway will serve as a reverse proxy providing SSL/TLS termination, Web Application Firewall capabilities, centralized traffic management, and WebSocket support for Phoenix LiveView real-time features. This architecture eliminates direct internet exposure of the container application while maintaining public accessibility through a managed, secure entry point.

## Technical Context

**Cloud Provider**: Microsoft Azure  
**IaC Tool**: Terraform 1.8+ (recommended: upgrade to 1.9+ for production)  
**Provider Versions**:
- azurerm (hashicorp/azurerm) ~> 4.0 (stable: 4.58.0 - recommended: >= 4.58, < 5.0)
- azapi (Azure/azapi) ~> 2.0 (for session affinity configuration)
- random (hashicorp/random) ~> 3.0

**Module Versions**:
- Azure/avm-res-network-applicationgateway/azurerm = 0.4.3 (Azure Verified Module - recommended for Application Gateway)

**Curated Modules**: Azure Verified Modules (AVM) - Microsoft-maintained, production-ready modules with comprehensive testing  
**State Backend**: Azure Blob Storage with state locking (managed by Terragrunt)  
**Environment Strategy**: Terragrunt-based configuration with environment-specific .hcl files (dev, production)  
**Testing**: terraform validate, terraform test  
**Security Scanning**: trivy config terraform/ (REQUIRED - no HIGH/CRITICAL findings)  
**Cost Estimation**: Azure Pricing Calculator  
**Target Environments**: dev, production (no staging in current setup)  
**Compliance**: Government of Canada security controls (ITSG-33 alignment), TLS 1.2+ requirement, defense-in-depth architecture

## Principles Check

### Architecture Principles Alignment

**✅ Prefer Managed Services**
- Azure Application Gateway is a fully managed PaaS service providing automated patching, built-in availability, and compliance certifications
- Avoids self-managed reverse proxy solutions (NGINX on VMs, custom load balancers)
- Leverages managed WAF capabilities integrated with Application Gateway
- Baseline (dev): Standard_v2 SKU with minimal WAF configuration
- Enhanced (production): Standard_v2 SKU with zone redundancy, OWASP CRS WAF rules, auto-scaling

**✅ Design for Simplicity**
- Single Application Gateway instance per environment (no multi-region complexity)
- Direct backend pool configuration using Container Apps internal FQDN
- Minimal routing rules (single backend, single frontend)
- Baseline (dev): Single-instance gateway, basic health probes, no WAF enforcement
- Enhanced (production): Zone-redundant gateway with auto-scaling, WAF detection mode initially

**✅ Design for Reliability and Resilience**
- Application Gateway v2 provides built-in zone redundancy capability for production
- Health probes ensure traffic only routes to healthy container instances
- Session affinity (sticky sessions) maintains WebSocket connection stability
- Zero-downtime deployment: Container Apps blue-green deployment preserves existing ingress during gateway setup
- Baseline (dev): Single-zone gateway, basic health checks, manual failover acceptable
- Enhanced (production): Zone-redundant gateway (3 availability zones), automated failover, comprehensive health monitoring

**✅ Optimize for Cost**
- Dev environment: Standard_v2 tier with minimum capacity units (2), no auto-scaling, no reserved capacity
- Production: Standard_v2 tier with auto-scaling (2-10 capacity units), evaluate reserved capacity after 30-day usage baseline
- WAF starts in detection mode (no additional compute cost) before enabling prevention mode
- No CDN/Front Door layer (Application Gateway sufficient for internal tool requirements)
- Baseline (dev): ~$150/month additional cost (Standard_v2, 2 capacity units)
- Enhanced (production): ~$300-500/month (zone-redundant, auto-scaling, WAF enabled)

### IaC Code Principles Alignment

**✅ Prefer Resource Simplicity**
- Direct `azurerm_application_gateway` resource blocks for maximum transparency
- Azure Verified Module considered but direct resources preferred for:
  - Clear configuration visibility for security reviews
  - Simplified debugging and troubleshooting
  - Reduced abstraction layers (single resource vs module wrapper)
- Module evaluation: AVM module adds 500+ lines of abstraction; direct resource ~150 lines
- Decision: Use direct resources in baseline implementation; evaluate AVM for enhanced production if complexity grows

**✅ Automate Validation and Deployment**
- `terraform validate` and `terraform fmt -check` required before commit
- `trivy config terraform/` security scanning gate (no HIGH/CRITICAL findings)
- Terragrunt plan generation on pull requests for peer review
- Lifecycle controls: `prevent_destroy` on production Application Gateway
- Deployment strategy: Dev first, validate WebSocket/session affinity, then production
- CI/CD: Manual approval required for production gateway changes

**✅ Manage Secrets Securely**
- No hardcoded credentials in Application Gateway configuration
- SSL certificates managed via Azure Key Vault integration or Azure-managed certificates
- Backend authentication (if required) uses managed identity for Container Apps
- WAF logs contain no sensitive data (URL/headers only, no request bodies)
- No secrets committed to version control (SSL certs, API keys excluded via .gitignore)

### Complexity Tracking

No principle violations requiring justification. All decisions align with baseline (dev) and enhanced (production) progressive complexity model.

## Infrastructure Architecture

<!--
  **CRITICAL TRANSITION POINT**: This is where generic requirements become cloud-specific.

  The spec.md uses ONLY generic infrastructure terms (e.g., "managed database", "object storage").
  THIS file (plan.md) translates them to cloud-specific services (e.g., "RDS PostgreSQL", "S3").

  Translation Examples:
  - spec.md: "managed relational database" → plan.md: "AWS RDS PostgreSQL 15.x" or "IBM Cloud Databases for PostgreSQL 15.x"
  - spec.md: "object storage" → plan.md: "S3 bucket with versioning" or "Cloud Object Storage bucket"
  - spec.md: "serverless compute" → plan.md: "Lambda functions (Node.js 18)" or "Code Engine applications"
  - spec.md: "container orchestration" → plan.md: "EKS cluster v1.28" or "IBM Cloud Kubernetes Service"
  - spec.md: "load balancer" → plan.md: "Application Load Balancer" or "VPC Load Balancer"
  - spec.md: "virtual private network" → plan.md: "AWS VPC" or "IBM Cloud VPC"

  During /iac.implement, AI agents will read this section to generate IaC files.
-->

### Compute Resources

**Azure Application Gateway (Reverse Proxy)**

**SKU Configuration:**
- **Dev**: Standard_v2 tier, 2 capacity units (fixed), single availability zone
- **Production**: Standard_v2 tier, 2-10 capacity units (auto-scaling), zone-redundant (zones 1,2,3)

**Frontend Configuration:**
- Public IP address: Standard SKU, static allocation, zone-redundant (production only)
- HTTPS listener on port 443 (TLS 1.2 minimum version enforced)
- HTTP listener on port 80 with redirect rule to HTTPS
- Custom domain support via SSL certificate from Azure Key Vault or Azure-managed certificate

**Backend Pool:**
- Target: Container App internal FQDN (`nav-{env}-cae.{region}.azurecontainerapps.io`)
- Protocol: HTTPS (backend uses TLS even for internal traffic)
- Port: 443 (Container Apps internal ingress standard port)

**Health Probe:**
- Protocol: HTTPS
- Path: `/` (existing Container App health check endpoint)
- Interval: 30 seconds
- Timeout: 30 seconds
- Unhealthy threshold: 3 consecutive failures
- Host header: Matches backend FQDN to pass Container Apps routing

**Session Affinity:**
- Cookie-based affinity enabled (required for Phoenix LiveView WebSocket connections)
- Cookie name: `ApplicationGatewayAffinity` (Azure default)
- Cookie lifetime: Session-based (expires when browser closes)

**Routing Rules:**
- Single path-based rule: `/*` → backend pool (all traffic to Container App)
- No complex routing (A/B testing, canary deployment out of scope)

**WebSocket Support:**
- Native WebSocket support in Application Gateway v2 (no additional configuration required)
- HTTP upgrade headers (`Connection: Upgrade`, `Upgrade: websocket`) passed through automatically
- Session affinity ensures WebSocket connections maintain server affinity

**Auto-scaling (Production only):**
- Minimum capacity: 2 units
- Maximum capacity: 10 units
- Scaling metric: Average compute units > 75% or Average capacity units > 60%

**Azure Container Apps (Backend) - MODIFIED CONFIGURATION:**
- **CRITICAL CHANGE**: Ingress `external_enabled` changed from `true` to `false`
- Internal ingress only - no public endpoint
- Internal FQDN: `nav-{env}.internal.{region}.azurecontainerapps.io`
- Port: 4000 (unchanged - Application Gateway backend pool targets port 443, Container Apps handles TLS termination internally)
- Existing scaling policies, health probes, session affinity remain unchanged
- No changes to container image, environment variables, or application code

### Data Storage

**No changes required** - existing data storage infrastructure remains unchanged:

**PostgreSQL Database:**
- Azure Database for PostgreSQL Flexible Server
- Private endpoint connectivity via VNet integration
- Connection from Container Apps via internal networking (unchanged)
- Backup retention: 30 days (dev), 90 days (production)

**Azure Storage Account:**
- General Purpose v2 storage for static assets (if applicable)
- Private endpoint for secure access (existing configuration)
- No changes required for Application Gateway integration

**Application Gateway Logging/Diagnostics:**
- Diagnostic logs sent to existing Log Analytics Workspace (nav-{env}-law)
- Metrics: Request count, response time, backend health status, failed requests
- WAF logs: Detection/prevention events, rule match details (when WAF enabled)
- Access logs: Client IP, request URL, response status, latency
- Retention aligned with Container Apps logs (30 days dev, 90 days production)

### Networking

**Existing VNet Configuration (unchanged):**
- VNet: nav-{env}-vnet
- Address space: 10.0.0.0/16
- Location: Canada Central (or configured region)

**NEW: Application Gateway Subnet**
- Subnet name: nav-{env}-agw-snet
- Address prefix: 10.0.3.0/24 (already provisioned in existing infrastructure - see vnet.tf:59-66)
- **CRITICAL**: Application Gateway subnet must NOT have Network Security Group attached (Azure platform limitation)
- Service endpoints: Microsoft.Storage (for diagnostic logs)
- Capacity: /24 provides 251 usable IPs (sufficient for auto-scaling up to 10 capacity units)

**Container Apps Subnet (EXISTING - modified ingress only):**
- Subnet name: nav-{env}-ca-snet
- Address prefix: 10.0.1.0/24 (existing)
- Delegation: Microsoft.App/environments (unchanged)
- Network Security Group: nav-{env}-ca-nsg (MODIFIED - see Security section)

**PostgreSQL Subnet (no changes):**
- Subnet name: nav-{env}-db-snet
- Address prefix: 10.0.2.0/24 (existing)
- Network Security Group: nav-{env}-db-nsg (unchanged)

**Public IP Address (NEW - Application Gateway frontend):**
- Name: nav-{env}-agw-pip
- SKU: Standard (required for zone redundancy)
- Allocation: Static
- Zones: ["1","2","3"] (production only - zone-redundant)
- DNS label: nav-{env}-gateway (optional - provides {label}.{region}.cloudapp.azure.com FQDN)

**Custom Domain Configuration (if applicable):**
- DNS A record: {domain} → Application Gateway public IP
- SSL certificate: Azure Key Vault reference or Azure-managed certificate
- SNI (Server Name Indication) enabled for multi-domain support (future enhancement)

**Traffic Flow:**
1. Internet → Application Gateway public IP (10.0.3.x, public IP)
2. Application Gateway → Container Apps internal endpoint (10.0.1.x, private)
3. Container Apps → PostgreSQL (10.0.2.x, private via existing VNet integration)
4. Container Apps → Internet (outbound via NAT Gateway if zone redundancy enabled)

**DNS Resolution:**
- External clients: Resolve custom domain to Application Gateway public IP
- Internal (Application Gateway → Container Apps): Azure-provided DNS resolves Container Apps internal FQDN
- No custom Private DNS zones required (Azure Container Apps handles internal DNS)

### Security

**Network Security Group (MODIFIED - Container Apps subnet):**

Existing NSG: `nav-{env}-ca-nsg`

**Inbound Rules (MODIFIED):**
```hcl
# REMOVE existing rule: allow-https-from-internet (0.0.0.0/0:443)

# NEW RULE: Allow HTTPS from Application Gateway subnet only
priority: 100
name: "allow-https-from-agw"
source_address_prefix: "10.0.3.0/24" # Application Gateway subnet
source_port_range: "*"
destination_address_prefix: "10.0.1.0/24" # Container Apps subnet
destination_port_range: "443"
protocol: "Tcp"
access: "Allow"
direction: "Inbound"

# NEW RULE: Allow health probes from Application Gateway
priority: 110
name: "allow-health-probes-from-agw"
source_address_prefix: "10.0.3.0/24"
source_port_range: "*"
destination_address_prefix: "10.0.1.0/24"
destination_port_range: "443"
protocol: "Tcp"
access: "Allow"
direction: "Inbound"

# EXISTING RULE: Deny all other inbound (implicit - Azure default)
```

**Outbound Rules (unchanged):**
- Container Apps → Internet (via NAT Gateway if enabled)
- Container Apps → PostgreSQL subnet (existing rule)
- Container Apps → Azure services (Microsoft.Storage, etc.)

**Application Gateway Subnet Security:**
- **CRITICAL**: NO Network Security Group allowed on Application Gateway subnet
- Azure platform manages Application Gateway subnet security automatically
- Inbound traffic to Application Gateway public IP implicitly allowed (port 443, 80)

**Web Application Firewall (WAF):**

**Dev Environment:**
- WAF Policy: Basic OWASP Core Rule Set 3.2 (detection mode only)
- No request blocking initially (observe traffic patterns for 7-14 days)
- Alert-only logging to Log Analytics Workspace

**Production Environment:**
- WAF Policy: OWASP Core Rule Set 3.2 (prevention mode after initial detection period)
- Rule groups: SQL injection, XSS, protocol attacks, bad bots
- Custom exclusions: Phoenix LiveView WebSocket upgrade headers (if flagged as anomalies)
- Rate limiting: 100 requests/minute per client IP (configurable based on usage patterns)

**SSL/TLS Configuration:**

**Application Gateway Frontend:**
- TLS version: 1.2 minimum (enforced via SSL policy)
- Cipher suites: Azure predefined policy "AppGwSslPolicy20220101" (TLS 1.2+ secure ciphers only)
- Certificate: Azure Key Vault integration OR Azure-managed certificate (Let's Encrypt via App Service Managed Certificate)
- SNI enabled: Yes (for future multi-domain support)

**Application Gateway to Container Apps Backend:**
- Protocol: HTTPS (encrypted backend traffic)
- Backend certificate validation: Trusted Azure certificates (Container Apps uses Azure-provided TLS)
- No custom certificates required for backend pool

**Secrets Management:**
- SSL certificates stored in Azure Key Vault (if custom domain)
- Application Gateway managed identity granted Key Vault Secrets Officer role
- No certificate private keys in Terraform state or version control

**Identity and Access Management (IAM):**

**Application Gateway Managed Identity:**
- System-assigned managed identity (created automatically with gateway)
- Key Vault access: GET secret, GET certificate (least privilege for SSL cert retrieval)

**Network Isolation:**
- Container Apps: Internal ingress only (external_enabled = false) - no public endpoint
- PostgreSQL: Private endpoint only (existing configuration unchanged)
- Storage Account: Private endpoint only (existing configuration unchanged)

**Compliance Controls:**
- TLS 1.2+ enforced (Government of Canada requirement)
- Defense-in-depth: Application Gateway WAF + Container Apps internal ingress + NSG restrictions
- Audit logging: All Application Gateway access/WAF logs sent to Log Analytics Workspace
- No sensitive data logged: WAF logs URL/headers only, no request/response bodies

### Environment Configuration

**Environment Strategy**: Terragrunt-based configuration with environment-specific variable files

**Environments**: dev, production (no staging in current setup)

**Variable Files (Terragrunt):**
- `terraform/env/dev/terragrunt.hcl` - Dev environment parameters
- `terraform/env/production/terragrunt.hcl` - Production environment parameters

**Application Gateway Environment-Specific Configuration:**

| Parameter | Dev | Production |
|-----------|-----|------------|
| **SKU Tier** | Standard_v2 | Standard_v2 |
| **Capacity** | 2 (fixed) | 2-10 (auto-scaling) |
| **Zone Redundancy** | No (single zone) | Yes (zones 1,2,3) |
| **Public IP SKU** | Standard | Standard |
| **Public IP Zones** | None | ["1","2","3"] |
| **WAF Policy** | Detection mode | Prevention mode (after validation) |
| **WAF Rules** | OWASP CRS 3.2 (basic) | OWASP CRS 3.2 (full) |
| **Auto-scale Enabled** | No | Yes |
| **SSL Policy** | AppGwSslPolicy20220101 | AppGwSslPolicy20220101 |
| **Health Probe Interval** | 30s | 30s |
| **Connection Draining** | 30s | 60s |
| **Request Timeout** | 30s | 30s |

**Container Apps Environment-Specific Configuration (MODIFIED):**

| Parameter | Dev | Production | Change |
|-----------|-----|------------|--------|
| **Ingress External Enabled** | `false` | `false` | ✅ CHANGED (was `true`) |
| **Ingress Visibility** | Internal | Internal | ✅ NEW |
| **IP Restrictions** | Removed | Removed | ✅ CHANGED (was 0.0.0.0/0) |
| **Min Replicas** | 1 | 2 | No change |
| **Max Replicas** | 3 | 10 | No change |
| **Session Affinity** | sticky | sticky | No change (required for WebSocket) |

**Network Security Group Rules (MODIFIED):**

**Dev Environment:**
```hcl
# Container Apps NSG - Inbound
allow_https_from_agw = {
  priority                   = 100
  source_address_prefix      = "10.0.3.0/24"  # dev Application Gateway subnet
  destination_address_prefix = "10.0.1.0/24"  # dev Container Apps subnet
  destination_port_range     = "443"
}
```

**Production Environment:**
```hcl
# Container Apps NSG - Inbound
allow_https_from_agw = {
  priority                   = 100
  source_address_prefix      = "10.0.3.0/24"  # prod Application Gateway subnet
  destination_address_prefix = "10.0.1.0/24"  # prod Container Apps subnet
  destination_port_range     = "443"
}
```

**Naming Convention (consistent across environments):**
- Application Gateway: `nav-{env}-agw`
- Public IP: `nav-{env}-agw-pip`
- WAF Policy: `nav-{env}-waf-policy`
- Application Gateway subnet: `nav-{env}-agw-snet`

**Deployment Order:**
1. Deploy Application Gateway to dev environment
2. Validate WebSocket connections, session affinity, health probes
3. Update Container Apps ingress to internal-only in dev
4. Test external access via Application Gateway, confirm no direct Container Apps access
5. Deploy to production following same sequence
6. Monitor production for 48 hours before enabling WAF prevention mode

**State Isolation:**
- Separate Terraform state per environment (managed by Terragrunt)
- State stored in Azure Blob Storage with unique container per environment
- No shared state between dev and production (complete isolation)

### Complexity Level

**Level**: Enhanced (Production-grade security hardening)

**Rationale**:
This infrastructure change implements defense-in-depth security for an existing production application serving Government of Canada users. While Navigator is an internal threat modeling tool (not public-facing to citizens), the security requirements and regulatory compliance mandate production-grade architecture patterns.

**Characteristics**:

**Purpose**: Security hardening for live production workload (Navigator threat modeling application)

**Architecture Complexity**:
- Production-grade reverse proxy layer (Application Gateway v2)
- Multi-tier networking with isolation (gateway subnet, application subnet, database subnet)
- Zone-redundant deployment (production environment)
- Defense-in-depth: WAF + internal ingress + NSG restrictions

**Security Controls**:
- Full encryption: TLS 1.2+ (frontend), HTTPS (backend), private endpoints (database/storage)
- Web Application Firewall with OWASP Core Rule Set
- Network isolation: Internal-only container apps, subnet-based restrictions
- Least-privilege IAM: Managed identity for Key Vault access
- Comprehensive audit logging: Access logs, WAF logs, diagnostic metrics
- Security scanning: trivy config terraform/ (enforced gate)

**High Availability**:
- Zone-redundant Application Gateway (production: 3 availability zones)
- Auto-scaling: 2-10 capacity units based on load
- Health probes: 30-second intervals with automatic failover
- Session affinity: Sticky sessions for WebSocket connection stability
- Zero-downtime deployment: Blue-green Container Apps revisions during gateway setup

**Monitoring**:
- Centralized logging: Log Analytics Workspace integration
- Custom metrics: Gateway latency, backend response time, health probe status
- Alerting: Unhealthy backend targets, failed requests, WAF blocks
- Dashboards: Real-time traffic visualization, security event monitoring

**Compliance**:
- Government of Canada ITSG-33 alignment (defense-in-depth, encryption, audit logging)
- TLS 1.2+ enforcement (regulatory requirement)
- Event logging per GC Event Logging Guidance
- Incident management aligned with GC CSEMP

**Cost**:
- Baseline (dev): ~$150/month additional (Standard_v2, 2 capacity units, detection-only WAF)
- Enhanced (production): ~$300-500/month (zone-redundant, auto-scaling, prevention WAF)
- Justification: Required for compliance with GC security controls; no simpler alternative meets defense-in-depth requirements

**Team Maturity**:
- Infrastructure as Code: Terragrunt-based configuration, environment isolation
- CI/CD: Automated validation (terraform validate, trivy scan), manual approval for production
- Operational readiness: Monitoring, alerting, incident response procedures required

**Baseline vs Enhanced Application**:
- **Dev environment**: Simplified configuration (single zone, detection-only WAF, minimal scaling) for cost optimization while maintaining security posture
- **Production environment**: Full enhanced capabilities (zone redundancy, prevention WAF, auto-scaling) to meet availability and security SLOs

This is NOT a POC or demo - this is a production security hardening for a live Government of Canada application. Enhanced complexity level is appropriate and required.

### State Management

**Strategy**: Remote state with Azure Blob Storage backend (managed by Terragrunt)

**Current Implementation** (from versions.tf):
```hcl
terraform {
  backend "azurerm" {}  # Configuration auto-generated by Terragrunt
}
```

**Backend Configuration (Terragrunt-managed)**:

**Dev Environment State:**
- Storage Account: (Terragrunt auto-configured)
- Container: `tfstate`
- Blob: `dev/terraform.tfstate`
- Resource Group: Shared Terraform state resource group (separate from application resources)
- Encryption: AES-256 server-side encryption (Azure Storage default)
- Versioning: Enabled (soft delete with 30-day retention)
- Access Control: Restricted to CI/CD service principal + authorized operators

**Production Environment State:**
- Storage Account: (Terragrunt auto-configured)
- Container: `tfstate`
- Blob: `production/terraform.tfstate`
- Resource Group: Shared Terraform state resource group (separate from application resources)
- Encryption: AES-256 server-side encryption (Azure Storage default)
- Versioning: Enabled (soft delete with 90-day retention for production)
- Access Control: Restricted to CI/CD service principal + authorized operators

**State Locking:**
- Mechanism: Azure Blob Storage native locking (lease-based locking)
- Lock acquisition: Automatic during `terraform plan` and `terraform apply`
- Prevents concurrent modifications: Multiple operators cannot modify same environment simultaneously
- Lock timeout: 15 minutes (Terraform default)

**State Isolation:**
- Separate state files per environment (dev, production)
- No shared state across environments
- Each environment can be modified independently
- Enables parallel infrastructure changes across environments (e.g., test in dev while production stable)

**Backup Strategy:**
- Azure Blob Storage versioning: Automatic retention of previous state versions
- Soft delete: 30-day retention (dev), 90-day retention (production)
- Manual backups: Not required (versioning provides rollback capability)
- Disaster recovery: Cross-region replication (if Terragrunt configures GRS/RA-GRS storage)

**Access Control:**
- IAM: Storage Blob Data Contributor role for CI/CD service principal
- Network: Storage Account firewall allows CI/CD runner IPs + Azure services
- Authentication: Azure AD authentication (no storage account keys in CI/CD)
- Audit: Storage Account logging enabled (read/write/delete operations logged)

**Security:**
- State encryption: AES-256 at rest (Azure Storage default)
- TLS in transit: Terraform uses HTTPS for state operations
- Sensitive values: Database passwords, API keys stored in state (encrypted at rest)
- No credentials in version control: Backend configuration injected by Terragrunt at runtime

**State Management Best Practices:**
1. Never commit `terraform.tfstate` to version control (already in .gitignore)
2. Use `terraform state` commands only when necessary (prefer declarative configuration changes)
3. Review `terraform plan` output before applying (state diff shows changes)
4. For Application Gateway changes: Review plan carefully (replacement operations can cause downtime)
5. Use lifecycle `prevent_destroy` for production Application Gateway resource

**Terragrunt Integration:**
- Terragrunt auto-configures backend based on environment (`terraform/env/{env}/terragrunt.hcl`)
- DRY principle: Backend configuration not duplicated in Terraform code
- Workspace selection: Terragrunt manages environment selection automatically
- State path: Terragrunt injects unique blob path per environment

## Project Structure

### Documentation (this infrastructure)

```text
specs/[###-infrastructure]/
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

**Structure**: Terraform Infrastructure (Option 2 - organized by resource type)

**Current Repository Structure**:
```
navigator-az-terraform/
├── terraform/
│   ├── azure/                      # Terraform root module (all .tf files)
│   │   ├── versions.tf             # Terraform and provider version constraints
│   │   ├── provider.tf             # Azure provider configuration (azurerm, azapi)
│   │   ├── locals.tf               # Naming convention centralization
│   │   ├── variables.tf            # Input variable declarations
│   │   ├── outputs.tf              # Output value declarations
│   │   │
│   │   │   # Existing infrastructure resources
│   │   ├── vnet.tf                 # Virtual Network, Subnets (includes agw-snet)
│   │   ├── security.tf             # Network Security Groups (MODIFIED)
│   │   ├── container-apps.tf      # Container Apps Environment, App (MODIFIED)
│   │   ├── postgresql.tf          # PostgreSQL Flexible Server
│   │   ├── storage.tf              # Storage Account
│   │   ├── acr.tf                  # Azure Container Registry
│   │   ├── dns.tf                  # Public DNS (if custom domain)
│   │   ├── dns-private.tf          # Private DNS zones
│   │   ├── secrets.tf              # Random passwords, Key Vault integration
│   │   ├── identity.tf             # Managed identities
│   │   ├── auth-openai.tf          # Azure OpenAI (optional)
│   │   │
│   │   │   # NEW infrastructure resources (to be added)
│   │   ├── application-gateway.tf  # ✅ NEW: Application Gateway, Public IP, WAF Policy
│   │   │
│   ├── env/                        # Terragrunt environment configurations
│   │   ├── dev/
│   │   │   └── terragrunt.hcl      # Dev environment variables (MODIFIED)
│   │   └── production/
│   │       └── terragrunt.hcl      # Production environment variables (MODIFIED)
│   │
├── specs/                          # Infrastructure specifications
│   ├── 002-internal-ca/            # This specification
│   │   ├── spec.md                 # Infrastructure requirements
│   │   ├── plan.md                 # This architecture plan
│   │   └── tasks.md                # Implementation tasks (to be created via /iac.tasks)
│   │
├── navigator/                      # Git submodule (Navigator application source)
│   └── (Elixir/Phoenix application - DO NOT MODIFY)
│  
├── .github/
│   └── instructions/               # Coding standards
│       ├── terraform.instructions.md
│       └── (other guidelines)
│
├── AGENTS.md                       # Agent instructions (project overview)
├── README.md                       # Repository documentation
└── .gitignore                      # Excludes .tfstate, .terraform/, secrets
```

**Files to be Modified (Implementation Phase)**:

1. **terraform/azure/application-gateway.tf** (NEW FILE)
   - Application Gateway resource (azurerm_application_gateway)
   - Public IP resource (azurerm_public_ip)
   - WAF Policy resource (azurerm_web_application_firewall_policy)
   - Backend pool configuration (Container Apps internal FQDN)
   - Health probe configuration (HTTPS, path /, 30s interval)
   - Routing rules (all traffic → backend pool)
   - SSL/TLS configuration (Azure-managed certificate or Key Vault reference)
   - Session affinity (cookie-based)

2. **terraform/azure/security.tf** (MODIFY EXISTING)
   - Update Container Apps NSG inbound rules:
     - Remove: `allow-https-from-internet` (0.0.0.0/0 → Container Apps)
     - Add: `allow-https-from-agw` (Application Gateway subnet → Container Apps subnet)

3. **terraform/azure/container-apps.tf** (MODIFY EXISTING)
   - Change `azurerm_container_app.navigator.ingress.external_enabled` from `true` to `false`
   - Remove or comment out `ip_security_restriction` block (internal ingress doesn't need IP restrictions)
   - Add `depends_on` for Application Gateway (ensure gateway ready before switching to internal ingress)

4. **terraform/azure/locals.tf** (MODIFY EXISTING)
   - Add Application Gateway naming locals:
     ```hcl
     agw_name        = "${local.name_prefix}-agw"
     agw_pip_name    = "${local.name_prefix}-agw-pip"
     waf_policy_name = "${local.name_prefix}-waf-policy"
     ```

5. **terraform/azure/variables.tf** (MODIFY EXISTING)
   - Add Application Gateway configuration variables:
     ```hcl
     variable "agw_capacity_min" { ... }
     variable "agw_capacity_max" { ... }
     variable "enable_waf" { ... }
     variable "waf_mode" { ... }  # "Detection" or "Prevention"
     ```

6. **terraform/env/dev/terragrunt.hcl** (MODIFY EXISTING)
   - Add Application Gateway dev configuration:
     ```hcl
     agw_capacity_min = 2
     agw_capacity_max = 2
     enable_waf = true
     waf_mode = "Detection"
     ```

7. **terraform/env/production/terragrunt.hcl** (MODIFY EXISTING)
   - Add Application Gateway production configuration:
     ```hcl
     agw_capacity_min = 2
     agw_capacity_max = 10
     enable_waf = true
     waf_mode = "Detection"  # Change to "Prevention" after validation
     ```

8. **terraform/azure/outputs.tf** (MODIFY EXISTING)
   - Add Application Gateway outputs:
     ```hcl
     output "application_gateway_public_ip" { ... }
     output "application_gateway_fqdn" { ... }
     ```

**Structure Decision**:

**Selected**: Option 2 - Terraform Infrastructure (organized by resource type)

**Rationale**:
- Existing infrastructure already uses this pattern (vnet.tf, container-apps.tf, postgresql.tf, etc.)
- Clear organization: Each file groups related resources (networking, compute, security)
- Maintainability: Easy to locate Application Gateway configuration (single file)
- No unnecessary complexity: Direct resources preferred over modules (see "Prefer Resource Simplicity" principle)
- Team familiarity: Consistent with existing codebase patterns
- File count: Adding 1 new file (application-gateway.tf) + modifications to 7 existing files

**NOT using modules**:
- Azure Verified Module (avm-res-network-applicationgateway) evaluated but rejected
- Direct `azurerm_application_gateway` resource provides better transparency for security reviews
- Estimated LOC: ~200 lines for Application Gateway resource vs 500+ lines of module abstraction
- Debugging: Direct resources easier to troubleshoot than module wrapper
- Decision aligns with "Prefer Resource Simplicity" principle

---

**Plan Complete** - Ready for task breakdown via `/iac.tasks`

**Optional Next Steps**:
- Run `/iac.enrichplan` for deep research (Well-Architected Framework analysis, detailed module configurations)
- Run `/iac.tasks` to break this plan into implementation tasks
