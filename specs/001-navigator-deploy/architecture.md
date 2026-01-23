# Detailed Infrastructure Architecture: Navigator Azure Deployment

**Date**: January 15, 2026 (Updated: January 20, 2026)  
**Branch**: `001-navigator-deploy`  
**Reference**: Based on research.md findings and plan.md decisions

---

## Architecture Overview

This document provides detailed specifications for each infrastructure component of the Navigator Azure deployment. The architecture follows Azure Well-Architected Framework principles with **direct Terraform resources (no modules)** for maximum transparency.

**Module Strategy Update (January 16, 2026)**: After comprehensive re-evaluation of Azure Verified Modules (AVM), the recommendation remains to use direct `azurerm_*` resources exclusively. See [avm-reevaluation.md](./avm-reevaluation.md) for complete analysis including component-by-component cost-benefit assessment and production deployment scenarios.

**Architecture Diagram** (Logical):

```
Internet
    │
    ▼
[HTTPS:443]
    │
    ▼
┌────────────────────────────────────────────────────────────┐
│ Azure VNet: 10.240.0.0/16 (Canada Central)                 │
│                                                            │
│  ┌───────────────────────────────────────────────────┐     │
│  │ Subnet: snet-container-apps (10.240.1.0/24)       │     │
│  │ Delegation: Microsoft.App/environments            │     │
│  │                                                   │     │
│  │  ┌──────────────────────────────────────────┐     │     │
│  │  │ Container Apps Environment               │     │     │
│  │  │ - Log Analytics Workspace                │     │     │
│  │  │                                          │     │     │
│  │  │  ┌────────────────────────────┐          │     │     │
│  │  │  │ Navigator Container App    │          │     │     │
│  │  │  │ - Phoenix/Elixir App       │          │     │     │
│  │  │  │ - Port 4000                │          │     │     │
│  │  │  │ - Managed Identity         │          │     │     │
│  │  │  │ - Auto-scaling (CPU)       │          │     │     │
│  │  │  │ - Container Apps Secrets   │          │     │     │
│  │  │  └────────────────────────────┘          │     │     │
│  │  └──────────────────────────────────────────┘     │     │
│  │                                                   │     │
│  │  NSG: Allow 443 inbound, Azure services +         │     │
│  │       PostgreSQL + Internet outbound              │     │
│  └───────────────────────────────────────────────────┘     │
│                                                            │
│              │                                             │
│              │ Private connectivity (5432)                 │
│              ▼                                             │
│  ┌───────────────────────────────────────────────────┐     │
│  │ Subnet: snet-postgres (10.240.2.0/24)             │     │
│  │ Delegation: Microsoft.DBforPostgreSQL/...         │     │
│  │                                                   │     │
│  │  ┌──────────────────────────────────────┐         │     │
│  │  │ PostgreSQL Flexible Server           │         │     │
│  │  │ - Version 16                         │         │     │
│  │  │ - Private (delegated subnet)         │         │     │
│  │  │ - Zone-redundant HA (prod)           │         │     │
│  │  │ - Automated backups (14 days)        │         │     │
│  │  └──────────────────────────────────────┘         │     │
│  │                                                   │     │
│  │  NSG: Allow 5432 from Container Apps only,        │     │
│  │       Deny all outbound                           │     │
│  └───────────────────────────────────────────────────┘     │
│                                                            │
└────────────────────────────────────────────────────────────┘

Managed Identity + RBAC (conditional)
(for ACR image pulls when using ACR)
              │
              ▼
┌──────────────────────────┐
│ Azure Container Registry │
│ (Optional - Production)  │
│ - Navigator images       │
│ - AcrPull role assigned  │
└──────────────────────────┘
```

---

## 1. Resource Group

### Specifications

| Attribute    | Baseline (Dev)                                           | Enhanced (Production)                                           |
| ------------ | -------------------------------------------------------- | --------------------------------------------------------------- |
| **Name**     | `navigator-dev-rg`                                       | `navigator-prod-rg`                                             |
| **Location** | Canada Central                                           | Canada Central                                                  |
| **Tags**     | Environment=dev, Project=navigator, CostCenter=navigator | Environment=production, Project=navigator, CostCenter=navigator |

