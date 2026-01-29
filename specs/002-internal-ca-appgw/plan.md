# Architecture Plan: Internal Container Apps with Application Gateway

**Branch**: `002-internal-ca-appgw` | **Date**: 2026-01-26 | **Spec**: [spec.md](./spec.md)
**Input**: Infrastructure specification from `/specs/002-internal-ca-appgw/spec.md`

**Note**: This plan builds on existing infrastructure in `terraform/azure/` by adding Application Gateway as a reverse proxy for internal-only Container Apps.

**Enrichment Artifacts** (generated 2026-01-26):
- [research.md](./research.md) - Azure Well-Architected Framework analysis, curated modules, ACME provider integration
- [architecture.md](./architecture.md) - Detailed infrastructure architecture specifications
- [modules.md](./modules.md) - Module specifications (direct resources approach)
- [quickstart.md](./quickstart.md) - Step-by-step provisioning guide

## Summary

This architecture secures the Navigator application by converting the existing publicly exposed Azure Container Apps environment to internal-only access and routing all external traffic through Azure Application Gateway. The Application Gateway serves as a defense-in-depth security layer with optional Web Application Firewall (WAF), SSL/TLS termination using ACME/Let's Encrypt certificates, and centralized traffic management. The implementation uses Azure-native managed services, maintains WebSocket support for Phoenix LiveView, and automates certificate provisioning and renewal via the ACME provider.

## Technical Context

