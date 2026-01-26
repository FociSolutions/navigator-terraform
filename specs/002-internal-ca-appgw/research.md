# Infrastructure Research: Application Gateway + Internal Container Apps

**Branch**: `002-internal-ca-appgw` | **Date**: 2026-01-26 | **Plan**: [plan.md](./plan.md)

This document consolidates comprehensive research findings for implementing Azure Application Gateway as a reverse proxy for internal-only Container Apps, following Azure Well-Architected Framework principles and Terraform best practices.

---

## Technology Decisions

### Cloud Provider: Microsoft Azure

**Decision**: Microsoft Azure (canadacentral region)

**Rationale**:
- Canadian data residency requirement for Government of Canada applications
- Existing infrastructure already deployed on Azure (Container Apps, PostgreSQL, VNet)
- Azure Container Apps provides excellent managed compute for Phoenix/Elixir applications
- Azure Application Gateway Standard_v2 offers built-in WAF capabilities without separate service
- Azure Verified Modules (AVM) provide production-ready, officially maintained Terraform modules

**Alternatives Considered**:
- AWS: Rejected - data residency concerns, requires infrastructure migration
- GCP: Rejected - less mature managed container services compared to Azure Container Apps
- IBM Cloud: Considered but Azure's existing footprint and Government of Canada adoption preferred

### Infrastructure-as-Code Tool: Terraform + Terragrunt

**Decision**: Terraform 1.8+ (latest stable: 1.14.3) with Terragrunt for environment orchestration

**Rationale**:
- Existing codebase uses Terraform/Terragrunt for environment management
- Terraform has mature Azure provider (azurerm ~> 4.58) with comprehensive resource coverage
- Terragrunt enables DRY configuration across dev/production environments
- Azure Verified Modules published as Terraform modules
- Strong community support and documentation
- Declarative infrastructure-as-code enables version control and code review

**Alternatives Considered**:
- Azure Bicep: Rejected - team expertise in Terraform, harder to migrate existing infrastructure
- Pulumi: Rejected - less mature module ecosystem for Azure, learning curve for team
- ARM Templates: Rejected - verbose JSON syntax, less readable than HCL

### Provider Versions

**Current Versions** (from existing infrastructure):
- `hashicorp/azurerm ~> 4.0` (current: 4.58.0)
- `Azure/azapi ~> 2.0` (current: 2.8.0)
- `hashicorp/random ~> 3.0` (current: 3.8.0)

**New Providers** (for this feature):
- `vancluever/acme ~> 2.0` (latest: 2.43.0) - Let's Encrypt certificate automation

**Rationale**:
- azurerm 4.58: Latest stable version with Application Gateway v2 support, WAF policy resources
- azapi 2.8: Required for advanced Container Apps session affinity configuration
- random 3.8: Stable version for secret generation (database passwords, certificate passwords)
- acme 2.43.0: Latest with ARI (ACME Renewal Information) RFC 9773 support for optimized renewal

**Version Pinning Strategy**:
```hcl
# Development: Pessimistic constraint for patch updates
version = "~> 4.58"  # Gets 4.58.x patches, not 4.59.0

# Production: Exact pinning for stability
version = "= 4.58.0"  # Locks to exact version
```

---

## Azure Well-Architected Framework Analysis

The Azure Well-Architected Framework provides five foundational pillars. This section maps each pillar to our infrastructure components with specific best practices.

### 1. Reliability

**Principle**: Ensure your application can recover from failures and continue functioning as intended.

#### Application Gateway Reliability

**Zone Redundancy** (Critical for Production):
- Deploy Application Gateway with zone-redundant configuration across all 3 availability zones in canadacentral region
- Minimum 3 instances for production (one per zone) eliminates single points of failure
- During zone failure: traffic automatically redistributes to healthy zones within seconds
- Platform manages instance replacement and health monitoring automatically

**Health Probes** (Essential):
- Configure custom health probes to detect backend (Container Apps) unavailability
- Recommended settings: probe every 30 seconds with unhealthy threshold of 3 consecutive failures
- For WebSocket support: ensure probes don't interfere with persistent connections
- Use HTTP probe to `/` path matching Container Apps readiness probe

**Configuration Best Practices**:
- Set `request_timeout` to 180 seconds for long-lived WebSocket connections
- Enable HTTP/2 for client connections (improves Phoenix LiveView performance)
- Configure connection draining (30 seconds) for graceful replica shutdown
- Avoid User-Defined Routes (UDRs) on Application Gateway subnet to prevent health reporting issues