### Terraform Resource

```hcl
resource "azurerm_resource_group" "main" {
  name     = "navigator-${var.environment}-rg"
  location = var.location

  tags = {
    Environment = var.environment
    Project     = "navigator"
    CostCenter  = "navigator"
    ManagedBy   = "terraform"
  }
}
```

---

## 2. Virtual Network (VNet)

### Specifications

| Attribute         | Value                                                        |
| ----------------- | ------------------------------------------------------------ |
| **Address Space** | `10.240.0.0/16`                                              |
| **Location**      | Canada Central                                               |
| **DNS Servers**   | Azure-provided DNS (168.63.129.16)                           |
| **Subnets**       | 3 (Container Apps, PostgreSQL, Application Gateway reserved) |

### Subnet Design

| Subnet Name           | Address Prefix  | Delegation                                  | Purpose                                 |
| --------------------- | --------------- | ------------------------------------------- | --------------------------------------- |
| `snet-container-apps` | `10.240.1.0/24` | `Microsoft.App/environments`                | Container Apps Environment              |
| `snet-postgres`       | `10.240.2.0/24` | `Microsoft.DBforPostgreSQL/flexibleServers` | PostgreSQL Flexible Server              |
| `snet-appgateway`     | `10.240.3.0/24` | None                                        | Reserved for future Application Gateway |

### Terraform Resources

```hcl
resource "azurerm_virtual_network" "main" {
  name                = "vnet-navigator-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.240.0.0/16"]

  tags = azurerm_resource_group.main.tags
}

resource "azurerm_subnet" "container_apps" {
  name                 = "snet-container-apps"
  virtual_network_name = azurerm_virtual_network.main.name
  resource_group_name  = azurerm_resource_group.main.name
  address_prefixes     = ["10.240.1.0/24"]

  delegation {
    name = "container-apps-delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "postgres" {
  name                 = "snet-postgres"
  virtual_network_name = azurerm_virtual_network.main.name
  resource_group_name  = azurerm_resource_group.main.name
  address_prefixes     = ["10.240.2.0/24"]
  service_endpoints    = ["Microsoft.Storage"]

  delegation {
    name = "postgres-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}
```

---

## 3. Network Security Groups (NSGs)

### Container Apps NSG

**Purpose**: Control inbound and outbound traffic for Container Apps subnet

| Rule Name                    | Direction | Priority | Source           | Source Port | Destination                                                           | Dest Port | Protocol | Action                                             | Justification             |
| ---------------------------- | --------- | -------- | ---------------- | ----------- | --------------------------------------------------------------------- | --------- | -------- | -------------------------------------------------- | ------------------------- |
| `AllowHttpsInbound`          | Inbound   | 100      | `*` (internet)   | `*`         | `VirtualNetwork`                                                      | 443       | TCP      | Allow                                              | Public web application    |
| `AllowAzureServicesOutbound` | Outbound  | 100      | `VirtualNetwork` | `*`         | Service tags: CognitiveServices, AzureMonitor, AzureContainerRegistry | 443       | TCP      | Allow                                              | Azure service integration |
| `AllowPostgresOutbound`      | Outbound  | 110      | `10.240.1.0/24`  | `*`         | `10.240.2.0/24`                                                       | 5432      | TCP      | Allow                                              | Database connectivity     |
| `AllowInternetOutbound`      | Outbound  | 120      | `VirtualNetwork` | `*`         | `Internet`                                                            | 443       | TCP      | Allow (conditional via `enable_outbound_internet`) | OpenAI API integration    |

**Trivy Suppressions**:

- AVD-AZU-0047: Unrestricted inbound HTTPS (public web app requirement - documented in terraform/azure/security.tf)
- AVD-AZU-0051: Unrestricted outbound (service tags for Azure services + conditional internet access - documented in terraform/azure/security.tf)