**Cloud Provider**: Microsoft Azure (canadacentral region)
**IaC Tool**: Terraform 1.8+ (current stable: 1.14.3)
**Provider Versions**:
- hashicorp/azurerm ~> 4.58 (latest: 4.58.0)
- Azure/azapi ~> 2.8 (latest: 2.8.0, for session affinity configuration)
- hashicorp/random ~> 3.8 (latest: 3.8.0, for secret generation)
- vancluever/acme ~> 2.43 (latest: 2.43.0, for Let's Encrypt TLS certificate automation with ARI support)
**Curated Modules**: Azure Verified Modules (AVM) - using direct resources per Navigator "Prefer Resource Simplicity" principle
**State Backend**: Azure Blob Storage with Terragrunt-managed configuration (existing setup)
**Environment Strategy**: Terragrunt with environment-specific configurations (terraform/env/dev, terraform/env/production)
**Testing**: terraform test (built-in), manual validation
**Security Scanning**: trivy config (infrastructure scanning)
**Cost Estimation**: Azure Pricing Calculator
**Target Environments**: dev, production
**Compliance**: Government of Canada ITSG-33, defense-in-depth architecture, Canadian data residency

## Principles Check

✅ **Prefer Managed Services**: Using Azure Application Gateway (fully managed PaaS), Container Apps (managed compute), and managed PostgreSQL. No self-managed infrastructure. WAF capabilities are built into Application Gateway service.

✅ **Design for Simplicity**: Single-region deployment with minimal networking complexity. Application Gateway deployed in same VNet as Container Apps. No multi-region, no service mesh. Both environments use Standard_v2 SKU for consistency.

✅ **Design for Reliability and Resilience**:
- Dev: Single-zone Application Gateway (acceptable for internal tool)
- Production: Zone-redundant Application Gateway with health probes for zero-downtime deployments
- WebSocket session affinity preserved for Phoenix LiveView
- Container Apps health probes maintained for backend monitoring

✅ **Optimize for Cost**:
- Both environments: Application Gateway Standard_v2 SKU for consistency (~$150/month dev, ~$250/month production with zone redundancy)
- WAF is optional feature flag, can be enabled/disabled independently of SKU
- Shared infrastructure (same VNet, subnets, NSGs) minimizes additional resources

✅ **Prefer Resource Simplicity**: Using direct `azurerm_application_gateway` resource blocks instead of modules. Clear, explicit configuration for gateway backend pools, HTTP settings, and routing rules. No module abstractions.

✅ **Automate Validation and Deployment**:
- Existing Terragrunt CI/CD workflow maintained
- Application Gateway changes validated through `terraform plan`
- Health probes enable automated backend validation
- Security scanning with trivy remains in place

✅ **Manage Secrets Securely**:
- No hardcoded credentials in infrastructure code
- Container Apps secrets managed via Azure platform encryption
- ACME provider uses ephemeral resources for certificate challenges (not stored in state)
- Certificate private keys managed via ACME provider, automatically rotated on renewal

**Deviations**: None. Architecture fully aligns with Navigator principles using managed services, direct resources, and environment-appropriate complexity levels.

## Infrastructure Architecture

### Compute Resources

**Azure Application Gateway (Reverse Proxy)**:
- **Both Environments**:
  - SKU: Standard_v2 (consistent across dev and production)
  - Tier: Standard_v2
  - WAF: Managed via separate WAF Policy (optional, feature flag `enable_waf`)
  - TLS Certificates: Automated via ACME provider (Let's Encrypt)

- **Dev Environment**:
  - Capacity: Fixed 1 instance (auto-scaling disabled)
  - Availability: Single-zone deployment
  - WAF Policy: Disabled (default)
  - Estimated cost: ~$150/month

- **Production Environment**:
  - Capacity: Auto-scale 2-5 instances based on traffic
  - Availability: Zone-redundant (zones 1, 2, 3)
  - WAF Policy: Optional (feature flag `enable_waf`), OWASP CRS 3.2, Detection mode initially
  - Estimated cost: ~$250/month (Standard_v2 zone-redundant), ~$400/month with WAF policy

**Frontend Configuration**:
- Public IP: Standard SKU, static allocation, zone-redundant (production) / zone-local (dev)
- HTTPS Listener: Port 443, TLS 1.2 minimum version
- HTTP→HTTPS Redirect: Optional listener on port 80 redirecting to 443
- TLS Certificate: Automated provisioning and renewal via ACME provider (Let's Encrypt)
- Custom domain support: Enabled when `var.domain_name` is provided (triggers ACME certificate request)

**Backend Configuration**:
- Backend Pool: Container Apps internal FQDN (`<ca-name>.<cae-default-domain>`)
- Backend Protocol: HTTP (port 80)
- Health Probe: HTTP probe to `/` path, 30-second interval, 3 failure threshold
- Connection Draining: 30-second timeout for graceful shutdown
- Session Affinity: Cookie-based affinity enabled (preserves existing Container Apps session affinity)
- Request Timeout: 180 seconds (supports long-lived WebSocket connections)

**WebSocket Support**:
- HTTP/2 enabled on Application Gateway
- WebSocket protocol upgrade headers preserved
- Session affinity ensures WebSocket connections stay on same backend replica
- Backend timeout configured for 180 seconds to prevent premature closure

**Header Preservation**:
- `X-Forwarded-Host`: Injected with original client host for correct redirect URLs
- `X-Forwarded-Proto`: Set to https for protocol awareness
- `X-Forwarded-For`: Original client IP preserved for logging
- Host header override: Backend receives Container Apps internal FQDN

**Existing Container Apps Infrastructure** (modified for internal load balancer):
- Container Apps Environment: VNet-integrated, internal load balancer enabled, zone-redundant (production), consumption workload profile
- Navigator Container App: Min 0 / Max 2 replicas (dev), Min 1 / Max 5 replicas (production), external_enabled=true for VNET access
- Container: 0.5 vCPU, 1Gi memory (dev), 1.0 vCPU, 2Gi memory (production)
- Health probes: Liveness, readiness, startup probes on `/` path
- Scaling: HTTP concurrency (dev), CPU utilization 70% (production)
- Transport: Auto (default, supports HTTP/1.1 and HTTP/2)

### Data Storage

**No changes to existing data storage**:
- Azure Database for PostgreSQL Flexible Server (existing)
- Connection via private delegated subnet
- Backup retention: 7 days (dev), 30 days (production)
- Storage: 32GB (dev), 64GB (production)

**Application Gateway does NOT store data** - stateless reverse proxy only.

### Networking

**Existing VNet Structure** (10.240.0.0/16):
```
├── Container Apps Subnet: 10.240.0.0/23 → MODIFIED to 10.240.0.0/23 (Microsoft requirement for internal load balancer)
│   ├── Delegation: Microsoft.App/environments
│   ├── Service Endpoints: Microsoft.Storage
│   └── NSG: Modified to allow inbound HTTP from Application Gateway subnet only
│
├── PostgreSQL Subnet: 10.240.2.0/24 (no changes)
│   ├── Delegation: Microsoft.DBforPostgreSQL/flexibleServers
│   ├── Service Endpoints: Microsoft.Storage
│   └── NSG: Existing rules maintained
│
└── Application Gateway Subnet: 10.240.3.0/24 (NEW - exists but unused)
    ├── No delegation required
    ├── No NSG allowed (Azure platform limitation for Application Gateway)
    └── Service Endpoints: Microsoft.Storage
```

**Subnet Size Change Rationale**:
- Container Apps subnet changed to 10.240.0.0/23 (510 hosts) per Microsoft requirement
- Microsoft requires minimum /23 subnet for Container Apps environment with internal load balancer
- Enables VNET integration features for Container Apps
- Provides room for future scaling and additional container apps

**Private DNS Zone** (NEW - for Container Apps internal FQDN):
- Zone Name: `<environment>.canadacentral.azurecontainerapps.io` (Container Apps environment default domain)
- A Record: `*` → Container Apps environment static IP
- A Record: `@` → Container Apps environment static IP
- Virtual Network Link: Links to main VNet for internal DNS resolution
- Purpose: Enables Application Gateway to resolve Container Apps internal FQDN

**Private DNS Zone for Custom Domain** (NEW):
- Zone Name: `var.domain_name` (e.g., demo.focisolutions.com)
- A Record: `@` → Application Gateway public IP
- Virtual Network Link: Links to main VNet for internal resolution
- Purpose: Enables internal resolution of custom domain within VNET

**Traffic Flow**:
```
Internet → Application Gateway (10.240.3.0/24)
         → Private DNS Resolution (internal FQDN)
         → Container Apps Environment (10.240.0.0/23, internal load balancer)
         → Navigator Container App (backend)
```

**NAT Gateway** (existing, production only):
- Enables outbound internet connectivity for Container Apps
- Required for Azure OpenAI API integration
- No changes required

**Custom Domain DNS** (managed via terraform/azure/dns.tf):
- Azure DNS Zone: Manages custom domain DNS records (e.g., demo.focisolutions.com)
- DNS A Record: `navigator-{env}` subdomain points to Application Gateway public IP (creates navigator-dev.demo.focisolutions.com or navigator-production.demo.focisolutions.com)
- ACME DNS-01 Challenge: Uses Azure DNS zone for domain validation with `azuredns` provider (automated)
- Certificate issued for full subdomain (e.g., navigator-dev.demo.focisolutions.com)

### Security

**Container Apps Ingress Change** (CRITICAL):
```hcl
# BEFORE (current state):
resource "azurerm_container_app_environment" "this" {
  # ... configuration ...
  internal_load_balancer_enabled = false  # Public access
}

ingress {
  external_enabled = true  # Direct public access
  allow_insecure_connections = false
  target_port = 4000
  ip_security_restriction {
    action = "Allow"
    ip_address_range = "0.0.0.0/0"  # Allow all
  }
}

# AFTER (new state):
resource "azurerm_container_app_environment" "this" {
  # ... configuration ...
  internal_load_balancer_enabled = true  # Internal load balancer only
  # public_network_access implicitly set to "Disabled" when internal_load_balancer_enabled = true
}

ingress {
  external_enabled = true   # Set to true to allow connections from same VNET (required for App Gateway)
  allow_insecure_connections = false
  target_port = 4000
  # transport defaults to Auto (removed explicit configuration)
  # No IP restrictions - VNET access only due to internal load balancer
}
```

**Network Security Groups**:

*Container Apps NSG (MODIFIED)*:
```
Inbound Rules (Priority Order):
1. Allow HTTP from Application Gateway subnet (10.240.3.0/24) → Port 80 [NEW]
2. Allow PostgreSQL traffic from Container Apps subnet → Port 5432 [EXISTING]
3. Deny all other inbound traffic [EXISTING]

Outbound Rules:
- Allow all outbound (NAT Gateway for internet access) [EXISTING]
```

*Application Gateway Subnet*:
- **No NSG allowed** - Azure platform requirement for Application Gateway
- Security managed through Application Gateway configuration and backend NSG rules

**Web Application Firewall (Optional)**:
- Feature flag: `enable_waf` (default: false for both environments, can be enabled independently)
- WAF Policy: Separate resource that can be attached to Standard_v2 Application Gateway
- WAF Configuration (when enabled):
  - OWASP Core Rule Set 3.2
  - Mode: Detection (initially), Prevention (after validation)
  - Rule Set: OWASP Top 10 protection (SQL injection, XSS, etc.)
  - Custom Rules: None initially (can add IP allowlist/blocklist later)
  - Exclusions: None initially (adjust based on false positives)
- Note: WAF_v2 SKU is NOT required - WAF policy can be attached to Standard_v2 SKU

**SSL/TLS Configuration**:
- Minimum TLS Version: 1.2
- Cipher Suites: Azure default (strong ciphers only)
- Certificate Management: Automated via ACME provider (Let's Encrypt)
  - Certificate provisioning: Automatic when `var.domain_name` is provided
  - Certificate renewal: Automatic via ACME provider (90-day Let's Encrypt certificates)
  - DNS validation: DNS-01 challenge using `azuredns` provider (configured per environment)
  - Certificate storage: Uploaded to Application Gateway and Container App Environment
  - Private key: Never stored in Terraform state (ephemeral resource)
- Backend communication: HTTP (gateway to container uses unencrypted HTTP within trusted VNET)

**ACME Provider Implementation**:
```hcl
# ACME provider configuration
provider "acme" {
  server_url = var.acme_server_url  # Environment-specific (staging for dev, production for prod)
}

# ACME account registration (one-time setup)
resource "tls_private_key" "acme_account" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "acme_registration" "account" {
  account_key_pem = tls_private_key.acme_account.private_key_pem
  email_address   = var.acme_email_address
}

# Certificate request and automatic renewal
resource "acme_certificate" "navigator" {
  count = var.domain_name != null ? 1 : 0  # Only when custom domain provided

  account_key_pem           = acme_registration.account.account_key_pem
  common_name               = var.domain_name  # Full subdomain
  certificate_p12_password  = random_password.cert_p12_password.result

  # DNS-01 challenge using existing Azure DNS zone (terraform/azure/dns.tf)
  dns_challenge {
    provider = "azuredns"  # Changed from "azure" (deprecated)
    config = {
      AZURE_RESOURCE_GROUP = var.resource_group_name
      AZURE_ZONE_NAME      = var.domain_name  # Managed by azurerm_dns_zone.main
      # Authentication via Azure CLI or managed identity (no client credentials needed)
    }
  }
}

# Random password for certificate P12 export
resource "random_password" "cert_p12_password" {
  length  = 32
  special = true
}

# Upload certificate to Application Gateway
resource "azurerm_application_gateway" "main" {
  # ... other configuration ...

  dynamic "ssl_certificate" {
    for_each = var.domain_name != null ? [1] : []
    content {
      name     = "navigator-ssl-cert"
      data     = acme_certificate.navigator[0].certificate_p12
      password = acme_certificate.navigator[0].certificate_p12_password
    }
  }
}

# Upload certificate to Container App Environment
resource "azurerm_container_app_environment_certificate" "navigator" {
  count                        = var.domain_name != null ? 1 : 0
  name                         = "navigator-cert-${var.environment}"
  container_app_environment_id = azurerm_container_app_environment.this.id
  certificate_blob_base64      = acme_certificate.navigator[0].certificate_p12
  certificate_password         = acme_certificate.navigator[0].certificate_p12_password
}

# Bind custom domain to Container App
resource "azurerm_container_app_custom_domain" "navigator" {
  count                         = var.domain_name != null ? 1 : 0
  name                          = var.domain_name
  container_app_id              = azurerm_container_app.navigator.id
  container_app_environment_certificate_id = azurerm_container_app_environment_certificate.navigator[0].id
  certificate_binding_type      = "SniEnabled"
}
```

**ACME Certificate Lifecycle**:
1. Initial provisioning: ACME provider requests certificate from Let's Encrypt during `terraform apply`
2. DNS validation: ACME provider automatically creates DNS TXT record in Azure DNS zone for domain validation
3. DNS-01 challenge: Let's Encrypt validates domain ownership via DNS query
4. Certificate issuance: Let's Encrypt issues certificate (valid 90 days)
5. Automatic renewal: ACME provider monitors expiry and renews before 30-day threshold
6. Certificate rotation: New certificate uploaded to Application Gateway on renewal (zero-downtime)

**Secrets Management**:
- Container Apps secrets: Encrypted by Azure platform (no changes)
- PostgreSQL password: Generated via `random_password`, stored in Azure-encrypted state
- ACME account key: Generated and managed by ACME provider (stored in state, encrypted)
- TLS certificate private key: Ephemeral resource, never stored in state (ACME provider managed)
- Certificate P12 password: Generated by ACME provider, used only during upload to Application Gateway
- No Azure Key Vault dependency required

**Identity and Access**:
- Container Apps: System-assigned managed identity (existing, no changes)
- Application Gateway: No managed identity required (stateless reverse proxy)
- Private DNS: No special permissions required

**Threat Model Considerations**:
- Attack surface reduced: Container Apps no longer directly internet-exposed
- Defense-in-depth: Application Gateway WAF layer + Container Apps ingress + NSG rules
- DDoS protection: Azure platform DDoS Basic included with public IP (no additional cost)
- SSL/TLS termination: Centralized certificate management at Application Gateway
- Backend communication: HTTP used between Application Gateway and Container Apps (private network, encrypted HTTPS only from client to gateway)

### Environment Configuration

**Environment Strategy**: Terragrunt-based configuration with environment-specific variable files

**Directory Structure**:
```
terraform/
├── azure/                    # Shared Terraform module (DRY principle)
│   ├── versions.tf           # MODIFIED: Add ACME provider version constraint
│   ├── provider.tf           # MODIFIED: Add ACME provider configuration
│   ├── variables.tf          # MODIFIED: Add Application Gateway and ACME variables
│   ├── locals.tf             # MODIFIED: Add Application Gateway naming
│   ├── vnet.tf               # MODIFIED: Subnet size, NSG rules
│   ├── container-apps.tf     # MODIFIED: internal_load_balancer_enabled = true, external_enabled = true
│   ├── app-gateway.tf        # NEW: Application Gateway resource
│   ├── acme.tf               # NEW: ACME certificate provisioning
│   ├── dns-private.tf        # MODIFIED: Add Private DNS zone for Container Apps
│   └── outputs.tf            # MODIFIED: Add Application Gateway outputs
│
└── env/
    ├── dev/
    │   └── terragrunt.hcl    # Dev-specific inputs (Standard_v2, no WAF, 1 instance)
    │
    └── production/
        └── terragrunt.hcl    # Production inputs (Standard_v2, zone-redundant, optional WAF)
```

**Environment Differences**:

| Parameter | Dev | Production |
|-----------|-----|------------|
| **Application Gateway** | | |
| SKU | Standard_v2 | Standard_v2 |
| Capacity | Fixed 1 instance | Auto-scale 2-5 instances |
| Availability Zones | None | Zones 1, 2, 3 |
| WAF Policy Attached | false | false (optional via `enable_waf`) |
| Public IP SKU | Standard (zone-local) | Standard (zone-redundant) |
| ACME Endpoint | Staging | Production |
| **Cost** | ~$150/month | ~$250/month (Standard_v2 zone-redundant) |
| **Container Apps** (existing) | | |
| Subnet Size | 10.240.0.0/23 | 10.240.0.0/23 |
| Internal Load Balancer | true | true |
| External Enabled | true (VNET access) | true (VNET access) |
| Min Replicas | 0 | 1 |
| Max Replicas | 2 | 5 |
| Container CPU | 0.5 vCPU | 1.0 vCPU |
| Container Memory | 1Gi | 2Gi |
| Zone Redundancy | false | true |

**Feature Flags** (via Terraform variables):
```hcl
# Dev defaults
enable_waf               = false  # Cost optimization (can enable if needed)
enable_zone_redundancy   = false  # Simplified architecture
enable_http_redirect     = true   # Redirect HTTP→HTTPS
appgw_capacity_min       = 1      # Fixed capacity
appgw_capacity_max       = 1      # No auto-scaling
acme_server_url          = "https://acme-staging-v02.api.letsencrypt.org/directory"  # Staging for testing

# Production defaults
enable_waf               = false  # Optional, can enable independently (adds ~$150/month)
enable_zone_redundancy   = true   # High availability
enable_http_redirect     = true   # Enforce HTTPS
appgw_capacity_min       = 2      # Minimum 2 instances
appgw_capacity_max       = 5      # Auto-scale up to 5
acme_server_url          = "https://acme-v02.api.letsencrypt.org/directory"  # Production Let's Encrypt
```

**Note on variable simplification**:
- Removed `enable_custom_domain` variable - custom domain usage is determined by checking if `var.domain_name` is provided (null check)
- ACME certificate provisioning triggered automatically when `var.domain_name != null`
- No redundant feature flags

**Variable Inputs** (Terragrunt):
```hcl
# Dev environment (terraform/env/dev/terragrunt.hcl)
inputs = {
  environment                  = "dev"
  enable_waf                   = false
  enable_zone_redundancy       = false
  appgw_sku_name              = "Standard_v2"
  appgw_tier                  = "Standard_v2"
  appgw_capacity_min          = 1
  appgw_capacity_max          = 1
  container_apps_subnet_prefix = "10.240.0.0/23"  # MODIFIED: Meets Microsoft's /23 requirement for delegation
  acme_email_address          = "devops-dev@example.gc.ca"
  acme_server_url             = "https://acme-staging-v02.api.letsencrypt.org/directory"
  domain_name                 = "demo.focisolutions.com"  # Subdomain pattern: navigator-{env}.demo.focisolutions.com
}

# Production environment (terraform/env/production/terragrunt.hcl)
inputs = {
  environment                  = "production"
  enable_waf                   = false  # Optional, set to true to enable WAF policy
  enable_zone_redundancy       = true
  appgw_sku_name              = "Standard_v2"
  appgw_tier                  = "Standard_v2"
  appgw_capacity_min          = 2
  appgw_capacity_max          = 5
  waf_mode                    = "Detection"  # Used only if enable_waf = true
  container_apps_subnet_prefix = "10.240.0.0/23"  # MODIFIED: Meets Microsoft's /23 requirement for delegation
  acme_email_address          = "devops@example.gc.ca"
  acme_server_url             = "https://acme-v02.api.letsencrypt.org/directory"
  domain_name                 = "demo.focisolutions.com"  # Subdomain pattern: navigator-{env}.demo.focisolutions.com
}
```

**Deployment Workflow**:
1. Apply to dev environment first: `terragrunt apply` in terraform/env/dev
2. Validate Application Gateway → Container Apps connectivity
3. Test WebSocket connections (Phoenix LiveView)
4. Configure custom domain DNS (if using custom domain):
   - Update domain registrar NS records to point to Azure DNS name servers (from outputs)
   - ACME provider will automatically create DNS TXT records for validation
   - ACME provider validates domain ownership via DNS-01 challenge
5. Promote to production: `terragrunt apply` in terraform/env/production
6. Monitor ACME certificate renewal (automatic, 30 days before expiry)

### Complexity Level

**Complexity Level: ENHANCED** (Staging/Production-grade architecture)

**Rationale**:
- Production workload: Navigator is an internal Government of Canada threat modeling tool requiring defense-in-depth security
- Security requirements: Defense-in-depth architecture per ITSG-33, WAF protection for OWASP Top 10 threats
- Reliability requirements: 99.95% uptime SLO, zero-downtime deployments, WebSocket session preservation
- Compliance: Government of Canada security controls, Canadian data residency

**Enhanced Features**:
- Multi-layer security: Application Gateway WAF + Container Apps internal ingress + NSG rules
- Zone-redundant deployment (production): Application Gateway across 3 availability zones
- Auto-scaling: Application Gateway scales 2-5 instances based on traffic (production)
- Comprehensive monitoring: Application Gateway access logs, WAF logs, Container Apps metrics
- Health probes: 30-second interval backend health checks with automated failover
- SSL/TLS termination: Centralized certificate management with TLS 1.2+ enforcement

**Cost Optimization Balance**:
- Dev environment uses simpler configuration (Standard_v2, no WAF, single instance) to minimize cost
- Production uses full features for security and reliability requirements
- Shared infrastructure (VNet, subnets, NSGs) minimizes incremental cost
- WAF optional feature flag allows cost/security trade-off

**NOT Over-Engineered**:
- Single-region deployment (no multi-region complexity)
- No custom modules (direct resources per principles)
- No service mesh or advanced routing (simple reverse proxy pattern)
- No CDN or caching layer (application-level caching preferred)
- No custom WAF rules initially (OWASP CRS defaults sufficient)

### State Management

**Backend: Azure Blob Storage** (existing Terragrunt configuration)

**Configuration**:
```hcl
# Managed by Terragrunt (terraform/env/*/terragrunt.hcl)
remote_state {
  backend = "azurerm"

  config = {
    resource_group_name  = "navigator-terraform-state-rg"
    storage_account_name = "navtfstate<uniqueness>"
    container_name       = "tfstate"
    key                  = "${path_relative_to_include()}/terraform.tfstate"

    # Security
    use_azuread_auth = true  # Managed identity authentication
    use_msi          = true  # No storage account keys
  }
}
```

**State Isolation**:
- Separate state files per environment: `env/dev/terraform.tfstate`, `env/production/terraform.tfstate`
- Environment isolation prevents cross-environment changes
- Dev and production can be deployed independently

**State Security**:
- Encryption at rest: Azure Storage Account encryption (AES-256)
- Encryption in transit: HTTPS enforced for all state operations
- Access control: Azure RBAC restricts state access to CI/CD service principals and authorized users
- Versioning: Blob versioning enabled for rollback capability (30-day retention)
- Locking: Azure Blob lease mechanism prevents concurrent modifications

**Backup Strategy**:
- Blob versioning: 30 days of version history retained
- Soft delete: 7-day retention for deleted blobs
- No separate backup process required (blob versioning is sufficient)

**Sensitive Data in State**:
- Container Apps secrets (database password, OAuth credentials) stored encrypted in state
- ACME account key: Stored in state (encrypted), used for certificate renewal
- ACME certificate private key: Never stored in state (ephemeral resource, managed by provider)
- Certificate P12 data: Stored in state temporarily during upload to Application Gateway
- State file access strictly controlled via Azure RBAC

**Terragrunt Benefits**:
- DRY configuration: Single module in `terraform/azure/`, environment-specific inputs in `terragrunt.hcl`
- Automatic backend initialization: Terragrunt generates backend configuration
- State management: Automatic state locking and encryption
- Dependency management: Terragrunt handles module dependencies

## Project Structure

### Documentation (this infrastructure)

```text
specs/002-internal-ca-appgw/
├── spec.md              # Infrastructure specification (technology-agnostic) - /iac.specify
├── plan.md              # This file - architecture plan - /iac.plan
├── tasks.md             # Implementation tasks - /iac.tasks
│
│   # Optional enrichment artifacts (run /iac.enrichplan if needed):
├── research.md          # Deep research: Well-Architected Framework, curated modules
├── modules.md           # Module specifications (if using custom modules)
└── quickstart.md        # Step-by-step provisioning guide
```

### Source Code (repository root)

```text
terraform/
├── azure/                           # Shared Terraform module (DRY principle)
│   ├── versions.tf                  # MODIFIED: Add ACME provider version constraint
│   ├── provider.tf                  # MODIFIED: Add ACME provider configuration
│   ├── variables.tf                 # MODIFIED: Add Application Gateway and ACME variables
│   ├── locals.tf                    # MODIFIED: Add Application Gateway naming
│   ├── vnet.tf                      # MODIFIED: Subnet size, NSG rules
│   ├── security.tf                  # MODIFIED: NSG rules for Application Gateway
│   ├── container-apps.tf            # MODIFIED: internal_load_balancer_enabled = true, external_enabled = true
│   ├── app-gateway.tf               # NEW: Application Gateway resource
│   ├── acme.tf                      # NEW: ACME certificate provisioning and renewal
│   ├── dns.tf                       # MODIFIED: DNS A record points to App Gateway, remove unnecessary resources
│   ├── dns-private.tf               # MODIFIED: Private DNS zone for Container Apps
│   ├── postgresql.tf                # No changes
│   └── outputs.tf                   # MODIFIED: Add Application Gateway outputs
│
└── env/
    ├── dev/
    │   └── terragrunt.hcl           # MODIFIED: Application Gateway and ACME inputs
    │
    └── production/
        └── terragrunt.hcl           # MODIFIED: Application Gateway and ACME inputs
```

**Structure Decision**: Terragrunt-based Infrastructure (Option 2 adapted for multi-environment)

This structure follows Navigator principles:
- **DRY**: Single Terraform module in `terraform/azure/` shared across environments
- **Direct Resources**: No custom modules, direct `azurerm_*` resource blocks
- **Environment Isolation**: Separate Terragrunt configurations per environment
- **Clear Separation**: Infrastructure files organized by resource type (vnet.tf, app-gateway.tf, etc.)

**New Files**:
- `terraform/azure/app-gateway.tf`: Application Gateway resource, backend pools, HTTP settings, listeners, routing rules, SSL certificate configuration
- `terraform/azure/acme.tf`: ACME provider configuration, account registration, certificate request and renewal logic

**Modified Files**:
- `terraform/azure/versions.tf`: Add ACME provider version constraint (~> 2.0)
- `terraform/azure/provider.tf`: Add ACME provider configuration with server URL
- `terraform/azure/vnet.tf`: Container Apps subnet changed to 10.240.0.0/23 (Microsoft requirement for delegation), NSG rules updated for HTTP (port 80)
- `terraform/azure/container-apps.tf`: Ingress `internal_load_balancer_enabled = true` and `external_enabled = true` (VNET access required for Application Gateway)
- `terraform/azure/dns.tf`: DNS A record points to Application Gateway IP, remove Container Apps custom domain resources (TXT record, custom domain binding, managed certificate, bind/unbind actions)
- `terraform/azure/dns-private.tf`: Private DNS zone for custom domain (var.domain_name) with A record and VNET link
- `terraform/azure/security.tf`: NSG rules allowing Application Gateway → Container Apps traffic
- `terraform/azure/variables.tf`: Application Gateway, ACME, and certificate variables
- `terraform/azure/locals.tf`: Application Gateway resource naming
- `terraform/azure/outputs.tf`: Application Gateway public IP, FQDN, certificate expiry outputs
- `terraform/env/dev/terragrunt.hcl`: Dev-specific Application Gateway and ACME inputs
- `terraform/env/production/terragrunt.hcl`: Production-specific Application Gateway and ACME inputs

## Infrastructure Modifications Summary

**Changes to Existing Resources**:
1. Container Apps Environment: Set `internal_load_balancer_enabled = true` and `public_network_access = "Disabled"`
2. Container Apps Ingress: Set `external_enabled = true` (required for VNET access from Application Gateway, despite internal load balancer)
3. Container Apps Subnet: Changed from 10.240.1.0/24 to 10.240.0.0/23 (Microsoft requirement for subnet delegation)
4. Container Apps NSG: Add inbound rule allowing HTTP (port 80) from Application Gateway subnet (443→80 protocol change)
5. Private DNS zone: Create zone for custom domain (var.domain_name) with A record "@" pointing to Container Apps internal IP and VNET link
6. DNS A record (terraform/azure/dns.tf): Change from Container Apps static IP to Application Gateway public IP
7. Application Gateway Backend: Use HTTP (not HTTPS) for communication with Container Apps (private network, HTTPS only from client to gateway)

**New Resources**:
1. Application Gateway: Standard_v2 reverse proxy with HTTPS listener, HTTP backend settings, health probe
2. Application Gateway Public IP: Static IP for external access (zone-redundant in production)
3. ACME Account Registration: One-time account setup with Let's Encrypt (using `azuredns` provider, not deprecated `azure`)
4. ACME Certificate: Automated TLS certificate provisioning and renewal (uploaded to both Application Gateway and Container App Environment)
5. Container App Environment Certificate: Upload Let's Encrypt certificate to Container App Environment
6. Container App Custom Domain: Bind custom domain to Container App with certificate
7. WAF Policy: Optional (feature flag), can be attached to Standard_v2 gateway, OWASP CRS 3.2 protection

**Removed Resources from terraform/azure/dns.tf**:
1. `azurerm_dns_txt_record.verification` - Container Apps domain verification TXT record (not needed with Application Gateway)
2. `azurerm_container_app_custom_domain.main` - Custom domain binding to Container App (domain binds to Application Gateway instead)
3. `azapi_resource.managed_certificate` - Azure Managed Certificate (replaced by ACME/Let's Encrypt certificate)
4. `azapi_resource_action.bind_certificate` - Certificate binding action (not needed with Application Gateway)
5. `azapi_resource_action.unbind_certificate` - Certificate unbinding action (not needed with Application Gateway)

**Rationale for DNS Resource Removal**:
- Application Gateway handles SSL/TLS termination, not Container Apps
- Custom domain points to Application Gateway public IP, not Container Apps endpoint
- ACME provider manages certificates directly, no Azure Managed Certificate needed
- DNS A record remains in dns.tf but points to Application Gateway instead of Container Apps
- Azure DNS zone remains for ACME DNS-01 challenge validation

**Infrastructure Not Required** (per user feedback):
- Azure Key Vault: Not required - ACME provider manages certificates directly
- WAF_v2 SKU: Not required - Standard_v2 SKU used for both environments, WAF policy attached optionally
- Separate SKUs per environment: Both use Standard_v2 for consistency

## Complexity Tracking

**No violations of Navigator principles** - all deviations justified by requirements:

| Decision | Why Needed | Simpler Alternative Rejected Because |
|----------|------------|-------------------------------------|
| Application Gateway (vs direct Container Apps) | Defense-in-depth security requirement per spec FR-002, centralized SSL/TLS termination FR-007, WAF protection NFR-S-004 | Direct public Container Apps exposes application to internet threats (current state being fixed), no WAF protection, no centralized certificate management |
| Standard_v2 SKU (both environments) | Consistent SKU across environments simplifies management, WAF can be attached via policy without requiring WAF_v2 SKU | Different SKUs per environment would add unnecessary complexity and potential configuration drift |
| Zone-redundant deployment (production) | 99.95% uptime SLO (SLO-001), high availability requirement NFR-A-001 | Single-zone deployment risks downtime during zone failures, cannot meet availability SLO |
| Private DNS zone | Application Gateway must resolve Container Apps internal FQDN (FR-003), DNS resolution required for backend connectivity | Public DNS not usable for internal Container Apps endpoints, direct IP addressing breaks session affinity |
| ACME provider integration | Automated certificate provisioning and renewal required for operational efficiency, eliminates manual certificate management | Manual certificate upload requires operational overhead, risks certificate expiry, no automated renewal |

**Cost vs Security Trade-off**:
- Both environments use Standard_v2 SKU for consistency (~$150/month dev, ~$250/month production with zone redundancy)
- WAF feature flag allows incremental adoption: start without WAF, enable when ready (adds ~$150/month)
- ACME provider eliminates certificate purchase costs (Let's Encrypt free certificates)

**Adherence to "Design for Simplicity" Principle**:
✅ Single-region deployment
✅ No multi-region complexity
✅ No service mesh
✅ No custom modules (direct resources only)
✅ Minimal additional subnets (reuse existing Application Gateway subnet)
✅ Standard Azure-native patterns (no custom routing logic)

---

**Next Steps**:
1. Run `/iac.tasks` to break this plan into implementation tasks
2. OR run `/iac.enrichplan` for:
   - Deep research (Azure Well-Architected Framework analysis)
   - Detailed Application Gateway configuration examples
   - ACME provider integration patterns and best practices
   - Provisioning quickstart with validation steps
