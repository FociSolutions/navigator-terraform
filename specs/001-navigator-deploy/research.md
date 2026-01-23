# Technology Research: Navigator Azure Deployment

**Date**: January 15, 2026  
**Branch**: `001-navigator-deploy`  
**Purpose**: Deep research for Azure infrastructure implementation using Well-Architected Framework principles and Azure Verified Modules

---

## Decision Summary

### Cloud Provider and IaC Tool

**Decision**: Microsoft Azure with Terraform 1.9+ (azurerm provider ~> 4.0)

**Rationale**:

- Azure provides managed container hosting (Azure Container Apps) comparable to AWS ECS Fargate
- Strong PostgreSQL Flexible Server offering with zone-redundant HA capabilities
- Excellent government cloud support (Canada Central region, data residency requirements)
- Terraform provides infrastructure-as-code consistency across cloud providers
- azurerm 4.0+ includes native Container Apps support without custom modules
- Strong Azure documentation and reference architectures for similar workloads

**Alternatives Considered**:

- **AWS**: Existing reference implementation (valentine-terraform) but migration not needed
- **Google Cloud Platform**: Strong Kubernetes (GKE) but requires more operational overhead
- **Pulumi**: Type-safe IaC but less mature ecosystem for Azure government workloads
- **Bicep**: Azure-native IaC but limits multi-cloud portability

**Version Constraints**:

- Terraform: >= 1.9.0 (latest stable as of January 2026)
- azurerm provider: ~> 4.0 (required for native Container Apps support)
- azapi provider: ~> 2.0 (required for session affinity and preview features)
- Azure CLI: >= 2.60.0 (for Container Apps commands)

---

## AzAPI Provider for Missing azurerm Features

### Overview

**What is the AzAPI Provider?**

The AzAPI provider is Microsoft's official Terraform provider that provides a **thin layer on top of Azure ARM REST APIs**. It complements the azurerm provider by enabling management of Azure resources and features that are not yet supported in azurerm, such as preview services, preview features, or recently released capabilities.

**Provider Details**:

- **Namespace**: Azure/azapi
- **Latest Version**: 2.8.0 (as of January 2026)
- **Registry**: https://registry.terraform.io/providers/Azure/azapi/latest
- **GitHub**: https://github.com/Azure/terraform-provider-azapi
- **Documentation**: https://registry.terraform.io/providers/Azure/azapi/latest/docs

### Why AzAPI for Navigator?

**Problem**: The `azurerm_container_app` resource **does NOT support session affinity (sticky sessions)** configuration, even though this feature is available in the Azure Container Apps service via the REST API.

**Azure Container Apps Session Affinity**:

- Required for WebSocket persistence (Phoenix LiveView real-time collaboration)
- Configured via `properties.configuration.ingress.stickySessions.affinity = "sticky"` in the Azure ARM API
- Available in Azure Portal, Azure CLI, and ARM/Bicep templates
- **NOT available** in azurerm provider (as of version 4.57.0)

**Solution**: Use AzAPI provider to configure session affinity alongside azurerm resources.

### Session Affinity Requirements

**Azure Documentation**: https://learn.microsoft.com/en-us/azure/container-apps/sticky-sessions

**Key Requirements**:

- Only supported in **single revision mode** (not multiple revision mode)
- Only supported when **ingress type is HTTP** (not TCP)
- Uses HTTP cookies to enforce stickiness
- Clients may be routed to new replica if previous replica becomes unavailable

**JSON Configuration Structure**:

```json
{
  "properties": {
    "configuration": {
      "ingress": {
        "external": true,
        "targetPort": 4000,
        "transport": "auto",
        "stickySessions": {
          "affinity": "sticky"
        }
      }
    }
  }
}
```

### Implementation Approach

**Recommended Pattern**: Hybrid azurerm + azapi approach

Use `azapi_resource_action` to patch the Container App after azurerm creates it:

```hcl
# Main Container App resource (azurerm provider)
resource "azurerm_container_app" "navigator" {
  name                = "nav-${var.environment}-ca-001"
  resource_group_name = var.resource_group_name
  # ... standard configuration ...

  ingress {
    external_enabled = true
    target_port      = 4000
    transport        = "auto"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }

    # Note: session_affinity not supported in azurerm provider
  }
}

# Session affinity configuration (azapi provider)
resource "azapi_resource_action" "navigator_session_affinity" {
  type        = "Microsoft.App/containerApps@2024-03-01"
  resource_id = azurerm_container_app.navigator.id

  body = jsonencode({
    properties = {
      configuration = {
        ingress = {
          stickySessions = {
            affinity = "sticky"
          }
        }
      }
    }
  })

  # Ensure this runs after Container App is created
  depends_on = [azurerm_container_app.navigator]
}
```

**Why This Approach**:

1. **Transparency**: Main resource defined in familiar azurerm syntax
2. **Minimal AzAPI Usage**: Only use AzAPI for the specific missing feature
3. **Maintainability**: When azurerm adds session_affinity support, easy to migrate
4. **State Management**: Both resources tracked in Terraform state

**Alternative Approach**: Full azapi_resource

Use `azapi_resource` for the entire Container App (not recommended unless multiple features are missing):

```hcl
resource "azapi_resource" "navigator" {
  type      = "Microsoft.App/containerApps@2024-03-01"
  parent_id = var.resource_group_id
  name      = "nav-${var.environment}-ca-001"

  body = jsonencode({
    properties = {
      managedEnvironmentId = azurerm_container_app_environment.main.id
      configuration = {
        ingress = {
          external      = true
          targetPort    = 4000
          transport     = "auto"
          stickySessions = {
            affinity = "sticky"
          }
        }
        # ... rest of configuration as JSON ...
      }
      template = {
        # ... template configuration as JSON ...
      }
    }
  })
}
```

**Drawbacks**:

- Less readable (raw JSON instead of HCL)
- Harder to maintain and review
- No IDE autocomplete or type checking
- More verbose

### Provider Configuration

**versions.tf**:

```hcl
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}
```

**provider.tf**:

```hcl
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "azapi" {
  # Uses same authentication as azurerm provider
  # Supports: Azure CLI, Managed Identity, Service Principal, OIDC
  subscription_id = var.subscription_id
}
```

**Authentication**: AzAPI uses the same authentication methods as azurerm:

- Azure CLI (`az login`)
- Managed Service Identity (for Azure resources)
- Service Principal with Client Secret
- Service Principal with Client Certificate
- OpenID Connect (OIDC) for GitHub Actions

### Version Pinning Strategy

**Development Environments**:

```hcl
azapi = {
  source  = "Azure/azapi"
  version = "~> 2.0"  # Allow minor version updates
}
```

**Production Environments**:

```hcl
azapi = {
  source  = "Azure/azapi"
  version = "= 2.8.0"  # Exact version pinning for stability
}
```

**Rationale**: AzAPI is actively developed with frequent updates as new Azure features are added. Exact version pinning prevents unexpected changes in production.

### When to Use AzAPI vs Waiting for azurerm Support

**Use AzAPI When**:

- Feature is **required for MVP** (session affinity for Navigator's WebSocket support)
- Feature is **stable in Azure** (generally available, not preview)
- azurerm support is **not planned or delayed** (check GitHub issues)
- Alternative workarounds are **more complex** (e.g., using Azure CLI in provisioners)

**Wait for azurerm Support When**:

- Feature is **nice-to-have** (not blocking MVP)
- azurerm support is **actively being developed** (PR in progress)
- Feature is **preview** (may change before GA)
- Workaround is **simple** (e.g., one-time manual configuration)

**Monitor for azurerm Support**:

- GitHub Issue Tracker: https://github.com/hashicorp/terraform-provider-azurerm/issues
- Search for: "container app session affinity" or "sticky sessions"
- When azurerm adds native support, migrate from azapi_resource_action to azurerm attribute

### Best Practices

1. **Minimize AzAPI Usage**: Use only for specific missing features, not entire resources
2. **Document API Versions**: Specify explicit API version in `type` field (e.g., `@2024-03-01`)
3. **Use depends_on**: Ensure azapi_resource_action runs after base resource creation
4. **Add Comments**: Explain why AzAPI is needed and when it can be removed
5. **Monitor azurerm Updates**: Check for native support in new azurerm releases
6. **Test Thoroughly**: AzAPI uses raw JSON - validate syntax and structure carefully

### References

- **AzAPI Provider Documentation**: https://registry.terraform.io/providers/Azure/azapi/latest/docs
- **Azure Container Apps REST API**: https://learn.microsoft.com/en-us/rest/api/containerapps/
- **Session Affinity Documentation**: https://learn.microsoft.com/en-us/azure/container-apps/sticky-sessions
- **AzAPI GitHub Examples**: https://github.com/Azure/terraform-provider-azapi/tree/main/examples
- **Microsoft Terraform Extension**: https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-azureterraform (includes AzAPI IntelliSense)

---

## Azure Well-Architected Framework

The Azure Well-Architected Framework provides **5 pillars** that guide architectural excellence. This section maps each pillar to Navigator infrastructure components with specific best practices.

### Reference

- **Documentation**: https://learn.microsoft.com/en-us/azure/well-architected/pillars
- **Assessment Tool**: https://learn.microsoft.com/en-us/assessments/azure-architecture-review/
- **Azure Advisor Integration**: Automated recommendations based on Well-Architected principles

### Pillar 1: Reliability

**Workload Concern**: Resiliency, availability, recovery

**Applicable Design Principles**:

1. **Design for business requirements**: Target 99.9% availability for internal tools (not mission-critical)
2. **Design for resilience**: Zone-redundant deployments for production, single-zone acceptable for dev
3. **Design for recovery**: Automated backups, point-in-time restore, health checks
4. **Keep it simple**: Avoid multi-region complexity unless explicitly required

**Mapped to Navigator Components**:

| Component          | Baseline (Dev)              | Enhanced (Production)                     | Rationale                                          |
| ------------------ | --------------------------- | ----------------------------------------- | -------------------------------------------------- |
| **Container Apps** | Single-zone, scale to zero  | Zone-redundant, min 1 replica             | Dev: Cost optimization; Prod: High availability    |
| **PostgreSQL**     | Single-zone, Burstable B1ms | Zone-redundant HA, General Purpose D2s_v3 | Dev: Acceptable downtime; Prod: Automatic failover |
| **Backups**        | 7-day retention             | 14-day retention, geo-redundant optional  | Business continuity requirements                   |
| **Health Probes**  | HTTP liveness probe on /    | HTTP liveness + readiness probes          | Detect and recover from failures                   |

**Best Practices from Microsoft Learn**:

- Use zone-redundant HA for PostgreSQL (RTO < 120s, RPO = 0)
- Configure automated backups with point-in-time restore (1-minute granularity)
- Enable Application Insights for production monitoring and distributed tracing
- Implement graceful degradation for non-critical features

**References**:

- https://learn.microsoft.com/en-us/azure/well-architected/reliability/principles
- https://learn.microsoft.com/en-us/azure/reliability/reliability-postgresql-flexible-server

---

### Pillar 2: Security

**Workload Concern**: Data protection, threat detection, mitigation

**Applicable Design Principles**:

1. **Protect confidentiality**: Private endpoints, TLS 1.2+ enforcement, managed identities
2. **Protect integrity**: Encryption at rest and in transit, RBAC, audit logging
3. **Protect availability**: Network Security Groups, DDoS protection (optional), WAF (optional)

**Mapped to Navigator Components**:

| Component                | Security Control       | Implementation                                                                                                                                                                 |
| ------------------------ | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Network Isolation**    | VNet integration       | Container Apps subnet (10.240.1.0/24), PostgreSQL subnet (10.240.2.0/24)                                                                                                       |
| **Data Encryption**      | At rest                | AES-256 (Microsoft-managed keys) for PostgreSQL and Storage                                                                                                                    |
| **Data Encryption**      | In transit             | TLS 1.2+ enforced for internet-facing traffic (HTTPS ingress); PostgreSQL TLS optional (disabled by default, network isolation via private endpoint provides primary security) |
| **Secrets Management**   | Container Apps secrets | Platform-encrypted secrets stored in Container Apps, accessible only to running app instances                                                                                  |
| **Access Control**       | Managed Identities     | Container Apps system-assigned identity for ACR access (AcrPull role)                                                                                                          |
| **Network Security**     | NSG rules              | Container Apps: Allow 443 inbound, PostgreSQL: Allow 5432 from Container Apps subnet only                                                                                      |
| **Private Connectivity** | Private endpoints      | PostgreSQL private endpoint (no public internet access)                                                                                                                        |

**Best Practices from Microsoft Learn**:

- **Use Azure Private Link** for PostgreSQL (eliminates public internet exposure)
- **Deploy Container Apps in custom VNet** for network control and isolation
- **Enable NSG flow logs** for traffic monitoring and threat detection
- **Use managed identities** instead of connection strings for Azure service authentication
- **Use Container Apps secrets** for sensitive configuration (platform-encrypted, isolated per app instance)
- **Implement defense in depth**: Multiple security layers (NSG, private endpoints, TLS, RBAC)

**Security Compliance (Government of Canada)**:

- Event logging per GC Event Logging Guidance
- Incident management aligned with GC CSEMP (Cyber Security Event Management Plan)
- Patch management following GC Patch Management Guidance
- Canadian Centre for Cyber Security IT Security Risk Management (ITSG-22, ITSG-38)

**References**:

- https://learn.microsoft.com/en-us/azure/well-architected/security/principles
- https://learn.microsoft.com/en-us/azure/container-apps/secure-deployment
- https://learn.microsoft.com/en-us/azure/postgresql/security/security-overview

---

### Pillar 3: Cost Optimization

**Workload Concern**: Cost modeling, budgets, reduce waste

**Applicable Design Principles**:

1. **Optimize on usage**: Right-size SKUs, auto-shutdown schedules, scale to zero
2. **Optimize on rate**: Use reservations for predictable workloads, avoid overprovisioning

**Mapped to Navigator Components**:

| Component          | Baseline (Dev)                   | Enhanced (Production)                   | Monthly Cost Estimate                 |
| ------------------ | -------------------------------- | --------------------------------------- | ------------------------------------- |
| **Container Apps** | 0.25 vCPU, 0.5 GB, scale to zero | 0.5 vCPU, 1.0 GB, min 1 replica         | Dev: $10-20; Prod: $50-100            |
| **PostgreSQL**     | Burstable B1ms (1 vCore, 2 GB)   | General Purpose D2s_v3 (2 vCores, 8 GB) | Dev: $12-15; Prod: $150-200           |
| **Storage**        | 32 GB, Standard LRS              | 128 GB, Standard ZRS                    | Dev: $3-5; Prod: $15-25               |
| **Networking**     | Basic VNet, no NAT Gateway       | Standard VNet, optional NAT Gateway     | Dev: $2-5; Prod: $10-30               |
| **Monitoring**     | Container Apps default metrics   | Application Insights                    | Dev: $0; Prod: $20-50                 |
| **TOTAL**          |                                  |                                         | **Dev: $27-45/mo; Prod: $245-405/mo** |

**Cost Optimization Best Practices**:

- **Dev/Test**: Auto-shutdown schedules (evenings, weekends) to reduce runtime costs
- **Production**: Use Azure Reservations for PostgreSQL (1-year or 3-year commitment for 30-40% savings)
- **Monitoring**: Use Azure Cost Management + Infracost for cost estimation in Terraform
- **Storage**: Implement lifecycle management (archive to Cool tier after 90 days, delete after 365 days)
- **Right-sizing**: Monitor actual usage with Azure Monitor, adjust SKUs based on real workload patterns

**References**:

- https://learn.microsoft.com/en-us/azure/well-architected/cost-optimization/principles
- https://azure.microsoft.com/en-us/pricing/calculator/

---

### Pillar 4: Operational Excellence

**Workload Concern**: Holistic observability, DevOps practices

**Applicable Design Principles**:

1. **Streamline operations with standards**: Infrastructure-as-code, GitOps workflows, standardized naming
2. **Comprehensive monitoring**: Centralized logging, distributed tracing, alerting
3. **Safe deployment practices**: Blue-green deployments, automated validation, rollback capability

**Mapped to Navigator Components**:

| Practice                   | Implementation                                                  | Benefit                                   |
| -------------------------- | --------------------------------------------------------------- | ----------------------------------------- |
| **Infrastructure as Code** | Terraform with Terragrunt orchestration                         | Repeatable deployments, version control   |
| **Validation**             | `terraform validate`, `terraform plan`, Trivy security scanning | Catch errors before deployment            |
| **Monitoring**             | Application Insights, Log Analytics workspace                   | Centralized logs, performance metrics     |
| **Deployment**             | GitHub Actions with OIDC authentication                         | No long-lived secrets, automated CI/CD    |
| **Environment Promotion**  | dev → staging → production                                      | Validate changes before production        |
| **Observability**          | Container Apps default metrics + Application Insights APM       | Troubleshoot issues, optimize performance |

**Best Practices from Microsoft Learn**:

- **Enable diagnostics settings** for Container Apps environments (send logs to Log Analytics)
- **Use GitHub OIDC** instead of service principal credentials for CI/CD authentication
- **Implement health probes** (liveness, readiness, startup) for automatic recovery
- **Configure Azure Monitor alerts** for critical metrics (CPU, memory, failed requests)
- **Use Log Analytics** for centralized log aggregation across Container Apps and PostgreSQL

**References**:

- https://learn.microsoft.com/en-us/azure/well-architected/operational-excellence/principles
- https://learn.microsoft.com/en-us/azure/container-apps/log-options

---

### Pillar 5: Performance Efficiency

**Workload Concern**: Scalability, load testing

**Applicable Design Principles**:

1. **Scale horizontally**: Auto-scaling based on CPU/memory, scale out at 70% utilization
2. **Test early and often**: Load testing in staging environment before production
3. **Monitor health**: Track p95 latency, throughput, database query performance

**Mapped to Navigator Components**:

| Component          | Scaling Strategy                                                | Performance Target                              |
| ------------------ | --------------------------------------------------------------- | ----------------------------------------------- |
| **Container Apps** | CPU-based auto-scaling (70% threshold)                          | < 2s page load time for 50-100 concurrent users |
| **PostgreSQL**     | Vertical scaling (vCore increase), pgBouncer connection pooling | < 500ms database p95 latency                    |
| **Storage**        | Auto-grow enabled for production                                | Low-latency blob access for user uploads        |
| **Networking**     | Session affinity for WebSocket persistence                      | Real-time collaboration without disconnects     |

**Best Practices from Microsoft Learn**:

- **Use pgBouncer** (built-in PostgreSQL Flexible Server feature) for connection pooling
- **Enable query performance insights** for PostgreSQL troubleshooting
- **Configure session affinity** for Container Apps to support WebSocket sticky sessions
- **Monitor with Container Apps metrics**: Request latency, replica count, CPU/memory usage

**References**:

- https://learn.microsoft.com/en-us/azure/well-architected/performance-efficiency/principles
- https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-query-performance-insight

---

## Azure Verified Modules (AVM)

### Overview

**What are Azure Verified Modules?**
Azure Verified Modules are **Microsoft-maintained, pre-defined Terraform modules** that follow Well-Architected Framework best practices. They provide standardized, tested infrastructure patterns with automated documentation and compliance.

**Module Registry**: https://registry.terraform.io/namespaces/Azure  
**GitHub**: https://github.com/Azure/Azure-Verified-Modules  
**Documentation**: https://azure.github.io/Azure-Verified-Modules/

### Module Development Process

Microsoft applies rigorous development standards:

1. **Design and Specification**: Architectural and security standards compliance
2. **Coding and Implementation**: Strict coding standards for Terraform
3. **Automated Testing**: Unit and integration tests for functionality and reliability
4. **Documentation Generation**: Automatically generated docs for each module
5. **Review and Approval**: Azure engineers review for quality and security

### Version Pinning Recommendations

**CRITICAL for Production Stability**:

- Terraform modules are **NOT captured in `.terraform.lock.hcl`** (only providers are locked)
- **Development**: Use `~> X.Y` for testing minor updates (e.g., `~> 1.2` allows 1.2.x)
- **Production**: Use **exact version pinning** `= X.Y.Z` (e.g., `version = "= 0.7.1"`) to prevent breaking changes

### Relevant Modules for Navigator Infrastructure

Based on research, the following Azure Verified Modules are available and applicable:

| Component                      | Module Name                              | Registry URL                                                                                      | Recommendation                                                                       |
| ------------------------------ | ---------------------------------------- | ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| **Container Apps**             | `avm-res-app-containerapp`               | https://registry.terraform.io/modules/Azure/avm-res-app-containerapp/azurerm/latest               | ❌ **NOT RECOMMENDED** - Direct `azurerm_container_app` provides better transparency |
| **Container Apps Environment** | `avm-res-app-managedenvironment`         | https://registry.terraform.io/modules/Azure/avm-res-app-managedenvironment/azurerm/latest         | ❌ **NOT RECOMMENDED** - Simple single-resource pattern                              |
| **PostgreSQL Flexible Server** | `avm-res-dbforpostgresql-flexibleserver` | https://registry.terraform.io/modules/Azure/avm-res-dbforpostgresql-flexibleserver/azurerm/latest | ❌ **NOT RECOMMENDED** - Direct `azurerm_postgresql_flexible_server` sufficient      |
| **Virtual Network**            | `avm-res-network-virtualnetwork`         | https://registry.terraform.io/modules/Azure/avm-res-network-virtualnetwork/azurerm/latest         | ❌ **NOT RECOMMENDED** - VNet + subnets straightforward with direct resources        |
| **Private Endpoint**           | `avm-res-network-privateendpoint`        | https://registry.terraform.io/modules/Azure/avm-res-network-privateendpoint/azurerm/latest        | ❌ **NOT RECOMMENDED** - Single-resource module adds unnecessary abstraction         |
| **Application Insights**       | `avm-res-insights-component`             | https://registry.terraform.io/modules/Azure/avm-res-insights-component/azurerm/latest             | ❌ **NOT RECOMMENDED** - Simple resource with minimal configuration                  |

### Module Usage Decision: **Direct Resources Preferred**

**UPDATED DECISION** (January 16, 2026): After comprehensive re-evaluation requested by stakeholders, the recommendation remains unchanged: **Use direct `azurerm_*` resources for ALL Navigator infrastructure components.**

For complete analysis including component-by-component benefit assessment, cost-benefit analysis, and production deployment scenarios, see: [avm-reevaluation.md](./avm-reevaluation.md)

**Executive Summary of Re-Evaluation**:

While Azure Verified Modules (AVMs) provide Microsoft-supported, WAF-aligned modules with built-in testing, the analysis found:

❌ **No concrete production benefits** for Navigator's scale (50-100 users, 6 core resources)
❌ **Significant complexity overhead** (12-23 hours additional learning curve, 2-3x longer debugging time)
❌ **Pre-release instability** (ALL modules < 1.0.0, breaking changes expected)
❌ **No compliance advantage** (GC baseline security controls met with direct resources)
❌ **Inferior operational transparency** (module-generated resource names, abstraction layers)

**Key Findings by Component**:

| Component          | AVM Module Version  | Recommendation         | Key Justification                                                     |
| ------------------ | ------------------- | ---------------------- | --------------------------------------------------------------------- |
| Virtual Network    | 0.7.x (pre-release) | ✅ **Direct Resource** | Module adds 20+ lines overhead for 3 static subnets. No IPAM benefit. |
| Container Apps Env | 0.4.x (pre-release) | ✅ **Direct Resource** | Uses `azapi` provider. Diagnostic settings not worth 50-var overhead. |
| Container App      | 0.4.x (pre-release) | ✅ **Direct Resource** | 100+ module variables for simple app config. No health probe benefit. |
| PostgreSQL         | 0.6.x (pre-release) | ✅ **Direct Resource** | Module doesn't simplify HA configuration. Pre-release version risk.   |
| Container Registry | 0.4.x (pre-release) | ✅ **Direct Resource** | Geo-replication not needed. Vulnerability scanning not automated.     |

**Rationale for Direct Resources** (original analysis still valid):

1. **Principle Alignment**: Navigator Infrastructure Principles v3.0.0 "Prefer Resource Simplicity" - Navigator infrastructure is **baseline complexity**

2. **Transparency and Maintainability**: Direct resources make configuration **explicit and visible** in code (critical for GC audit trail)

3. **Simplicity and Learning**: Direct resources enable understanding exact Azure configuration without module abstraction layers

4. **No Complex Patterns**: Infrastructure does NOT require multi-resource composition with complex validation

5. **Version Management Overhead**: Modules add version pinning requirements (not captured in `.terraform.lock.hcl`)

6. **Pre-Release Risk**: ALL AVM modules are pre-release (`< 1.0.0`) with breaking changes expected per AVM documentation

**Cost-Benefit Quantitative Analysis**:

| Metric                     | Direct Resources | AVM Modules    | Difference   |
| -------------------------- | ---------------- | -------------- | ------------ |
| Initial Development Time   | 8-12 hours       | 20-35 hours    | +12-23 hours |
| Learning Curve             | 4-6 hours        | 12-23 hours    | +8-17 hours  |
| Debugging Time (per issue) | 30 min           | 60-90 min      | +2-3x        |
| Upgrade Time (per module)  | 30 min           | 2-4 hours      | +4-8x        |
| Lines of Code              | ~200 lines       | ~250-300 lines | +25-50%      |

**When to Reconsider Modules**:

- **Multi-region deployment** (2+ regions with failover)
- **10+ Azure resources per environment** (hub-spoke topology)
- **Shared services pattern** (5+ dependent infrastructure stacks)
- **AVM reaches GA (1.0.0)** with concrete benefits demonstrated

For Navigator's current scope (single-region, 50-100 users, 6 core resources): **Direct resources remain optimal.**

**Example: Direct Resource vs Module**

Direct Resource (Preferred for Navigator):

```hcl
resource "azurerm_postgresql_flexible_server" "main" {
  name                   = "nav-${var.environment}-postgres"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  version                = "16"
  delegated_subnet_id    = azurerm_subnet.postgres.id
  private_dns_zone_id    = azurerm_private_dns_zone.postgres.id
  administrator_login    = "navadmin"
  administrator_password = random_password.postgres.result
  zone                   = var.availability_zone
  storage_mb             = var.postgres_storage_gb * 1024
  sku_name               = var.postgres_sku
  backup_retention_days  = var.backup_retention_days

  high_availability {
    mode                      = var.postgres_ha_enabled ? "ZoneRedundant" : "Disabled"
    standby_availability_zone = var.postgres_ha_enabled ? var.standby_availability_zone : null
  }
}
```

Module Approach (NOT recommended for Navigator baseline):

```hcl
module "postgresql" {
  source  = "Azure/avm-res-dbforpostgresql-flexibleserver/azurerm"
  version = "= 0.4.2"  # MUST pin exact version - not in .terraform.lock.hcl

  name                = "nav-${var.environment}-postgres"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  # ... 30+ additional module-specific variables ...
  # Requires understanding module interface, variable names, defaults
  # Debugging requires reading module source code
}
```

**Decision**: Use **direct `azurerm_*` resources exclusively** for Navigator infrastructure.

### References

- https://learn.microsoft.com/en-us/community/content/azure-verified-modules
- https://azure.github.io/Azure-Verified-Modules/
- https://registry.terraform.io/namespaces/Azure

---

## Azure Container Apps Best Practices

### Architecture Patterns

**Container Apps Overview**:

- **Serverless container hosting** with built-in auto-scaling (including scale to zero)
- **Consumption plan** (baseline) vs **Workload profiles** (enhanced for dedicated resources)
- **VNet integration** for private networking and secure communication
- **Managed certificates** for HTTPS with automatic renewal

### Networking Best Practices

**Reference**: https://learn.microsoft.com/en-us/azure/well-architected/service-guides/azure-container-apps

| Best Practice                                 | Implementation for Navigator                                                                | Rationale                                                 |
| --------------------------------------------- | ------------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| **Deploy in custom VNet**                     | Container Apps subnet (10.240.1.0/24, delegated to Microsoft.App/environments)              | Control network traffic, integrate with private resources |
| **Use internal ingress for backend services** | External ingress for public web app (Navigator is internet-facing)                          | Allow public access while maintaining backend security    |
| **Configure NSG rules**                       | Allow 443 inbound (public app), restrict outbound to Azure services + internet (OpenAI API) | Least-privilege network access                            |
| **Enable HTTPS-only ingress**                 | TLS 1.2+ enforcement, HTTP redirects to HTTPS                                               | Protect data in transit                                   |
| **Use managed certificates**                  | Container Apps Managed Certificates (free, auto-renewal)                                    | Simplify TLS certificate management                       |
| **Configure health probes**                   | HTTP liveness probe on "/" endpoint                                                         | Automatic restart of unhealthy containers                 |
| **Enable session affinity**                   | Sticky sessions for WebSocket support                                                       | Real-time collaboration requires persistent connections   |

**Subnet Sizing**:

- **Consumption-only environments**: Minimum `/23` (512 IPs) - base 60 IPs reserved + scale
- **Workload profiles**: Minimum `/27` (32 IPs) - smaller footprint for dedicated profiles
- **Navigator**: Use `/24` (256 IPs) to accommodate future scaling

**Private Endpoint Support**:

- Container Apps can use **private endpoints** for inbound access (internal load balancer)
- Navigator is a **public web application** - external ingress required (documented Trivy suppression)

### Security Best Practices

**Reference**: https://learn.microsoft.com/en-us/azure/container-apps/secure-deployment

| Security Control                         | Navigator Implementation                                                    |
| ---------------------------------------- | --------------------------------------------------------------------------- |
| **VNet Integration**                     | Deploy Container Apps Environment in custom VNet (10.240.0.0/16)            |
| **Managed Identity**                     | System-assigned managed identity for ACR image pull (AcrPull role)          |
| **Container Registry Authentication**    | Use managed identity for ACR image pull (AcrPull role)                      |
| **Secrets Management**                   | Container Apps secrets for all sensitive configuration (platform-encrypted) |
| **NSG Flow Logs**                        | Enable for Container Apps subnet (audit traffic, detect anomalies)          |
| **Azure Firewall (Optional)**            | Use UDR to route outbound traffic through Azure Firewall for inspection     |
| **Application Gateway + WAF (Optional)** | Enhanced protection for production (OWASP rule sets)                        |

### Deployment and Scaling Best Practices

| Practice            | Baseline (Dev)                 | Enhanced (Production)                              |
| ------------------- | ------------------------------ | -------------------------------------------------- |
| **Min Replicas**    | 0 (scale to zero)              | 1 (always available)                               |
| **Max Replicas**    | 2                              | 10                                                 |
| **Scaling Trigger** | HTTP concurrency (10 requests) | CPU-based (70% utilization)                        |
| **Resource Limits** | 0.25 vCPU, 0.5 GB memory       | 0.5 vCPU, 1.0 GB memory                            |
| **Ingress**         | External (public internet)     | External with Application Gateway + WAF (optional) |
| **Revision Mode**   | Single (latest revision)       | Multiple (blue-green deployments)                  |

**Startup and Health Configuration**:

```hcl
resource "azurerm_container_app" "navigator" {
  # ...
  template {
    container {
      name   = "navigator"
      image  = var.container_image
      cpu    = var.container_cpu
      memory = var.container_memory

      liveness_probe {
        transport = "HTTP"
        path      = "/"
        port      = 4000
        initial_delay_seconds = 10
        period_seconds        = 30
        timeout_seconds       = 5
        failure_threshold     = 3
      }

      # Optional: Startup probe for slow-starting applications
      startup_probe {
        transport = "HTTP"
        path      = "/"
        port      = 4000
        initial_delay_seconds = 0
        period_seconds        = 10
        timeout_seconds       = 5
        failure_threshold     = 30  # Allow 5 minutes for startup
      }
    }

    min_replicas = var.min_replicas
    max_replicas = var.max_replicas
  }

  ingress {
    external_enabled = true
    target_port      = 4000
    transport        = "http"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }

    # Note: session_affinity not supported in azurerm provider
    # Use azapi_resource_action to configure sticky sessions
    # See "AzAPI Provider for Missing azurerm Features" section above
  }
}

# Session affinity configuration (azapi provider)
resource "azapi_resource_action" "navigator_session_affinity" {
  type        = "Microsoft.App/containerApps@2024-03-01"
  resource_id = azurerm_container_app.navigator.id

  body = jsonencode({
    properties = {
      configuration = {
        ingress = {
          stickySessions = {
            affinity = "sticky"
          }
        }
      }
    }
  })

  depends_on = [azurerm_container_app.navigator]
}
```

### Code Sample References

**Terraform Code Sample** (from Microsoft Learn):

```hcl
# Note: Azure Container Apps Terraform resources use azurerm provider
# Full Terraform module examples NOT available in AVM for Container Apps
# Use direct azurerm resources as shown in Terraform documentation
```

Microsoft Learn provides primarily **Azure CLI** and **Bicep** examples for Container Apps. Terraform users should reference:

- **azurerm provider documentation**: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app
- **Azure Verified Modules** (if choosing module approach): https://registry.terraform.io/modules/Azure/avm-res-app-containerapp/azurerm/latest

### References

- https://learn.microsoft.com/en-us/azure/well-architected/service-guides/azure-container-apps
- https://learn.microsoft.com/en-us/azure/container-apps/secure-deployment
- https://learn.microsoft.com/en-us/azure/container-apps/networking
- https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets

---

## Azure Database for PostgreSQL Flexible Server

### High Availability and Reliability

**Reference**: https://learn.microsoft.com/en-us/azure/well-architected/service-guides/postgresql

| HA Configuration        | RTO      | RPO              | Use Case               | Monthly Cost Impact                 |
| ----------------------- | -------- | ---------------- | ---------------------- | ----------------------------------- |
| **Single-zone (no HA)** | 5-15 min | < 5 min          | Development, testing   | Baseline (e.g., $12-15/mo for B1ms) |
| **Same-zone HA**        | < 120s   | 0 (no data loss) | Production (single AZ) | +60% (~$20-25/mo for B1ms)          |
| **Zone-redundant HA**   | < 120s   | 0 (no data loss) | Production (multi-AZ)  | +60% (~$20-25/mo for B1ms)          |

**How Zone-Redundant HA Works**:

1. Primary server in Availability Zone 1, standby replica in Availability Zone 2
2. **Synchronous replication** - data written to both primary and standby before commit
3. **Automatic failover** - standby promoted to primary within 60-120 seconds (no manual intervention)
4. **New standby created** in original primary zone after failover

**Configuration Example**:

```hcl
resource "azurerm_postgresql_flexible_server" "main" {
  name                   = "nav-${var.environment}-postgres"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  version                = "16"  # Latest stable PostgreSQL version
  delegated_subnet_id    = azurerm_subnet.postgres.id
  private_dns_zone_id    = azurerm_private_dns_zone.postgres.id
  administrator_login    = "navadmin"
  administrator_password = random_password.postgres.result
  zone                   = "1"  # Primary availability zone
  storage_mb             = var.postgres_storage_gb * 1024
  sku_name               = var.postgres_sku  # e.g., "B_Standard_B1ms" or "GP_Standard_D2s_v3"
  backup_retention_days  = var.backup_retention_days  # 7 (dev) or 14 (prod)

  # High Availability configuration (production only)
  dynamic "high_availability" {
    for_each = var.postgres_ha_enabled ? [1] : []
    content {
      mode                      = "ZoneRedundant"
      standby_availability_zone = "2"
    }
  }

  # Auto-grow storage (production)
  storage_tier = var.environment == "production" ? "P30" : null

  lifecycle {
    prevent_destroy = var.environment == "production" ? true : false
  }
}
```

### Backup and Restore

**Automated Backup Features**:

- **Daily full backups**: Automatic snapshots of database files
- **Continuous transaction log backups**: WAL (Write-Ahead Log) archiving to Azure Blob Storage
- **Retention**: 7-35 days (configurable)
- **Point-in-time restore**: Restore to any point within retention period (1-minute granularity)
- **Geo-redundant backup**: Optional (enabled at server creation, cannot be changed later)

**Best Practices**:

- **Development**: 7-day retention (minimize cost)
- **Production**: 14-day retention (business continuity requirements)
- **Geo-redundancy**: Enable for production if disaster recovery across regions is required
- **Testing**: Regularly test backup restore to validate RTO/RPO

**Restore Time Estimates**:

- **Small database** (< 10 GB): 5-15 minutes
- **Medium database** (10-100 GB): 15-60 minutes
- **Large database** (100+ GB): 1-12 hours (depends on size and log recovery)

### Performance and Optimization

**SKU Selection**:

| Tier                 | SKU Example        | vCores | Memory | Use Case                   | Monthly Cost (Canada Central) |
| -------------------- | ------------------ | ------ | ------ | -------------------------- | ----------------------------- |
| **Burstable**        | B_Standard_B1ms    | 1      | 2 GB   | Dev/test, low traffic      | ~$12-15                       |
| **Burstable**        | B_Standard_B2s     | 2      | 4 GB   | Small production           | ~$25-30                       |
| **General Purpose**  | GP_Standard_D2s_v3 | 2      | 8 GB   | Production (50-100 users)  | ~$150-200                     |
| **General Purpose**  | GP_Standard_D4s_v3 | 4      | 16 GB  | High-traffic production    | ~$300-400                     |
| **Memory Optimized** | MO_Standard_E2s_v3 | 2      | 16 GB  | Memory-intensive workloads | ~$200-250                     |

**Navigator Recommendation**:

- **Development**: `B_Standard_B1ms` (1 vCore, 2 GB) - $12-15/month
- **Production**: `GP_Standard_D2s_v3` (2 vCores, 8 GB) - $150-200/month

**pgBouncer Connection Pooling**:

- **Built-in feature** of PostgreSQL Flexible Server (no separate deployment)
- **Purpose**: Reduce connection overhead, improve throughput
- **Configuration**: Enable via `pgbouncer.enabled` server parameter
- **Pool modes**: Transaction pooling (recommended for web apps) vs Session pooling

**Query Performance Insights**:

- **Enable**: `pg_stat_statements` extension + Azure Monitor integration
- **Metrics**: Top queries by execution time, CPU usage, I/O wait
- **Optimization**: Identify slow queries, create indexes, adjust configurations

### Security Best Practices

**Private Networking** (Recommended):

```hcl
# Private DNS zone for PostgreSQL
resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.main.name
}

# Link DNS zone to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "postgres-vnet-link"
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.main.id
  resource_group_name   = azurerm_resource_group.main.name
}

# PostgreSQL subnet with delegation
resource "azurerm_subnet" "postgres" {
  name                 = "snet-postgres"
  virtual_network_name = azurerm_virtual_network.main.name
  resource_group_name  = azurerm_resource_group.main.name
  address_prefixes     = ["10.240.2.0/24"]
  service_endpoints    = ["Microsoft.Storage"]

  delegation {
    name = "postgresql-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# PostgreSQL server with VNet integration
resource "azurerm_postgresql_flexible_server" "main" {
  # ...
  delegated_subnet_id = azurerm_subnet.postgres.id
  private_dns_zone_id = azurerm_private_dns_zone.postgres.id
  # No public access - accessible only from VNet
}
```

**SSL/TLS Enforcement** (Optional):

- **Default**: Set `require_secure_transport = off` to match AWS reference architecture
- **Configurable**: Can be enabled via `var.postgres_require_ssl` variable for enhanced security
- **When enabled**: Set `ssl_min_protocol_version = TLSv1.2` for minimum TLS 1.2+
- **Client configuration**: Connection string uses `sslmode=disable` by default, or `sslmode=require` when TLS enabled
- **Security Note**: Network isolation via private endpoint (delegated subnet) provides primary security control; TLS provides additional defense-in-depth when enabled

**Managed Identity Authentication** (Optional):

- PostgreSQL Flexible Server supports **Microsoft Entra ID (Azure AD) authentication**
- Container Apps can authenticate using **managed identity** (eliminates passwords)
- **Setup**: Create Azure AD admin, grant database roles to managed identity
- **Connection**: Use `DefaultAzureCredential` in application code

### Code Sample References

**Terraform Code Sample** (from Microsoft Learn):

```hcl
resource "azurerm_postgresql_flexible_server" "default" {
  name                   = "${random_pet.name_prefix.id}-server"
  resource_group_name    = azurerm_resource_group.default.name
  location               = azurerm_resource_group.default.location
  version                = "13"
  delegated_subnet_id    = azurerm_subnet.default.id
  private_dns_zone_id    = azurerm_private_dns_zone.default.id
  administrator_login    = "adminTerraform"
  administrator_password = random_password.pass.result
  zone                   = "1"
  storage_mb             = 32768
  sku_name               = "GP_Standard_D2s_v3"
  backup_retention_days  = 7

  depends_on = [azurerm_private_dns_zone_virtual_network_link.default]
}

resource "azurerm_postgresql_flexible_server_database" "default" {
  name      = "${random_pet.name_prefix.id}-db"
  server_id = azurerm_postgresql_flexible_server.default.id
  collation = "en_US.utf8"
  charset   = "UTF8"
}
```

**Reference**: https://learn.microsoft.com/en-us/azure/developer/terraform/deploy-postgresql-flexible-server-database

### References

- https://learn.microsoft.com/en-us/azure/well-architected/service-guides/postgresql
- https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-high-availability
- https://learn.microsoft.com/en-us/azure/postgresql/backup-restore/concepts-backup-restore
- https://learn.microsoft.com/en-us/azure/postgresql/security/security-overview

---

## Azure Networking Best Practices

### Virtual Network Design

**Reference**: https://learn.microsoft.com/en-us/azure/well-architected/service-guides/virtual-network

**Navigator VNet Architecture**:

```
VNet: 10.240.0.0/16 (Canada Central)
├── snet-container-apps: 10.240.1.0/24 (delegated to Microsoft.App/environments)
├── snet-postgres: 10.240.2.0/24 (delegated to Microsoft.DBforPostgreSQL/flexibleServers)
└── snet-appgateway: 10.240.3.0/24 (for future Application Gateway, optional)
```

**Subnet Sizing Best Practices**:

- **Avoid small subnets**: Use /24 or larger to allow for growth
- **Avoid /16 waste**: Don't allocate unnecessarily large address spaces
- **Plan for scale**: Container Apps reserves 60 base IPs + additional IPs per revision
- **Service delegation**: Required for Container Apps and PostgreSQL Flexible Server

**Address Space Selection**:

- **Avoid conflicts**: 10.240.0.0/16 avoids common on-premises ranges (10.0.0.0/8, 172.16.0.0/12)
- **Government networks**: Coordinate with GC IT to avoid conflicts with on-premises infrastructure

### Network Security Groups (NSG)

**Best Practices**:

1. **Deny by default, permit by exception**: Create restrictive NSG rules
2. **Apply NSGs to subnets** (not individual NICs) for centralized management
3. **Use service tags**: Reference Azure services by tag (CognitiveServices, AzureMonitor) instead of IP ranges
4. **Enable NSG flow logs**: Capture traffic for monitoring and threat detection
5. **Document exceptions**: Trivy findings for unrestricted rules should include business justification

**Container Apps NSG Rules**:

```hcl
resource "azurerm_network_security_group" "container_apps" {
  name                = "nsg-container-apps"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Inbound: Allow HTTPS from internet (public web application)
  security_rule {
    name                       = "AllowHttpsInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"  # Public internet - documented business justification
    destination_address_prefix = "VirtualNetwork"
  }

  # Outbound: Allow HTTPS to Azure services
  security_rule {
    name                       = "AllowAzureServicesOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefixes = [
      "CognitiveServices",  # For OpenAI API
      "AzureMonitor",
      "AzureContainerRegistry"
    ]
  }

  # Outbound: Allow PostgreSQL access
  security_rule {
    name                       = "AllowPostgresOutbound"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = "10.240.1.0/24"  # Container Apps subnet
    destination_address_prefix = "10.240.2.0/24"  # PostgreSQL subnet
  }

  # Outbound: Conditional internet access for OpenAI API
  dynamic "security_rule" {
    for_each = var.enable_outbound_internet ? [1] : []
    content {
      name                       = "AllowInternetOutbound"
      priority                   = 120
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "Internet"
    }
  }
}

# Associate NSG with Container Apps subnet
resource "azurerm_subnet_network_security_group_association" "container_apps" {
  subnet_id                 = azurerm_subnet.container_apps.id
  network_security_group_id = azurerm_network_security_group.container_apps.id
}
```

**PostgreSQL NSG Rules**:

```hcl
resource "azurerm_network_security_group" "postgres" {
  name                = "nsg-postgres"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Inbound: Allow PostgreSQL from Container Apps subnet only
  security_rule {
    name                       = "AllowPostgresInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = "10.240.1.0/24"  # Container Apps subnet
    destination_address_prefix = "10.240.2.0/24"  # PostgreSQL subnet
  }

  # Outbound: Deny all (database does not initiate outbound connections)
  security_rule {
    name                       = "DenyAllOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
```

### Private Endpoints and Private Link

**When to Use Private Endpoints**:

- **PostgreSQL**: Highly recommended (eliminates public internet exposure)
- **Storage Account**: Optional for production (if used for user uploads)
- **Container Apps**: Navigator is public web app - external ingress required

**Private Endpoint Configuration**:

```hcl
# Private endpoint for PostgreSQL (using VNet integration instead)
# PostgreSQL Flexible Server uses delegated subnet, not private endpoint
# Configuration shown in PostgreSQL section above
```

**Benefits of Private Endpoints**:

1. **Eliminates public internet exposure**: Traffic stays on Azure backbone network
2. **Reduces attack surface**: No public IP addresses to protect
3. **Simplified security**: No need for IP allowlisting or firewall rules
4. **Cross-region connectivity**: Access services in other regions via Azure backbone

### DNS Configuration

**Private DNS Zones**:

- Required for private endpoint resolution (e.g., `privatelink.postgres.database.azure.com`)
- Must be linked to VNet for name resolution
- Overrides public DNS resolution with private IP addresses

**Custom Domain for Container Apps**:

```hcl
# Azure DNS zone for custom domain
resource "azurerm_dns_zone" "main" {
  name                = var.domain_name  # e.g., "navigator-dev.demo.focisolutions.com"
  resource_group_name = azurerm_resource_group.main.name
}

# A record pointing to Container Apps default domain or Application Gateway
resource "azurerm_dns_a_record" "container_app" {
  name                = "@"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = [azurerm_container_app.navigator.ingress[0].ip_address]
}

# Custom domain for Container Apps
resource "azurerm_container_app_custom_domain" "main" {
  container_app_id = azurerm_container_app.navigator.id
  name             = var.domain_name
  certificate_binding_type = "SniEnabled"

  # Use Container Apps Managed Certificate (free, automatic renewal)
  lifecycle {
    ignore_changes = [certificate_id]
  }
}
```

### Trivy Security Findings and Suppressions

**Common Trivy Findings for Navigator NSG Configuration**:

| Finding                                                   | Severity | Navigator Justification                                                                                                                                                                                               | Suppression                 |
| --------------------------------------------------------- | -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------- |
| **AVD-AZU-0047**: NSG allows unrestricted inbound access  | CRITICAL | Navigator is a **public web application** requiring internet access on port 443. This is intentional design.                                                                                                          | Documented in `security.tf` |
| **AVD-AZU-0051**: NSG allows unrestricted outbound access | HIGH     | Outbound rules use **Azure service tags** (CognitiveServices, AzureMonitor) for least-privilege access. Internet access (443) required for OpenAI API integration, controlled by `enable_outbound_internet` variable. | Documented in `security.tf` |

**Suppression Example**:

```hcl
#trivy:ignore:AVD-AZU-0047 Navigator is a public web application requiring internet access on HTTPS port 443
resource "azurerm_network_security_rule" "allow_https_inbound" {
  # ... unrestricted source 0.0.0.0/0 is intentional for public app
}

#trivy:ignore:AVD-AZU-0051 Outbound rules use Azure service tags for least-privilege access; internet access required for OpenAI API
resource "azurerm_network_security_rule" "allow_internet_outbound" {
  # ... controlled by enable_outbound_internet variable
}
```

### References

- https://learn.microsoft.com/en-us/azure/well-architected/service-guides/virtual-network
- https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview
- https://learn.microsoft.com/en-us/azure/private-link/private-link-overview
- https://learn.microsoft.com/en-us/azure/security/fundamentals/network-best-practices

---

## Implementation Recommendations

### Module vs Direct Resource Decision

**FINAL RECOMMENDATION**: Use **direct `azurerm_*` resources exclusively** for Navigator infrastructure.

**Rationale**:

1. **Principle alignment**: "Prefer Resource Simplicity" (v3.0.0) prioritizes direct resources as default
2. **Baseline complexity**: Navigator infrastructure is simple - no complex multi-resource patterns
3. **Transparency**: Direct resources make all configuration visible and explicit
4. **Learning**: Baseline (dev) environments prioritize maximum simplicity for learning
5. **No compelling module use case**: Azure Verified Modules do not provide significant value over direct resources for this architecture

**When to Reconsider**:

- Enhanced (production) environments with complex hub-spoke networking (10+ subnets, multi-region)
- Organizational mandate for standardized AVM usage across Government of Canada deployments
- Pattern reuse across 5+ identical Navigator deployments

### Terraform Provider Versions

**Recommended Versions**:

```hcl
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = var.environment == "production" ? true : false
    }
  }
}
```

**Version Pinning Strategy**:

- **Providers**: Use `~> X.Y` to allow patch updates (e.g., `~> 4.0` allows 4.0.x, 4.1.x but not 5.0.0)
- **Modules** (if used): Use exact version `= X.Y.Z` for production (e.g., `version = "= 0.7.1"`)
- **Lock file**: Commit `.terraform.lock.hcl` to version control

### Security Scanning with Trivy

**Integration in CI/CD**:

```yaml
# .github/workflows/terraform-plan.yml
- name: Run Trivy security scan
  uses: aquasecurity/trivy-action@master
  with:
    scan-type: "config"
    scan-ref: "terraform/"
    format: "sarif"
    output: "trivy-results.sarif"
    severity: "CRITICAL,HIGH"

- name: Upload Trivy results to GitHub Security
  uses: github/codeql-action/upload-sarif@v2
  with:
    sarif_file: "trivy-results.sarif"
```

**Common Findings and Suppressions**:

- Document suppressions with `#trivy:ignore:<RULE_ID>` and business justification
- Security review required for all suppressed findings
- Update suppressions when architecture changes

### State Management

**Azure Blob Storage Backend**:

```hcl
# terraform/env/dev/terragrunt.hcl
remote_state {
  backend = "azurerm"
  config = {
    resource_group_name  = "navigator-tfstate-rg"
    storage_account_name = "navtfstatedev"
    container_name       = "tfstate"
    key                  = "navigator.terraform.tfstate"
    use_azuread_auth     = true  # Use Azure AD authentication (no storage access keys)
  }
}
```

**Best Practices**:

- **Separate state per environment**: `navtfstatedev`, `navtfstateprod`
- **Enable versioning**: Blob versioning for state file history (30-day retention)
- **Enable soft delete**: 14-day retention for accidental deletion recovery
- **RBAC**: Storage Blob Data Contributor for CI/CD, Storage Blob Data Reader for developers
- **Encryption**: Microsoft-managed keys (default), customer-managed keys optional for compliance

---

## Cost Estimation Summary

| Environment     | Container Apps | PostgreSQL | Networking | Storage | Monitoring | **Total (Monthly)** |
| --------------- | -------------- | ---------- | ---------- | ------- | ---------- | ------------------- |
| **Development** | $10-20         | $12-15     | $2-5       | $3-5    | $0         | **$27-45**          |
| **Production**  | $50-100        | $150-200   | $10-30     | $15-25  | $20-50     | **$245-405**        |

**Cost Optimization Strategies**:

- **Development**: Auto-shutdown schedules (evenings, weekends) can reduce costs by 50-70%
- **Production**: Azure Reservations for PostgreSQL (1-year commitment) saves 30-40%
- **Monitoring**: Use Azure Monitor included quota before enabling Application Insights

**Tools**:

- **Azure Pricing Calculator**: https://azure.microsoft.com/en-us/pricing/calculator/
- **Infracost**: Terraform cost estimation in CI/CD
- **Azure Cost Management**: Real-time cost tracking and budget alerts

---

## Next Steps

1. **Phase 1: Architecture Design** → Create `architecture.md` with detailed infrastructure specifications
2. **Phase 1: Module Specifications** → Create `modules.md` if custom modules are required (SKIPPED - using direct resources)
3. **Phase 1: Provisioning Guide** → Create `quickstart.md` with step-by-step deployment instructions
4. **Update plan.md** → Incorporate research findings into architecture plan
5. **Agent Context Update** → Run `.specify/scripts/bash/update-agent-context.sh opencode`

**Implementation Phase** (after enrichment):

- Run `/iac.implement` to generate Terraform code based on architecture plan
- Validate with `terraform validate` and `trivy config terraform/`
- Deploy to development environment first, then promote to production

---

## Azure Container Apps Managed Certificates

### Problem Statement

**Issue Discovered**: January 23, 2026  
**Tasks**: T053-T054 (Custom domain with managed certificate binding)

When attempting to bind a custom domain to Azure Container Apps with an Azure-managed certificate using Terraform, the following issues were encountered:

1. **azurerm provider limitation**: The `azurerm_container_app_custom_domain` resource documentation suggests omitting `container_app_environment_certificate_id` to use Azure managed certificates, but this approach does not automatically create the managed certificate
2. **azurerm_container_app_environment_certificate limitation**: This resource only supports user-provided certificates (PFX/PEM files) and Key Vault certificates - it does NOT support creating Azure-managed certificates
3. **State mismatch**: Custom domain was added but remained in `Disabled` binding state instead of being bound with a managed certificate

### Root Cause Analysis

**Azure CLI Behavior** (Working):
```bash
az containerapp hostname add --hostname <domain> ...       # Adds domain without binding
az containerapp hostname bind --hostname <domain> ...      # Creates managed cert AND binds it
```

The `hostname bind` command performs two operations:
1. Creates a managed certificate resource: `Microsoft.App/managedEnvironments/managedCertificates/{name}`
2. Updates the container app custom domain with `bindingType: "SniEnabled"` and `certificateId`

**Terraform Behavior** (Not Working):
```hcl
resource "azurerm_container_app_custom_domain" "main" {
  container_app_id = azurerm_container_app.navigator.id
  name             = var.domain_name
  # Omitting certificate_id per docs - expecting auto-managed cert

  lifecycle {
    ignore_changes = [certificate_binding_type, container_app_environment_certificate_id]
  }
}
```

**Problem**: The `azurerm` provider has no resource to create managed certificates, and `azurerm_container_app_custom_domain` does not trigger certificate creation when `certificate_id` is omitted.

### Solution: Hybrid Approach (azapi + azurerm)

**Strategy**: Use `azapi_resource` to create the managed certificate (since azurerm doesn't support it), then bind using `azurerm_container_app_custom_domain`.

**Implementation** (terraform/azure/dns.tf):

```hcl
# T053: Azure Managed Certificate for Custom Domain
# Uses azapi provider because azurerm_container_app_environment_certificate only supports
# user-provided certificates (PFX/PEM) and Key Vault certificates, not Azure-managed certificates
resource "azapi_resource" "managed_certificate" {
  count = var.domain_name != null ? 1 : 0

  type      = "Microsoft.App/managedEnvironments/managedCertificates@2024-03-01"
  name      = replace(var.domain_name, ".", "-")  # Certificate name: dots replaced with hyphens
  parent_id = azurerm_container_app_environment.main.id
  location  = var.location

  body = jsonencode({
    properties = {
      subjectName             = var.domain_name
      domainControlValidation = "HTTP"  # HTTP validation for apex domains with A records
    }
  })

  depends_on = [
    azurerm_dns_a_record.container_app,
    azurerm_dns_txt_record.verification
  ]

  tags = merge(var.tags, {
    Environment = var.environment
    Name        = "managed-certificate-${var.domain_name}"
  })

  timeouts {
    create = "20m"  # Certificate provisioning takes 10-15 minutes for DigiCert validation
    delete = "10m"
  }
}

# T054: Bind custom domain to Container App with managed certificate
# Uses native azurerm resource for type-safe configuration
resource "azurerm_container_app_custom_domain" "main" {
  count = var.domain_name != null ? 1 : 0

  container_app_id                         = azurerm_container_app.navigator.id
  name                                     = var.domain_name
  container_app_environment_certificate_id = azapi_resource.managed_certificate[0].id
  certificate_binding_type                 = "SniEnabled"

  depends_on = [
    azapi_resource.managed_certificate
  ]
}
```

### Key Technical Details

**Certificate Naming**:
- Replace dots with hyphens: `navigator-dev.demo.focisolutions.com` → `navigator-dev-demo-focisolutions-com`
- Must be unique within the Container Apps Environment
- Alphanumeric characters and hyphens only

**Validation Method**:
- **HTTP validation** for apex domains with A records (e.g., `navigator-dev.demo.focisolutions.com`)
- **CNAME validation** for subdomains with CNAME records (e.g., `www.example.com`)
- DigiCert performs validation from their IP addresses (must be publicly accessible)

**API Version**:
- `2024-03-01` is the stable API version supporting managed certificates
- Newer preview versions (e.g., `2025-10-02-preview`) also available but not required

**Provisioning Timeline**:
- DNS propagation: 1-5 minutes
- DigiCert validation: 5-15 minutes
- Certificate issuance and binding: 1-2 minutes
- **Total**: 10-20 minutes on first deployment

### Advantages of Hybrid Approach

| Aspect | Hybrid Approach | Pure azapi Approach | Pure azurerm Approach |
|--------|----------------|-------------------|---------------------|
| **Certificate Creation** | ✅ azapi_resource | ✅ azapi_resource_action | ❌ Not supported |
| **Domain Binding** | ✅ azurerm native resource | ⚠️ azapi PATCH operations | ✅ azurerm native resource |
| **Type Safety** | ✅ Typed binding resource | ❌ JSON body encoding | ✅ Fully typed |
| **State Management** | ✅ Clean resource state | ⚠️ Action-based state | ❌ Doesn't work |
| **Code Complexity** | ✅ 2 resources | ⚠️ 3 resources | ❌ 1 resource (broken) |

### Validation

After deployment, verify the certificate:

```bash
# Check managed certificate status
az containerapp env certificate list \
  --name <environment-name> \
  --resource-group <resource-group> \
  --managed-certificates-only \
  --output table

# Verify custom domain binding
az containerapp show \
  --name <app-name> \
  --resource-group <resource-group> \
  --query "properties.configuration.ingress.customDomains" \
  --output json

# Test HTTPS connectivity
curl -I https://<custom-domain>

# Verify certificate details
openssl s_client -connect <custom-domain>:443 -servername <custom-domain> < /dev/null 2>/dev/null | \
  openssl x509 -noout -issuer -subject -dates
```

Expected results:
- Certificate status: `Succeeded`
- Binding type: `SniEnabled`
- HTTPS response: Valid SSL/TLS certificate
- Issuer: DigiCert

### Prerequisites Checklist

Before deploying managed certificates:

- ✅ DNS zone created in Azure DNS (or external DNS provider configured)
- ✅ A record pointing to Container Apps Environment static IP
- ✅ TXT record (`asuid.<domain>`) with Container App verification ID
- ✅ Domain publicly accessible over HTTP (for DigiCert validation)
- ✅ No CAA records blocking DigiCert (or CAA record explicitly allowing `digicert.com`)
- ✅ Container App has external ingress enabled
- ✅ azapi provider configured in terraform/azure/versions.tf

### References

- **Microsoft Learn**: https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-managed-certificates
- **Azure API Reference**: https://learn.microsoft.com/en-us/rest/api/containerapps/managed-certificates
- **GitHub Issue #796** (Container Apps managed certs): https://github.com/microsoft/azure-container-apps/issues/796
- **Terraform azurerm Provider**: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app_custom_domain
- **Terraform azapi Provider**: https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/azapi_resource

---

**Document Version**: 1.1.0  
**Last Updated**: January 23, 2026  
**Research Sources**: Microsoft Learn, Azure Well-Architected Framework, Azure Verified Modules, Terraform Registry, Azure Container Apps GitHub Issues