**Reference**: [Application Gateway Reliability Guide](https://learn.microsoft.com/en-us/azure/well-architected/service-guides/azure-application-gateway#reliability)

#### Container Apps Reliability

**Internal Ingress Configuration**:
- Internal-only ingress restricts access to within VNet/Container Apps environment
- Provides complete isolation from public internet while allowing Application Gateway to route traffic
- Combine with zone redundancy for production: distributes replicas across availability zones

**Scaling for Resilience**:
- Set minimum replica count ≥ 2 for production (never scale to zero for critical apps)
- Configure autoscaling with HTTP concurrent requests or CPU/memory metrics
- During zone failure: existing replicas in healthy zones continue serving traffic
- Scale-out is fast; scale-in respects connection draining

**Session Affinity Considerations**:
- If enabled: clients routed to failed zone instances will reconnect to new replicas
- State is lost from previous replicas - design stateless applications
- For Phoenix LiveView: consider external session store (Redis/Cosmos DB) for multi-replica deployments
- Configure Phoenix.PubSub for multi-node communication (Redis adapter recommended)

**WebSocket Support**:
- Container Apps natively support WebSocket over HTTP/1.1 and HTTP/2
- Internal ingress fully supports WebSocket connections
- No additional configuration required; Application Gateway forwards upgraded connections
- Session affinity ensures WebSocket connections stay on same backend replica

**Reference**: [Container Apps Reliability Guide](https://learn.microsoft.com/en-us/azure/reliability/reliability-container-apps)

#### PostgreSQL Flexible Server Reliability

**High Availability Options**:

1. **Zone-Redundant HA** (Recommended for Production):
   - Primary and standby servers in different availability zones
   - Synchronous replication with **RPO = 0** (no data loss)
   - **RTO < 120 seconds** for automatic failover
   - Protects against zone-level failures

2. **Same-Zone HA**:
   - Both servers in same zone (fallback when zone capacity unavailable)
   - Protects against node-level failures only
   - Same RTO/RPO guarantees

3. **Without HA** (Dev/Test Only):
   - 99.9% SLA vs 99.99% with HA
   - Locally redundant storage (3 copies within zone)
   - Automatic restart on failure but longer recovery time

**Backup Strategy**:
- Automated backups: Daily full + continuous transaction log backups
- Retention: 7 days for dev, 30 days for production
- Zone-redundant backup storage in regions with availability zones
- Point-in-time restore (PITR) for recovery from logical errors
- Consider geo-redundant backups for regional disaster recovery (select regions only)

**Connection Resilience**:
- Implement retry logic in Elixir application for transient failures
- Use connection pooling (PgBouncer) to reduce connection overhead
- Monitor connection limits and configure alerts (80% threshold)

**Reference**: [PostgreSQL Business Continuity](https://learn.microsoft.com/en-us/azure/postgresql/backup-restore/concepts-business-continuity)

### 2. Security

**Principle**: Protect applications and data from threats with strong security posture.

#### Application Gateway Security

**Web Application Firewall (WAF)**:
- Enable WAF for OWASP Top 10 protection (SQL injection, XSS, etc.)
- Start in Detection mode during tuning, then switch to Prevention mode for production
- Use latest managed rule sets (OWASP CRS 3.2, updated regularly by Microsoft)
- Enable bot protection rules to block malicious bots while allowing legitimate crawlers
- Configure rate limiting to prevent abuse and DDoS attacks
- Create custom rules for geo-filtering, IP blocking, and application-specific threats

**TLS/Certificate Management**:
- Integrate with Azure Key Vault for certificate storage (never embed in config)
- Enable automatic certificate rotation via Key Vault
- Use managed identity (user-assigned) for Application Gateway to access Key Vault
- Enforce TLS 1.2 minimum (TLS 1.0/1.1 deprecated August 31, 2025)
- Configure end-to-end TLS encryption (Application Gateway to Container Apps)
- For Let's Encrypt: automate renewal via ACME protocol with Key Vault integration

**Network Security**:
- Deploy in dedicated subnet with Network Security Groups (NSGs)
- NSG must allow GatewayManager traffic for health probes
- Lock down backend access: Container Apps internal ingress only accepts traffic from Application Gateway
- No public endpoint on Container Apps environment

**Reference**: [WAF Best Practices](https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/best-practices)

#### Container Apps Security

**Network Isolation**:
- Internal environment deployment eliminates public endpoints entirely
- VNet integration with dedicated subnets for Container Apps environment
- Configure NSG rules to allow only necessary traffic (Application Gateway subnet → Container Apps subnet)
- Private DNS zone for internal FQDN resolution

**Identity & Access**:
- Use managed identities for accessing Azure resources (Key Vault, Storage, PostgreSQL)
- Integrate with Microsoft Entra ID for authentication/authorization
- Apply RBAC with least privilege principle

**Data Protection**:
- Enable TLS termination at Application Gateway with re-encryption to backends
- Container Apps support mutual TLS (mTLS) for service-to-service authentication
- Encrypt secrets using Key Vault references in Container Apps configuration

**Supply Chain Security**:
- Use Microsoft Defender for Containers to scan images in Azure Container Registry
- Implement container-aware scanning in CI/CD pipelines
- Use minimal base images (Alpine, Chiselled Ubuntu) to reduce attack surface

**Reference**: [Container Apps Security](https://learn.microsoft.com/en-us/azure/container-apps/secure-deployment)

#### PostgreSQL Security

**Network Protection**:
- Deploy with private endpoint (no public IP address)
- Configure Azure Private DNS zone for private endpoint resolution
- Disable public network access entirely at server level
- Use VNet service endpoints or Private Link for application connectivity

**Authentication & Encryption**:
- Use Microsoft Entra authentication instead of SQL passwords where possible
- Enable TLS/SSL enforcement for all connections
- Use managed identities for passwordless connections from Container Apps
- Encrypt data at rest (enabled by default with platform-managed keys)
- Consider customer-managed keys (CMK) for backup encryption

**Access Control**:
- Apply RBAC for management plane operations
- Use database-level permissions following least privilege
- Enable audit logging for compliance and security monitoring

**Reference**: [PostgreSQL Security Overview](https://learn.microsoft.com/en-us/azure/postgresql/security/security-overview)

### 3. Cost Optimization

**Principle**: Maximize value while managing costs effectively.

#### General Cost Principles

**Dev vs Production Trade-offs**:

**Development Environment**:
- Single-zone deployment (no zone redundancy)
- Lower SKUs (Application Gateway: Standard_v2 with min instances)
- PostgreSQL: Burstable tier without HA
- Container Apps: scale to zero when idle
- Estimated Monthly Cost: ~$200-400

**Production Environment**:
- Zone-redundant for all services
- Right-sized SKUs based on actual load testing
- PostgreSQL: General Purpose or Memory Optimized with zone-redundant HA
- Container Apps: minimum 2+ replicas per zone
- Estimated Monthly Cost: ~$1,500-3,000 (varies by scale)

#### Application Gateway Cost Optimization

**Capacity Planning**:
- Use autoscaling with appropriate min/max instance counts (don't overprovision)
- Capacity units measure combined throughput, connections, and compute
- Monitor actual usage and adjust scaling rules quarterly
- Consider consumption-based billing for variable workloads vs reserved instances for predictable loads

**SKU Selection**:
- Standard_v2 provides autoscaling and zone redundancy
- WAF adds cost (~$150/month) but provides essential security (recommend for production)
- Evaluate if WAF features justify cost vs external WAF services

**Reference**: [Cost Optimization Guide](https://learn.microsoft.com/en-us/azure/well-architected/cost-optimization/optimize-component-costs)

#### Container Apps Cost Optimization

**Scaling Strategy**:
- Configure scale-to-zero for non-production and non-critical workloads
- Idle replicas billed at reduced rate (not zero)
- Set appropriate minimum replicas balancing availability vs cost
- Use event-driven scaling to match demand precisely

**Resource Allocation**:
- Right-size CPU and memory allocations per container
- Monitor actual usage and adjust resource requests
- Use consumption plan for variable workloads; dedicated plan for predictable usage

#### PostgreSQL Cost Optimization

**Compute & Storage**:
- Use Burstable tier for dev/test (B1ms, B2s)
- General Purpose for most production workloads
- Memory Optimized only when memory-intensive queries proven by metrics
- Start with smaller compute, monitor, then scale up if needed

**Storage Optimization**:
- IOPS scale with storage size; don't over-allocate storage for IOPS alone
- Monitor actual IOPS usage and adjust
- Backup retention: 7 days for dev, 30+ for production (storage cost increases with retention)

**Connection Pooling**:
- Built-in PgBouncer reduces connection overhead without additional VMs
- Alternative: deploy PgBouncer sidecar in Container Apps (no extra cost)
- Reduces CPU usage from connection management = potential for smaller compute tier

**Reference**: [PostgreSQL Service Guide](https://learn.microsoft.com/en-us/azure/well-architected/service-guides/postgresql)

### 4. Operational Excellence

**Principle**: Ensure smooth operations through monitoring, automation, and safe deployment practices.

#### Monitoring & Observability

**Application Gateway**:
- Enable diagnostic settings → send logs to Log Analytics workspace
- Key metrics: Backend response time, failed requests, unhealthy host count
- WAF logs critical for security monitoring (send to Microsoft Sentinel for SIEM)
- Configure Azure Monitor alerts for threshold breaches
- Use Application Insights integration for end-to-end tracing

**Container Apps**:
- Enable Log Analytics integration (built-in)
- Monitor: Replica count, request success rate, response times, system/app logs
- Configure health probes (liveness, readiness, startup) for automatic recovery
- Use Azure Monitor metrics for autoscaling decisions
- Implement distributed tracing (Application Insights/OpenTelemetry) for Elixir/Phoenix app

**PostgreSQL**:
- Enable Enhanced Metrics and Query Performance Insight
- Use Query Store to track query performance over time
- Monitor: CPU, memory, connections, IOPS, replication lag (if HA enabled)
- Configure alerts for connection limit (80% threshold), CPU (70%), storage (80%)
- Enable audit logging for compliance

**Centralized Logging**:
- Send all logs to single Log Analytics workspace
- Use Azure Workbooks for custom dashboards
- Integrate with Microsoft Sentinel for security correlation
- Retain logs based on compliance requirements (30-90 days typical)

**Reference**: [Observability Principles](https://learn.microsoft.com/en-us/azure/well-architected/operational-excellence/principles#evolve-operations-with-observability)

#### Infrastructure as Code (IaC)

**Best Practices**:
- Define all infrastructure as Terraform code
- Use Terragrunt for environment-specific configurations (dev/prod)
- Store state in Azure Storage with state locking
- Implement CI/CD pipelines (GitHub Actions/Azure DevOps) for automated deployments
- Use `terraform fmt`, `validate`, and `plan` in PR checks
- Run `trivy config` scan for security issues in Terraform code

**WAF Configuration as Code**:
- Define WAF policies, rule exclusions, custom rules in Terraform
- Enables versioning and easy updates across rule set versions
- Critical for maintaining consistent security posture

#### Deployment Strategy

**Safe Deployment Practices**:
- Use blue/green deployments for Container Apps (traffic splitting between revisions)
- Test new Container Apps revisions with 10% traffic before full cutover
- Application Gateway changes require 4-7 minutes for updates; plan maintenance windows
- PostgreSQL: test HA failover in non-production before relying on it

**Change Management**:
- Implement revision management for Container Apps
- Tag all resources consistently for tracking and cost allocation
- Use deployment slots concept via Container Apps revisions

**Reference**: [Deploy with Confidence](https://learn.microsoft.com/en-us/azure/well-architected/operational-excellence/principles#deploy-with-confidence)

### 5. Performance Efficiency

**Principle**: Maintain user experience under load through scaling and optimization.

#### Application Gateway Performance

**Scaling Configuration**:
- Enable autoscaling with min 3, max based on load testing
- Each instance handles ~10 capacity units minimum
- WAF enabled increases latency slightly (request buffering for inspection)
- Large file uploads (>30MB) can cause significant latency with WAF

**Backend Configuration**:
- Configure appropriate timeout values matching backend processing time
- Use HTTP/2 between Application Gateway and clients (enabled by default)
- Configure session affinity if application requires sticky sessions (Cookie-based)
- For WebSocket: health probes should use TCP probe type not HTTP

**Reference**: [Application Gateway Service Guide](https://learn.microsoft.com/en-us/azure/well-architected/service-guides/azure-application-gateway)

#### Container Apps Performance

**Scaling Rules**:
- HTTP scaling: Based on concurrent requests (default trigger)
- TCP scaling: For WebSocket connections (concurrent connections threshold)
- Custom scaling: CPU/memory metrics or event-driven (Service Bus, Kafka, etc.)
- Powered by KEDA - supports 50+ scalers

**Replica Management**:
- Default: min 0, max 10 replicas
- Production: min 2-3 replicas per zone for high availability
- Scale-out is fast; scale-in respects connection draining
- Trade-off: Higher minimum = better performance under sudden load but higher cost

**Phoenix/Elixir Specific**:
- Container Apps autoscaling works well with stateless Phoenix apps
- For LiveView with multiple replicas:
  - Use external session store (Redis/Cosmos DB)
  - Configure Phoenix.PubSub for multi-node communication (Redis adapter)
- WebSocket support: fully compatible with Phoenix Channels
- Set appropriate CPU/memory resources per container (start: 0.5 CPU, 1Gi memory)

**Reference**: [Container Apps Scaling](https://learn.microsoft.com/en-us/azure/container-apps/scale-app)

#### PostgreSQL Performance

**Query Optimization**:
- Use Query Store to identify expensive queries
- Enable Index Tuning for automatic index recommendations
- Use Intelligent Tuning to automatically optimize server parameters
- Analyze with EXPLAIN ANALYZE for query plan insights

**Connection Pooling** (Critical for Elixir/Phoenix):
- Elixir applications create many short-lived connections
- Built-in PgBouncer:
  - Enabled at server level
  - Transaction pooling mode (default)
  - Reduces connection overhead significantly
  - No additional infrastructure cost
- Alternative: PgBouncer sidecar in Container Apps for more control
- Configure appropriate pool size based on expected concurrent connections

**Read Replicas**:
- Deploy read replicas to offload read-only queries
- Useful for reporting, analytics workloads
- Asynchronous replication (some lag acceptable)

**Compute Sizing**:
- Start with General Purpose tier (2-4 vCores)
- Monitor CPU, memory, IOPS during load testing
- Scale vertically if consistent high utilization (>70% CPU sustained)
- Memory Optimized tier if memory-intensive queries (large sorts, joins)

**Reference**: [PostgreSQL Performance Guide](https://learn.microsoft.com/en-us/azure/well-architected/service-guides/postgresql#performance-efficiency)

---

## Curated Modules & Resources

### Approach: Direct Resources Preferred

**Decision**: Use direct `azurerm_*` resource blocks instead of Azure Verified Modules

**Rationale** (from Navigator principles):
- Principle: "Prefer Resource Simplicity" - Direct resources provide transparency and reduce indirection
- Direct resources make configuration explicit and enable straightforward troubleshooting
- Avoid module abstractions that obscure configuration details
- Modules add version management overhead (not captured in `.terraform.lock.hcl`)
- Team familiarity with direct resources from existing infrastructure

**When Modules Are Justified**:
1. Complex multi-resource patterns requiring validated composition
2. Organizational standards mandating specific module usage
3. Patterns requiring cross-resource validation logic impossible with individual resources

**For this infrastructure**: None of the above conditions apply. Application Gateway, Container Apps, and PostgreSQL configurations are straightforward enough for direct resources.

### Azure Verified Modules (AVM) Reference

While not using modules for this implementation, AVM modules are documented here for reference:

| Service | Module | Version | Status |
|---------|--------|---------|--------|
| Application Gateway | `Azure/avm-res-network-applicationgateway/azurerm` | 0.4.3 | Verified, 140K+ downloads |
| Virtual Network | `Azure/avm-res-network-virtualnetwork/azurerm` | 0.17.1 | Verified, 1.3M+ downloads |
| PostgreSQL Flexible Server | `Azure/avm-res-dbforpostgresql-flexibleserver/azurerm` | 0.1.4 | Verified, 136K+ downloads |
| Container Apps | `Azure/avm-res-app-containerapp/azurerm` | 0.7.4 | Verified, 109K+ downloads |

**Reference**: [Azure Verified Modules](https://aka.ms/avm)

### Direct Terraform Resources

**Recommended Approach** (per Navigator principles):

```hcl
# Application Gateway
resource "azurerm_application_gateway" "main" {
  name                = local.appgw_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  # Explicit configuration visible in code
  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = var.appgw_capacity_min
  }

  # ... other configuration
}

# Container Apps Environment
resource "azurerm_container_app_environment" "this" {
  name                           = local.cae_name
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  infrastructure_subnet_id       = azurerm_subnet.ca.id
  internal_load_balancer_enabled = true

  # ... other configuration
}

# PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "this" {
  name                = local.psql_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  version             = "16"

  # ... other configuration
}
```

**Resources Using Direct Blocks**:
- `azurerm_application_gateway` - Application Gateway configuration
- `azurerm_application_gateway_waf_policy` - WAF policy (optional)
- `azurerm_container_app_environment` - Container Apps environment
- `azurerm_container_app` - Navigator container app
- `azurerm_postgresql_flexible_server` - PostgreSQL database
- `azurerm_virtual_network` - VNet and subnets
- `azurerm_network_security_group` - NSG rules
- `azurerm_private_dns_zone` - Private DNS zones
- `azurerm_public_ip` - Application Gateway public IP

### Version Pinning Strategy

**Provider Versions** (pessimistic constraints for stability):
```hcl
terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.58" # Gets 4.58.x patches, not 4.59.0
    }

    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.8"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.8"
    }

    acme = {
      source  = "vancluever/acme"
      version = "~> 2.43"
    }
  }
}
```

**Development vs Production**:
- **Development**: Use `~> X.Y` constraints to get patch updates for testing
- **Production**: Consider exact pinning `= X.Y.Z` for critical infrastructure stability
- **Module Versions** (if used): Always exact pin `version = "X.Y.Z"` since modules are NOT captured in `.terraform.lock.hcl`

**Reference**: [Terraform Version Constraints](https://developer.hashicorp.com/terraform/language/expressions/version-constraints)

---

## ACME Provider Integration (Let's Encrypt)

### Configuration Overview

**Provider**: `vancluever/acme` version 2.43.0

**Features Used**:
- DNS-01 challenge for Azure DNS integration
- Automatic certificate renewal via `min_days_remaining`
- ARI (ACME Renewal Information) RFC 9773 support via `use_renewal_info = true`
- Ephemeral resources for private key handling (security best practice)

### DNS-01 Challenge Configuration

**Rationale**: DNS-01 challenge preferred over HTTP-01 because:
- Works with internal-only Container Apps (no public HTTP endpoint required)
- Supports wildcard certificates (future-proofing)
- More reliable for automated renewal (no dependency on application availability)

**Important Note**: The Azure provider name has changed from `azure` to `azuredns` in recent versions of the ACME provider. Use `azuredns` for DNS-01 challenges with Azure DNS.

**Configuration**:
```hcl
provider "acme" {
  server_url = var.acme_server_url
  # Dev: "https://acme-staging-v02.api.letsencrypt.org/directory"
  # Prod: "https://acme-v02.api.letsencrypt.org/directory"
}

resource "acme_certificate" "navigator" {
  count = var.domain_name != null ? 1 : 0

  account_key_pem = acme_registration.account.account_key_pem
  common_name     = var.domain_name

  # DNS-01 challenge using Azure DNS (provider name: azuredns)
  dns_challenge {
    provider = "azuredns"

    config = {
      AZURE_RESOURCE_GROUP = var.resource_group_name
      AZURE_ZONE_NAME      = var.domain_name
      # Authentication via Azure CLI or managed identity
    }
  }

  # Auto-renewal at 30 days before expiry (Let's Encrypt certs are 90-day validity)
  min_days_remaining = 30

  # Use ARI for optimized renewal timing
  use_renewal_info = true

  # Revoke on destroy
  revoke_certificate_on_destroy = true
}
```

### Certificate Lifecycle Automation

**Provisioning Workflow**:
1. ACME provider requests certificate from Let's Encrypt during `terraform apply`
2. DNS validation: ACME provider automatically creates DNS TXT record in Azure DNS zone
3. DNS-01 challenge: Let's Encrypt validates domain ownership via DNS query
4. Certificate issuance: Let's Encrypt issues certificate (valid 90 days)

**Renewal Workflow**:
1. ACME provider monitors certificate expiry in Terraform state
2. When `min_days_remaining` threshold reached (30 days before expiry):
   - Automatic renewal triggered on next `terraform apply`
   - New certificate provisioned using same DNS-01 challenge
   - Certificate uploaded to Application Gateway (zero-downtime rotation)
3. ARI (ACME Renewal Information) provides optimized renewal timing from Let's Encrypt

**Operational Considerations**:
- Terraform apply should run at least once every 60 days to catch renewal window
- Recommended: Scheduled Terraform apply via CI/CD (weekly or bi-weekly)
- Monitor certificate expiry with Azure Monitor alerts (30-day warning)
- Test renewal process in dev environment using staging ACME endpoint

### Security Best Practices

**Private Key Handling**:
```hcl
# ACME account key (stored in state, encrypted by Azure Storage)
resource "tls_private_key" "acme_account" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "acme_registration" "account" {
  account_key_pem = tls_private_key.acme_account.private_key_pem
  email_address   = var.acme_email_address
}

# Certificate private key: ephemeral resource, not stored in state
# Managed by ACME provider, uploaded to Application Gateway as P12
```

**Certificate Storage**:
- Certificate uploaded to Application Gateway directly from ACME provider
- P12 format with random password generated by `random_password` resource
- Certificate data stored in Terraform state (encrypted by Azure Storage Account encryption)
- Alternative: Store in Azure Key Vault for centralized certificate management

**Sensitive Variables**:
```hcl
variable "acme_email_address" {
  type        = string
  sensitive   = true  # Prevents output in logs
  description = "Email for ACME account registration and renewal notifications"
}
```

**Reference**: [ACME Provider Documentation](https://registry.terraform.io/providers/vancluever/acme/2.43.0/docs)

---

## Architecture-Specific Best Practices

### VNet & Networking Design

**Subnet Strategy** (from plan.md):
```
VNet: 10.240.0.0/16
├── Container Apps Subnet: 10.240.0.0/23 (Microsoft requirement for VNET delegation with internal load balancer)
├── PostgreSQL Subnet: 10.240.2.0/24 (private delegated subnet)
└── Application Gateway Subnet: 10.240.3.0/24 (dedicated, no NSG allowed)
```

**NSG Rules** (from Well-Architected Framework guidance):

*Container Apps NSG* (MODIFIED):
```
Inbound Rules (Priority Order):
1. Allow HTTP from Application Gateway subnet (10.240.3.0/24) → Port 80 [NEW - changed from HTTPS/443]
2. Allow PostgreSQL traffic from Container Apps subnet → Port 5432 [EXISTING]
3. Deny all other inbound traffic [EXISTING]

Outbound Rules:
- Allow all outbound (NAT Gateway for internet access) [EXISTING]
```

*Application Gateway Subnet*:
- No NSG allowed - Azure platform requirement for Application Gateway
- Security managed through Application Gateway configuration and backend NSG rules
- Must allow GatewayManager traffic for health probes (platform-managed)

**Private DNS Zones**:
- Create `<environment>.canadacentral.azurecontainerapps.io` for Container Apps internal FQDN
- A record `*` → Container Apps environment static IP
- Virtual Network Link to VNet for internal DNS resolution
- Enables Application Gateway to resolve Container Apps internal FQDN

**Reference**: [Networking Best Practices](https://learn.microsoft.com/en-us/azure/well-architected/security/networking)

### Zone-Redundant Deployment Pattern

**Production Configuration**:
```
Region: canadacentral (3 availability zones)

Application Gateway:
  - Zone-redundant: Yes (spans zones 1, 2, 3)
  - Min instances: 2 (production)
  - Autoscale max: 5

Container Apps Environment:
  - Zone-redundant: Yes
  - Container Apps:
    - Min replicas: 1 (production)
    - Max replicas: 5

PostgreSQL Flexible Server:
  - Zone-redundant HA: Enabled
  - Primary: Zone 1
  - Standby: Zone 2
  - Backup: Zone-redundant storage
```

**Expected Behavior During Zone Failure**:
- **Application Gateway**: Traffic redistributes within seconds; brief connection interruptions
- **Container Apps**: Replicas in failed zone lost; traffic routes to healthy zones; new replicas may spawn
- **PostgreSQL**: Automatic failover to standby in <120 seconds; no data loss (RPO=0)

**Reference**: [Application Gateway Reliability](https://learn.microsoft.com/en-us/azure/reliability/reliability-application-gateway-v2)

### WebSocket Support Configuration

**Application Gateway**:
- Enable HTTP/2: `enable_http2 = true`
- WebSocket protocol upgrade headers preserved automatically
- Session affinity ensures WebSocket connections stay on same backend replica
- Backend timeout configured for 180 seconds to prevent premature closure

**Container Apps**:
- Native WebSocket support over HTTP/1.1 and HTTP/2
- Internal ingress fully supports WebSocket connections
- No additional configuration required
- Session affinity (cookie-based) preserves Phoenix LiveView connection to specific replica

**Phoenix LiveView Considerations**:
- Multi-replica deployments require external session store (Redis/Cosmos DB)
- Configure Phoenix.PubSub for multi-node communication (Redis adapter)
- Health probes should not interfere with long-lived WebSocket connections

**Reference**: [Application Gateway WebSocket Support](https://learn.microsoft.com/en-us/azure/application-gateway/application-gateway-websocket)

---

## References

### Azure Well-Architected Framework
- **Framework Overview**: https://learn.microsoft.com/en-us/azure/well-architected/what-is-well-architected-framework
- **Pillars Summary**: https://learn.microsoft.com/en-us/azure/well-architected/pillars
- **Application Gateway Service Guide**: https://learn.microsoft.com/en-us/azure/well-architected/service-guides/azure-application-gateway
- **Container Apps Service Guide**: https://learn.microsoft.com/en-us/azure/well-architected/service-guides/azure-container-apps
- **PostgreSQL Service Guide**: https://learn.microsoft.com/en-us/azure/well-architected/service-guides/postgresql

### Reliability
- **Application Gateway Reliability**: https://learn.microsoft.com/en-us/azure/reliability/reliability-application-gateway-v2
- **Container Apps Reliability**: https://learn.microsoft.com/en-us/azure/reliability/reliability-container-apps
- **PostgreSQL High Availability**: https://learn.microsoft.com/en-us/azure/reliability/reliability-azure-database-postgresql
- **PostgreSQL Business Continuity**: https://learn.microsoft.com/en-us/azure/postgresql/backup-restore/concepts-business-continuity

### Security
- **WAF Best Practices**: https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/best-practices
- **Container Apps Security**: https://learn.microsoft.com/en-us/azure/container-apps/secure-deployment
- **PostgreSQL Security Overview**: https://learn.microsoft.com/en-us/azure/postgresql/security/security-overview
- **Key Vault Integration**: https://learn.microsoft.com/en-us/azure/application-gateway/key-vault-certs
- **Network Security Best Practices**: https://learn.microsoft.com/en-us/azure/well-architected/security/networking

### Performance
- **Container Apps Scaling**: https://learn.microsoft.com/en-us/azure/container-apps/scale-app
- **PostgreSQL Connection Pooling**: https://learn.microsoft.com/en-us/azure/postgresql/connectivity/concepts-connection-pooling-best-practices
- **Application Gateway WebSocket Support**: https://learn.microsoft.com/en-us/azure/application-gateway/application-gateway-websocket

### Terraform
- **Azure Verified Modules**: https://aka.ms/avm
- **azurerm Provider**: https://registry.terraform.io/providers/hashicorp/azurerm/4.58.0
- **azapi Provider**: https://registry.terraform.io/providers/Azure/azapi/2.8.0
- **ACME Provider**: https://registry.terraform.io/providers/vancluever/acme/2.43.0
- **Terraform Version Constraints**: https://developer.hashicorp.com/terraform/language/expressions/version-constraints
- **HashiCorp Style Guide**: https://developer.hashicorp.com/terraform/language/style

### Azure Documentation
- **Container Apps Overview**: https://learn.microsoft.com/azure/container-apps/
- **Container Apps Networking**: https://learn.microsoft.com/en-us/azure/container-apps/networking
- **PostgreSQL Flexible Server**: https://learn.microsoft.com/azure/postgresql/flexible-server/
- **Application Gateway Overview**: https://learn.microsoft.com/azure/application-gateway/
- **Private DNS Zones**: https://learn.microsoft.com/en-us/azure/dns/private-dns-overview

---

## Summary & Key Takeaways

**Technology Decisions**:
- ✅ Microsoft Azure (canadacentral) for data residency and existing infrastructure
- ✅ Terraform 1.14.3 + Terragrunt for Infrastructure-as-Code
- ✅ Direct `azurerm_*` resources instead of modules (per Navigator "Prefer Resource Simplicity" principle)
- ✅ ACME provider 2.43.0 for Let's Encrypt certificate automation

**Well-Architected Framework Alignment**:
- ✅ **Reliability**: Zone-redundant production deployment, health probes, automatic failover
- ✅ **Security**: WAF protection, TLS 1.2+, internal ingress, private endpoints
- ✅ **Cost Optimization**: Dev/prod differentiation, autoscaling, right-sized SKUs
- ✅ **Operational Excellence**: Centralized logging, IaC automation, blue/green deployments
- ✅ **Performance Efficiency**: Autoscaling, connection pooling, WebSocket support

**Curated Modules Approach**:
- ❌ Azure Verified Modules documented but NOT used (per Navigator principles)
- ✅ Direct Terraform resources provide transparency and maintainability
- ✅ Version pinning: `~> X.Y` for providers, exact `= X.Y.Z` for production stability

**ACME Certificate Automation**:
- ✅ DNS-01 challenge for internal-only infrastructure
- ✅ Automatic renewal at 30-day threshold (90-day Let's Encrypt certificates)
- ✅ ARI (ACME Renewal Information) for optimized renewal timing
- ✅ Ephemeral private key handling (security best practice)

**Next Steps**:
1. Proceed to Phase 1: Infrastructure Architecture Design (architecture.md)
2. Define provisioning guide (quickstart.md)
3. Update plan.md with research findings
4. Implement Terraform code following direct resource approach