### PostgreSQL NSG

| Rule Name              | Direction | Priority | Source          | Source Port | Destination     | Dest Port | Protocol | Action |
| ---------------------- | --------- | -------- | --------------- | ----------- | --------------- | --------- | -------- | ------ |
| `AllowPostgresInbound` | Inbound   | 100      | `10.240.1.0/24` | `*`         | `10.240.2.0/24` | 5432      | TCP      | Allow  |
| `DenyAllOutbound`      | Outbound  | 100      | `*`             | `*`         | `*`             | `*`       | `*`      | Deny   |

---

## 4. Azure Container Apps

### Container Apps Environment

| Attribute                   | Baseline (Dev)                        | Enhanced (Production)                 |
| --------------------------- | ------------------------------------- | ------------------------------------- |
| **Workload Profile**        | Consumption                           | Consumption (or Dedicated if needed)  |
| **VNet Subnet**             | `snet-container-apps` (10.240.1.0/24) | `snet-container-apps` (10.240.1.0/24) |
| **Log Analytics Workspace** | Yes (shared with PostgreSQL)          | Yes (dedicated, retention 30 days)    |
| **Zone Redundancy**         | Disabled                              | Enabled                               |

### Navigator Container App

| Attribute            | Baseline (Dev)                            | Enhanced (Production)                                                |
| -------------------- | ----------------------------------------- | -------------------------------------------------------------------- |
| **Container Image**  | `public.ecr.aws/cds-snc/valentine:latest` | Azure Container Registry (ACR): `navacr.azurecr.io/navigator:v1.2.3` |
| **CPU**              | 0.25 vCPU                                 | 0.5 vCPU                                                             |
| **Memory**           | 0.5 GB                                    | 1.0 GB                                                               |
| **Min Replicas**     | 0 (scale to zero)                         | 1                                                                    |
| **Max Replicas**     | 2                                         | 10                                                                   |
| **Scaling Trigger**  | HTTP concurrency (10 requests)            | CPU-based (70% threshold)                                            |
| **Target Port**      | 4000                                      | 4000                                                                 |
| **Ingress**          | External (HTTPS)                          | External (HTTPS)                                                     |
| **Session Affinity** | Enabled (sticky sessions)                 | Enabled (sticky sessions)                                            |
| **Managed Identity** | System-assigned                           | System-assigned                                                      |
| **Health Probe**     | HTTP liveness on "/"                      | HTTP liveness + readiness on "/"                                     |

**Session Affinity Implementation Note**:

- Session affinity (sticky sessions) is required for Phoenix LiveView WebSocket persistence
- Configured using **AzAPI provider** via `azapi_resource_action` (not yet supported in `azurerm_container_app`)
- Sets `properties.configuration.ingress.stickySessions.affinity = "sticky"` via Azure ARM REST API
- See [research.md](./research.md#azapi-provider-for-missing-azurerm-features) for detailed implementation approach

### Environment Variables

| Variable Name          | Source                              | Value/Secret Reference                         |
| ---------------------- | ----------------------------------- | ---------------------------------------------- |
| `DATABASE_URL`         | Container Apps secret               | `database-connection-string`                   |
| `SECRET_KEY_BASE`      | Container Apps secret               | `phoenix-secret-key-base`                      |
| `PHX_HOST`             | Ingress FQDN                        | Container Apps default domain or custom domain |
| `PORT`                 | Static                              | `4000`                                         |
| `OPENAI_API_KEY`       | Container Apps secret (conditional) | `openai-api-key`                               |
| `GOOGLE_CLIENT_ID`     | Container Apps secret (prod)        | `google-oauth-client-id`                       |
| `GOOGLE_CLIENT_SECRET` | Container Apps secret (prod)        | `google-oauth-client-secret`                   |

**Secret Management**:

- Auto-generated secrets (PostgreSQL passwords, SECRET_KEY_BASE): Created by Terraform `random_password` resource, stored in Terraform state, injected into Container Apps secrets
- Injected secrets (OAuth credentials, API keys): Passed as Terraform input variables, stored as Container Apps secrets
- Container Apps secrets: Platform-encrypted by Azure, accessible only to running app instances

### Health Probes

**Liveness Probe** (detect unhealthy containers):

- **Type**: HTTP
- **Path**: `/`
- **Port**: 4000
- **Initial Delay**: 10 seconds
- **Period**: 30 seconds
- **Timeout**: 5 seconds
- **Failure Threshold**: 3 (restart after 3 failed checks)

**Startup Probe** (optional, for slow startup):

- **Type**: HTTP
- **Path**: `/`
- **Port**: 4000
- **Initial Delay**: 0 seconds
- **Period**: 10 seconds
- **Failure Threshold**: 30 (allow 5 minutes for startup)

---

## 6. Azure Database for PostgreSQL Flexible Server

### Server Configuration

| Attribute                | Baseline (Dev)                    | Enhanced (Production)                         |
| ------------------------ | --------------------------------- | --------------------------------------------- |
| **Version**              | PostgreSQL 16                     | PostgreSQL 16                                 |
| **SKU**                  | `B_Standard_B1ms` (1 vCore, 2 GB) | `GP_Standard_D2s_v3` (2 vCores, 8 GB)         |
| **Storage**              | 32 GB                             | 128 GB (auto-grow enabled)                    |
| **Availability Zone**    | Zone 1                            | Zone 1 (primary)                              |
| **High Availability**    | Disabled                          | Zone-redundant (standby in Zone 2)            |
| **Backup Retention**     | 7 days                            | 14 days                                       |
| **Geo-Redundant Backup** | Disabled                          | Optional (enabled at creation, cannot change) |
| **Network**              | Private (delegated subnet)        | Private (delegated subnet)                    |
| **Public Access**        | Disabled                          | Disabled                                      |
| **SSL/TLS Enforcement**  | Optional (disabled by default)    | Optional (configurable via variable)          |

### Authentication

| Method                      | Baseline (Dev)                                                            | Enhanced (Production)                                                     |
| --------------------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| **Admin User**              | `navadmin`                                                                | `navadmin`                                                                |
| **Admin Password**          | Auto-generated via Terraform `random_password`, stored in Terraform state | Auto-generated via Terraform `random_password`, stored in Terraform state |
| **Azure AD Authentication** | Optional (future)                                                         | Recommended (future)                                                      |

### Database Configuration

| Attribute         | Value        |
| ----------------- | ------------ |
| **Database Name** | `navigator`  |
| **Collation**     | `en_US.utf8` |
| **Charset**       | `UTF8`       |

### Server Parameters

| Parameter                    | Baseline (Dev)  | Enhanced (Production) | Purpose                            |
| ---------------------------- | --------------- | --------------------- | ---------------------------------- |
| `pgbouncer.enabled`          | `off`           | `on`                  | Connection pooling                 |
| `require_secure_transport`   | `off`           | `off` (configurable)  | Optional SSL/TLS enforcement       |
| `ssl_min_protocol_version`   | `TLSv1.2`       | `TLSv1.2`             | Minimum TLS version (when enabled) |
| `log_statement`              | `none`          | `ddl`                 | Log DDL statements for audit       |
| `log_min_duration_statement` | `-1` (disabled) | `1000` (1 second)     | Log slow queries                   |

### Private DNS Zone

| Attribute     | Value                                     |
| ------------- | ----------------------------------------- |
| **Zone Name** | `privatelink.postgres.database.azure.com` |
| **VNet Link** | Linked to `vnet-navigator-${environment}` |

---

## 7. Azure DNS and Custom Domain

### DNS Zone

**Implementation**: DNS zones created by Terraform as part of infrastructure deployment

| Attribute     | Baseline (Dev)                                                           | Enhanced (Production)                           |
| ------------- | ------------------------------------------------------------------------ | ----------------------------------------------- |
| **Zone Name** | `navigator-dev.demo.focisolutions.com`                                   | `navigator.demo.focisolutions.com`              |
| **A Record**  | Points to Container Apps default domain or Application Gateway public IP | Points to Container Apps or Application Gateway |

### TLS Certificates

| Method               | Baseline (Dev)                            | Enhanced (Production)                                                 |
| -------------------- | ----------------------------------------- | --------------------------------------------------------------------- |
| **Certificate Type** | Container Apps Managed Certificate (free) | Container Apps Managed Certificate or App Gateway Managed Certificate |
| **Validation**       | DNS validation (automated)                | DNS validation (automated)                                            |
| **Renewal**          | Automatic                                 | Automatic                                                             |

---

## 8. Monitoring and Logging

### Log Analytics Workspace

| Attribute     | Baseline (Dev)                 | Enhanced (Production)          |
| ------------- | ------------------------------ | ------------------------------ |
| **Name**      | `law-navigator-${environment}` | `law-navigator-${environment}` |
| **SKU**       | PerGB2018                      | PerGB2018                      |
| **Retention** | 30 days                        | 90 days                        |
| **Daily Cap** | 1 GB                           | 10 GB                          |

### Application Insights (Conditional)

| Attribute            | Baseline (Dev) | Enhanced (Production)   |
| -------------------- | -------------- | ----------------------- |
| **Enabled**          | No             | Yes                     |
| **Application Type** | N/A            | Web                     |
| **Sampling**         | N/A            | 100% (no sampling)      |
| **Workspace Link**   | N/A            | Linked to Log Analytics |

### Diagnostic Settings

**Container Apps Environment**:

- Destination: Log Analytics Workspace
- Logs: All categories (AppEnvSpringAppConsoleLogs, ContainerAppConsoleLogs, ContainerAppSystemLogs)
- Metrics: AllMetrics

**PostgreSQL Flexible Server**:

- Destination: Log Analytics Workspace
- Logs: PostgreSQLLogs, PostgreSQLFlexDatabaseXacts, PostgreSQLFlexQueryStoreRuntime, PostgreSQLFlexSessions
- Metrics: AllMetrics

---

## 9. Identity and Access Management (IAM)

### Managed Identities

| Identity       | Type            | Purpose                    |
| -------------- | --------------- | -------------------------- |
| Container Apps | System-assigned | Pull ACR images (optional) |

### RBAC Role Assignments

| Principal                       | Role        | Scope                               | Purpose                         |
| ------------------------------- | ----------- | ----------------------------------- | ------------------------------- |
| Container Apps managed identity | AcrPull     | Azure Container Registry (optional) | Pull container images           |
| GitHub OIDC identity            | Contributor | Resource Group                      | Deploy infrastructure via CI/CD |
| Developers                      | Reader      | Resource Group                      | View resources                  |
| Ops team                        | Contributor | Resource Group                      | Manage resources                |

---

## 10. Optional Components

### Azure Container Registry (ACR)

**Enabled**: Production only (use public ECR for development)

| Attribute                  | Value                                    |
| -------------------------- | ---------------------------------------- |
| **SKU**                    | Standard                                 |
| **Public Access**          | Disabled                                 |
| **Private Endpoint**       | Enabled                                  |
| **Geo-replication**        | Disabled                                 |
| **Retention Policy**       | 30 days for untagged manifests           |
| **Vulnerability Scanning** | Microsoft Defender for Cloud integration |

### Azure Storage Account (Optional)

**Enabled**: If needed for user uploads

| Attribute            | Baseline (Dev)                                             | Enhanced (Production)                                      |
| -------------------- | ---------------------------------------------------------- | ---------------------------------------------------------- |
| **SKU**              | Standard_LRS                                               | Standard_ZRS                                               |
| **Access Tier**      | Hot                                                        | Hot                                                        |
| **Blob Container**   | `user-uploads`                                             | `user-uploads`                                             |
| **Private Endpoint** | No                                                         | Yes (conditional)                                          |
| **Lifecycle Policy** | Archive to Cool after 90 days, Archive tier after 180 days | Archive to Cool after 90 days, Archive tier after 180 days |

### Application Gateway + WAF (Optional)

**Enabled**: Production only if required by compliance

| Attribute        | Value                             |
| ---------------- | --------------------------------- |
| **SKU**          | WAF_v2                            |
| **Tier**         | WAF_v2                            |
| **Subnet**       | `snet-appgateway` (10.240.3.0/24) |
| **WAF Policy**   | OWASP 3.2 rule set                |
| **Backend Pool** | Container Apps default domain     |

---

## 11. Cost Estimation (Detailed)

### Development Environment

| Component      | SKU/Configuration                              | Quantity        | Monthly Cost (CAD) |
| -------------- | ---------------------------------------------- | --------------- | ------------------ |
| Container Apps | 0.25 vCPU, 0.5 GB, scale to zero               | ~50 hours/month | $5-10              |
| PostgreSQL     | B_Standard_B1ms (1 vCore, 2 GB), 32 GB storage | 1               | $12-15             |
| VNet           | Standard                                       | 1               | $2                 |
| Log Analytics  | 1 GB/day ingestion, 30-day retention           | 1               | $3-5               |
| **TOTAL**      |                                                |                 | **$22-32/month**   |

**With auto-shutdown** (evenings, weekends): **$12-20/month** (45-55% savings)

### Production Environment

| Component              | SKU/Configuration                                              | Quantity        | Monthly Cost (CAD)       |
| ---------------------- | -------------------------------------------------------------- | --------------- | ------------------------ |
| Container Apps         | 0.5 vCPU, 1.0 GB, min 1 replica                                | 730 hours/month | $50-80                   |
| PostgreSQL             | GP_Standard_D2s_v3 (2 vCores, 8 GB), 128 GB, Zone-redundant HA | 1               | $240-280                 |
| VNet                   | Standard                                                       | 1               | $2                       |
| NAT Gateway (optional) | Standard                                                       | 1               | $35-45                   |
| Log Analytics          | 5 GB/day ingestion, 90-day retention                           | 1               | $15-25                   |
| Application Insights   | 5 GB/day ingestion                                             | 1               | $15-25                   |
| ACR                    | Standard                                                       | 1               | $6.50                    |
| **TOTAL**              |                                                                |                 | **$363.50-463.50/month** |

**With Azure Reservations** (1-year PostgreSQL commitment): **$285-395/month** (22-25% savings)

---

## 12. Security Compliance Summary

### Government of Canada Requirements

| Requirement               | Implementation                                                                                                   | Compliance Status         |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------- | ------------------------- |
| **Data Residency**        | Canada Central region                                                                                            | ✅ Compliant              |
| **Encryption at Rest**    | AES-256 (Microsoft-managed keys)                                                                                 | ✅ Compliant              |
| **Encryption in Transit** | TLS 1.2+ enforced for internet-facing traffic; Optional for DB connections (network isolation provides security) | ✅ Compliant              |
| **Network Isolation**     | Private VNet, no public PostgreSQL access                                                                        | ✅ Compliant              |
| **Secrets Management**    | Container Apps secrets (platform-encrypted)                                                                      | ✅ Compliant              |
| **Event Logging**         | Diagnostic settings to Log Analytics                                                                             | ✅ Compliant              |
| **Incident Management**   | Azure Monitor alerts, GC CSEMP aligned                                                                           | ✅ Compliant              |
| **Patch Management**      | Managed services auto-patching                                                                                   | ✅ Compliant              |
| **ITSG-22/ITSG-38**       | Risk management framework                                                                                        | ⚠️ Manual review required |

---

**Document Version**: 1.2.0  
**Last Updated**: January 21, 2026  
**Related Documents**: plan.md, research.md, quickstart.md

**Changelog**:

- v1.2.0 (2026-01-21): Removed Azure Key Vault completely - using Container Apps secrets exclusively for secret management
- v1.1.0 (2026-01-20): Updated Key Vault to optional configuration, added secrets management strategy details, updated NSG rules documentation, clarified DNS zone creation
- v1.0.0 (2026-01-15): Initial architecture specification
