# Detailed Infrastructure Architecture

**Branch**: `002-internal-ca-appgw` | **Date**: 2026-01-26 | **Plan**: [plan.md](./plan.md) | **Research**: [research.md](./research.md)

This document provides detailed infrastructure architecture specifications for implementing Azure Application Gateway as a reverse proxy for internal-only Container Apps. All design decisions align with Azure Well-Architected Framework principles documented in research.md.

---

## Architecture Overview

### High-Level Design

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                 │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             │ HTTPS (443)
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  Azure Application Gateway (Standard_v2)                        │
│  - Public IP (zone-redundant/prod, zone-local/dev)              │
│  - TLS Termination (Let's Encrypt via ACME azuredns provider)   │
│  - WAF Policy (optional, OWASP CRS 3.2)                         │
│  - Health Probes → Container Apps (HTTP)                        │
│  Subnet: 10.240.3.0/24                                          │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             │ HTTP (80) → Private DNS → Internal FQDN
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  Azure Container Apps Environment (Internal Load Balancer)      │
│  - Internal Load Balancer Enabled (VNet-integrated)             │
│  - Public Network Access: Disabled                              │
│  - Static IP for Private DNS resolution                         │
│  - Zone-redundant (production)                                  │
│  Subnet: 10.240.0.0/23 (Microsoft requirement for delegation)   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Navigator Container App                                │   │
│  │  - Phoenix/Elixir application (port 4000)               │   │
│  │  - WebSocket support (Phoenix LiveView)                 │   │
│  │  - External Enabled: true (VNET access for App Gateway) │   │
│  │  - Min: 0/1 replicas (dev/prod), Max: 2/5 replicas      │   │
│  │  - Session affinity (cookie-based)                      │   │
│  └─────────────────────────────────────────────────────────┘   │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             │ PostgreSQL (5432)
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  Azure Database for PostgreSQL Flexible Server                  │
│  - Private delegated subnet (10.240.2.0/24)                     │
│  - Zone-redundant HA (production)                               │
│  - Built-in PgBouncer (connection pooling)                      │
└─────────────────────────────────────────────────────────────────┘
```

### Traffic Flow

1. **Client Request**: User accesses `https://navigator-{env}.demo.focisolutions.com` → DNS resolves to Application Gateway public IP
2. **TLS Termination**: Application Gateway terminates TLS, validates certificate (Let's Encrypt)
3. **WAF Inspection** (if enabled): Request inspected against OWASP CRS rules
4. **Private DNS Resolution**: Application Gateway resolves Container Apps internal FQDN via Private DNS zone
5. **Backend Routing**: Request forwarded to Container Apps internal endpoint (HTTP, port 80)
6. **Container Apps Ingress**: Internal load balancer routes to Navigator container app replica
7. **Session Affinity**: Cookie-based affinity ensures WebSocket connections stay on same replica
8. **Application Processing**: Phoenix/Elixir app processes request, connects to PostgreSQL via private subnet

---

## Compute Resources

### Azure Application Gateway

**Purpose**: Reverse proxy providing defense-in-depth security, TLS termination, and centralized traffic management

#### SKU Configuration

**Both Environments**:
- SKU Name: `Standard_v2`
- SKU Tier: `Standard_v2`
- Rationale: Consistent SKU across environments simplifies management; WAF attachable via policy

**Dev Environment**:
```hcl
sku {
  name = "Standard_v2"
  tier = "Standard_v2"
}

# Fixed capacity (no autoscaling)
capacity = 1
```

**Production Environment**:
```hcl
sku {
  name = "Standard_v2"
  tier = "Standard_v2"
}

# Autoscaling configuration
autoscale_configuration {
  min_capacity = 2
  max_capacity = 5
}

# Zone redundancy
zones = ["1", "2", "3"]
```

**Rationale from Well-Architected Framework**:
- Standard_v2 provides autoscaling and zone redundancy capabilities
- WAF policy can be attached to Standard_v2 SKU (WAF_v2 SKU not required)
- Consistent SKU reduces configuration drift between environments
- Cost optimization: Dev uses fixed 1 instance (~$150/month), Prod autoscales 2-5 instances (~$250/month)

#### Frontend IP Configuration

**Public IP Address**:
```hcl
resource "azurerm_public_ip" "appgw" {
  name                = "${local.name_prefix}-appgw-pip"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  sku                 = "Standard"  # Required for Application Gateway v2
  allocation_method   = "Static"    # Required for zone redundancy
  zones               = var.enable_zone_redundancy ? ["1", "2", "3"] : null

  domain_name_label   = var.domain_name != null ? null : "${local.name_prefix}-appgw"
}
```

**Frontend IP Configuration**:
```hcl
frontend_ip_configuration {
  name                 = "frontend-ip-public"
  public_ip_address_id = azurerm_public_ip.appgw.id
}
```

#### Listeners

**HTTPS Listener** (Primary):
```hcl
frontend_port {
  name = "https-port"
  port = 443
}

http_listener {
  name                           = "https-listener"
  frontend_ip_configuration_name = "frontend-ip-public"
  frontend_port_name             = "https-port"
  protocol                       = "Https"
  ssl_certificate_name           = var.domain_name != null ? "navigator-ssl-cert" : null

  # TLS policy
  ssl_policy {
    policy_type          = "Custom"
    min_protocol_version = "TLSv1_2"
    cipher_suites = [
      "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
      "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
    ]
  }
}
```

**HTTP Listener** (Optional redirect to HTTPS):
```hcl
frontend_port {
  name = "http-port"
  port = 80
}

http_listener {
  name                           = "http-listener"
  frontend_ip_configuration_name = "frontend-ip-public"
  frontend_port_name             = "http-port"
  protocol                       = "Http"
}

# Redirect configuration
redirect_configuration {
  name                 = "http-to-https-redirect"
  redirect_type        = "Permanent"  # 301 redirect
  target_listener_name = "https-listener"
  include_path         = true
  include_query_string = true
}

request_routing_rule {
  name                       = "http-redirect-rule"
  rule_type                  = "Basic"
  http_listener_name         = "http-listener"
  redirect_configuration_name = "http-to-https-redirect"
  priority                   = 200
}
```

**Rationale**: HTTP→HTTPS redirect enforces secure connections; priority 200 ensures redirect rule processes before main routing rule (priority 100)

#### Backend Configuration

**Backend Pool**:
```hcl
backend_address_pool {
  name  = "ca-backend-pool"
  fqdns = [azurerm_container_app.navigator.ingress[0].fqdn]
}
```

**Note**: Container Apps internal FQDN format: `<container-app-name>.<container-app-environment-default-domain>` (e.g., `nav-dev-ca-001.internalenv.canadacentral.azurecontainerapps.io`)

**Backend HTTP Settings**:
```hcl
backend_http_settings {
  name                                = "ca-backend-http-settings"
  cookie_based_affinity               = "Enabled"  # Preserves Phoenix LiveView sessions
  affinity_cookie_name                = "ApplicationGatewayAffinity"
  port                                = 80
  protocol                            = "Http"
  request_timeout                     = 180  # Seconds (supports long-lived WebSocket connections)
  pick_host_name_from_backend_address = true  # Use Container Apps internal FQDN as Host header

  # Connection draining
  connection_draining {
    enabled           = true
    drain_timeout_sec = 30
  }

  # Probe configuration
  probe_name = "ca-health-probe"
}
```

**Rationale**:
- Cookie-based affinity: Ensures WebSocket connections (Phoenix Channels) stay on same Container Apps replica
- Request timeout 180s: Phoenix LiveView maintains long-lived connections; default 30s insufficient
- Pick host name from backend: Application Gateway sends Container Apps internal FQDN as Host header for proper routing
- Connection draining: Gracefully shutdown during scale-in or updates (Container Apps respects 30s graceful shutdown)
- HTTP protocol: Gateway to container communication uses HTTP as containers are within trusted VNET

**Health Probe**:
```hcl
probe {
  name                                      = "ca-health-probe"
  protocol                                  = "Http"
  pick_host_name_from_backend_http_settings = true
  path                                      = "/"
  interval                                  = 30
  timeout                                   = 30
  unhealthy_threshold                       = 3

  match {
    status_code = ["200-399"]  # Accept any 2xx or 3xx response
  }
}
```

**Rationale from Well-Architected Framework**:
- 30-second interval balances responsiveness with backend load
- 3 failure threshold (90 seconds total) prevents false positives from transient failures
- Path `/` matches Container Apps readiness probe (Phoenix/Elixir app health endpoint)

#### Routing Rules

**Main Routing Rule**:
```hcl
request_routing_rule {
  name                       = "https-routing-rule"
  rule_type                  = "Basic"  # Simple 1:1 listener-to-backend mapping
  http_listener_name         = "https-listener"
  backend_address_pool_name  = "ca-backend-pool"
  backend_http_settings_name = "ca-backend-http-settings"
  priority                   = 100
}
```

#### SSL/TLS Certificate Management

**Certificate Upload to Application Gateway** (when custom domain provided):
```hcl
dynamic "ssl_certificate" {
  for_each = var.domain_name != null ? [1] : []

  content {
    name     = "navigator-ssl-cert"
    data     = acme_certificate.navigator[0].certificate_p12
    password = acme_certificate.navigator[0].certificate_p12_password
  }
}
```

**ACME Certificate Resource** (in acme.tf):
```hcl
resource "acme_certificate" "navigator" {
  count = var.domain_name != null ? 1 : 0

  account_key_pem = acme_registration.account.account_key_pem
  common_name     = "navigator-${var.environment}.${var.domain_name}"  # e.g., navigator-dev.demo.focisolutions.com

  dns_challenge {
    provider = "azuredns"  # Changed from "azure" (deprecated) to "azuredns"
    config = {
      AZURE_RESOURCE_GROUP = var.resource_group_name
      AZURE_ZONE_NAME      = var.domain_name
    }
  }

  min_days_remaining = 30  # Renew 30 days before expiry
  use_renewal_info   = true  # Use ARI for optimized renewal timing

  revoke_certificate_on_destroy = true
}
```

**Container App Environment Certificate** (for Container Apps custom domain binding):
```hcl
# Upload certificate to Container Apps environment
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
  name                          = "navigator-${var.environment}.${var.domain_name}"
  container_app_id              = azurerm_container_app.navigator.id
  container_app_environment_certificate_id = azurerm_container_app_environment_certificate.navigator[0].id
  certificate_binding_type      = "SniEnabled"
}
```

**Rationale**: 
- ACME provider automates Let's Encrypt certificate provisioning and renewal (DNS-01 challenge using `azuredns` provider)
- Certificate issued for full subdomain (e.g., `navigator-dev.demo.focisolutions.com`)
- Certificate uploaded to both Application Gateway (for HTTPS listener) and Container App Environment (for custom domain binding)
- `min_days_remaining=30` ensures renewal before 90-day certificate expires

#### Web Application Firewall (Optional)

**WAF Policy** (separate resource):
```hcl
resource "azurerm_web_application_firewall_policy" "main" {
  count = var.enable_waf ? 1 : 0

  name                = "${local.name_prefix}-waf-policy"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  policy_settings {
    enabled                     = true
    mode                        = var.waf_mode  # "Detection" initially, "Prevention" after tuning
    request_body_check          = true
    file_upload_limit_in_mb     = 100
    max_request_body_size_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }

    managed_rule_set {
      type    = "Microsoft_BotManagerRuleSet"
      version = "1.0"
    }
  }
}
```

**Attach WAF to Application Gateway**:
```hcl
resource "azurerm_application_gateway" "main" {
  # ... other configuration ...

  firewall_policy_id = var.enable_waf ? azurerm_web_application_firewall_policy.main[0].id : null
}
```

**Rationale**:
- Feature flag `enable_waf` allows incremental adoption (start without, enable when ready)
- Detection mode initially for tuning; switch to Prevention after validating no false positives
- OWASP CRS 3.2 provides OWASP Top 10 protection (SQL injection, XSS, etc.)
- Bot Manager ruleset blocks malicious bots while allowing legitimate crawlers

#### Additional Configuration

**HTTP/2 Support** (Phoenix LiveView optimization):
```hcl
enable_http2 = true
```

**WebSocket Support**:
- HTTP/2 enabled allows WebSocket protocol upgrade
- Session affinity ensures WebSocket connections stay on same backend
- Request timeout 180s prevents premature connection closure
- No additional configuration required

---

### Azure Container Apps

**No changes to existing Container Apps infrastructure** - only ingress configuration modified

#### Ingress Configuration Change

**BEFORE** (current state):
```hcl
ingress {
  external_enabled           = true  # Public internet access
  allow_insecure_connections = false
  target_port                = 4000

  ip_security_restriction {
    action           = "Allow"
    ip_address_range = "0.0.0.0/0"  # Allow all
  }
}
```

**AFTER** (new state):
```hcl
# Container App Environment with internal load balancer
resource "azurerm_container_app_environment" "this" {
  name                           = local.cae_name
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  infrastructure_subnet_id       = azurerm_subnet.ca.id
  internal_load_balancer_enabled = true
  
  # Required for internal load balancer
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

# Container App with external enabled for VNET access
ingress {
  external_enabled           = true   # Set to true to allow connections from same VNET (required for App Gateway communication)
  allow_insecure_connections = false
  target_port                = 4000
  # transport defaults to Auto (removed explicit configuration)
  # No IP restrictions - VNET access only due to internal load balancer
}
```

**Critical Impact**:
- Container Apps environment uses internal load balancer (not internet accessible)
- `public_network_access` implicitly set to "Disabled" when internal load balancer is enabled
- `external_enabled = true` allows connections from same VNET (required for Application Gateway communication)
- All external traffic must route through Application Gateway
- Internal FQDN format: `<app-name>.<env-default-domain>` (no `.internal` prefix)
- Existing health probes, session affinity, and scaling rules unchanged
- Transport defaults to Auto (supports both HTTP/1.1 and HTTP/2)

#### Session Affinity Configuration

**Using azapi provider** (for advanced configuration):
```hcl
resource "azapi_update_resource" "ca_session_affinity" {
  type        = "Microsoft.App/containerApps@2024-03-01"
  resource_id = azurerm_container_app.navigator.id

  body = jsonencode({
    properties = {
      configuration = {
        ingress = {
          stickySessions = {
            affinity = "sticky"  # Cookie-based session affinity
          }
        }
      }
    }
  })
}
```

**Rationale**: Session affinity required for Phoenix LiveView WebSocket connections; ensures user stays on same replica for duration of session

---

## Data Storage

**No changes to existing data storage** - Application Gateway does not store data (stateless reverse proxy)

### Existing PostgreSQL Configuration

- **Service**: Azure Database for PostgreSQL Flexible Server
- **Connection**: Private delegated subnet (10.240.2.0/24)
- **High Availability**: Zone-redundant (production), no HA (dev)
- **Backup Retention**: 7 days (dev), 30 days (production)
- **Storage**: 32GB (dev), 64GB (production)
- **Connection Pooling**: Built-in PgBouncer enabled

**Reference**: See existing `terraform/azure/postgresql.tf`

---

## Networking

### Virtual Network Structure

**VNet Address Space**: `10.240.0.0/16` (existing)

#### Subnets

**1. Container Apps Subnet** (MODIFIED):
```hcl
resource "azurerm_subnet" "ca" {
  name                 = "${local.name_prefix}-ca-snet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.240.0.0/23"]  # CHANGED from 10.240.1.0/24 to 10.240.0.0/23 (Microsoft requirement for VNET delegation)

  delegation {
    name = "Microsoft.App/environments"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }

  service_endpoints = ["Microsoft.Storage"]
}
```

**Rationale for Size Change**:
- Changed to 10.240.0.0/23 (510 hosts) as required by Microsoft for Container Apps VNET delegation
- Enables VNet integration features for Container Apps
- Provides room for future scaling and additional container apps
- Microsoft requirement: minimum /23 subnet for Container Apps environment with internal load balancer

**2. PostgreSQL Subnet** (NO CHANGES):
```hcl
resource "azurerm_subnet" "db" {
  name                 = "${local.name_prefix}-db-snet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.240.2.0/24"]

  delegation {
    name = "Microsoft.DBforPostgreSQL/flexibleServers"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }

  service_endpoints = ["Microsoft.Storage"]
}
```

**3. Application Gateway Subnet** (NEW - existing subnet, now used):
```hcl
resource "azurerm_subnet" "appgw" {
  name                 = "${local.name_prefix}-appgw-snet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.240.3.0/24"]

  # No delegation required for Application Gateway
  # No NSG allowed (Azure platform limitation)

  service_endpoints = ["Microsoft.Storage"]
}
```

**Important**: Application Gateway subnet cannot have NSG attached (Azure platform requirement); security managed through backend NSG rules

### Network Security Groups

**Container Apps NSG** (MODIFIED):
```hcl
resource "azurerm_network_security_group" "ca" {
  name                = "${local.name_prefix}-ca-nsg"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
}

# NEW RULE: Allow HTTPS from Application Gateway
resource "azurerm_network_security_rule" "ca_allow_appgw" {
  name                        = "AllowAppGatewayHttp"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "10.240.3.0/24"  # Application Gateway subnet
  destination_address_prefix  = "10.240.0.0/23"  # Container Apps subnet
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.ca.name
}

# EXISTING RULE: Deny all other inbound traffic
resource "azurerm_network_security_rule" "ca_deny_all_inbound" {
  name                        = "DenyAllInbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.ca.name
}
```

**PostgreSQL NSG** (NO CHANGES):
- Existing rules maintained (allow Container Apps → PostgreSQL port 5432)

**Application Gateway Subnet**:
- No NSG allowed (Azure platform requirement)
- Security managed through Application Gateway configuration and backend NSG rules

### Private DNS Zone

**Purpose**: Enable Application Gateway to resolve Container Apps internal FQDN

**Private DNS Zone**:
```hcl
resource "azurerm_private_dns_zone" "ca" {
  name                = azurerm_container_app_environment.this.default_domain
  resource_group_name = azurerm_resource_group.this.name
}

# Example zone name: "internalenv001.canadacentral.azurecontainerapps.io"
```

**Virtual Network Link**:
```hcl
resource "azurerm_private_dns_zone_virtual_network_link" "ca" {
  name                  = "${local.name_prefix}-ca-dns-link"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.ca.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
}
```

**DNS A Records**:
```hcl
# Wildcard record for all Container Apps
resource "azurerm_private_dns_a_record" "ca_wildcard" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.ca.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  records             = [azurerm_container_app_environment.this.static_ip_address]
}

# Root record
resource "azurerm_private_dns_a_record" "ca_root" {
  name                = "@"
  zone_name           = azurerm_private_dns_zone.ca.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  records             = [azurerm_container_app_environment.this.static_ip_address]
}
```

**Rationale**: Private DNS zone enables Application Gateway to resolve Container Apps internal FQDN to Container Apps environment static IP; required for backend connectivity

### Public DNS Configuration

**Azure DNS Zone** (for custom domain):
```hcl
# Public DNS zone for custom domain (e.g., demo.focisolutions.com)
resource "azurerm_dns_zone" "main" {
  count               = var.domain_name != null ? 1 : 0
  name                = var.domain_name  # e.g., "demo.focisolutions.com"
  resource_group_name = azurerm_resource_group.this.name
}

# DNS A record for subdomain pointing to Application Gateway public IP
resource "azurerm_dns_a_record" "main" {
  count               = var.domain_name != null ? 1 : 0
  name                = "navigator-${var.environment}"  # Creates navigator-dev.demo.focisolutions.com or navigator-production.demo.focisolutions.com
  zone_name           = azurerm_dns_zone.main[0].name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  records             = [azurerm_public_ip.appgw.ip_address]
}
```

**Domain Pattern**:
- Dev: `navigator-dev.demo.focisolutions.com`
- Production: `navigator-production.demo.focisolutions.com`
- ACME certificate issued for full subdomain (e.g., `navigator-dev.demo.focisolutions.com`)

**Change from Existing**: DNS A record now points to Application Gateway public IP instead of Container Apps IP

**ACME DNS-01 Challenge**:
- ACME provider automatically creates DNS TXT records in Azure DNS zone for domain validation
- Provider name changed to `azuredns` (from deprecated `azure`)
- No manual intervention required
- TXT records cleaned up after validation completes

**Private DNS Zone for Custom Domain** (NEW):
```hcl
# Private DNS zone for var.domain_name (e.g., demo.focisolutions.com)
resource "azurerm_private_dns_zone" "domain" {
  count               = var.domain_name != null ? 1 : 0
  name                = var.domain_name
  resource_group_name = azurerm_resource_group.this.name
}

# A record for @ pointing to Application Gateway public IP
resource "azurerm_private_dns_a_record" "domain_root" {
  count               = var.domain_name != null ? 1 : 0
  name                = "@"
  zone_name           = azurerm_private_dns_zone.domain[0].name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  records             = [azurerm_public_ip.appgw.ip_address]
}

# Virtual Network Link for private DNS zone
resource "azurerm_private_dns_zone_virtual_network_link" "domain" {
  count                 = var.domain_name != null ? 1 : 0
  name                  = "${local.name_prefix}-domain-dns-link"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.domain[0].name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
}
```

**Rationale**: Private DNS zone for custom domain enables internal resolution within VNET; replaces Container Apps internal FQDN private DNS zone approach

---

## Security

### Defense-in-Depth Layers

**Layer 1: Public Internet → Application Gateway**:
- DDoS Protection: Azure platform DDoS Basic (no additional cost)
- WAF Protection: OWASP CRS 3.2 (when enabled)
- TLS Termination: TLS 1.2+ enforcement, strong cipher suites

**Layer 2: Application Gateway → Container Apps**:
- Private networking: Application Gateway in dedicated subnet
- NSG rules: Container Apps NSG only allows inbound from Application Gateway subnet (port 80)
- HTTP backend communication: Uses HTTP for gateway to container communication as containers are within trusted VNET
- TLS termination at Application Gateway provides encryption for external traffic

**Layer 3: Container Apps → PostgreSQL**:
- Private connectivity: PostgreSQL private delegated subnet
- No public endpoint: PostgreSQL public network access disabled
- Encrypted connections: TLS/SSL enforcement for database connections

### TLS/SSL Configuration

**Minimum TLS Version**: 1.2 (TLS 1.0/1.1 deprecated)

**Cipher Suites** (Application Gateway):
```hcl
ssl_policy {
  policy_type          = "Custom"
  min_protocol_version = "TLSv1_2"
  cipher_suites = [
    "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
    "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
  ]
}
```

**Rationale**: Forward secrecy (ECDHE), authenticated encryption (GCM), strong key sizes (128/256-bit AES)

### Secrets Management

**ACME Account Key**:
- Generated by `tls_private_key` resource
- Stored in Terraform state (encrypted by Azure Storage Account encryption)
- Never exposed in logs (sensitive = true)

**Certificate Private Key**:
- Managed by ACME provider (ephemeral resource)
- Never stored in Terraform state
- Uploaded to Application Gateway as P12 format with random password

**Certificate P12 Password**:
```hcl
resource "random_password" "cert_p12_password" {
  length  = 32
  special = true
}
```

**PostgreSQL Password** (existing):
- Generated by `random_password` resource
- Stored in Terraform state (encrypted)
- Never hardcoded in configuration

**Alternative: Azure Key Vault Integration** (future enhancement):
- Store certificates in Key Vault for centralized management
- Application Gateway uses managed identity to access Key Vault
- Automatic certificate rotation via Key Vault

### Identity and Access

**Application Gateway**:
- No managed identity required (stateless reverse proxy)
- Future: User-assigned managed identity for Key Vault integration

**Container Apps** (existing):
- System-assigned managed identity for accessing Azure resources
- No changes required

**PostgreSQL** (existing):
- Admin credentials managed via Terraform state encryption
- Future: Microsoft Entra authentication for passwordless connections

---

## Environment Configuration

### Dev Environment

**Application Gateway**:
- SKU: Standard_v2
- Capacity: Fixed 1 instance
- Availability: Single-zone
- WAF: Disabled (default)
- ACME Endpoint: Staging (`https://acme-staging-v02.api.letsencrypt.org/directory`)

**Container Apps** (existing):
- Subnet: 10.240.0.0/23
- Min Replicas: 0
- Max Replicas: 2
- Container: 0.5 vCPU, 1Gi memory
- Zone Redundancy: false

**PostgreSQL** (existing):
- Tier: Burstable
- SKU: B1ms
- Storage: 32GB
- Backup Retention: 7 days
- High Availability: Disabled

**Estimated Monthly Cost**: ~$350-500 (existing ~$200 + Application Gateway ~$150)

### Production Environment

**Application Gateway**:
- SKU: Standard_v2
- Capacity: Autoscale 2-5 instances
- Availability: Zone-redundant (zones 1, 2, 3)
- WAF: Optional (feature flag `enable_waf`)
- ACME Endpoint: Production (`https://acme-v02.api.letsencrypt.org/directory`)

**Container Apps** (existing):
- Subnet: 10.240.0.0/23
- Min Replicas: 1
- Max Replicas: 5
- Container: 1.0 vCPU, 2Gi memory
- Zone Redundancy: true

**PostgreSQL** (existing):
- Tier: General Purpose
- SKU: GP_Standard_D2s_v3
- Storage: 64GB
- Backup Retention: 30 days
- High Availability: Zone-redundant

**Estimated Monthly Cost**: ~$1,750-3,250 (existing ~$1,500 + Application Gateway ~$250-400 with WAF)

### Feature Flags

```hcl
# Dev defaults
enable_waf             = false  # Cost optimization
enable_zone_redundancy = false  # Simplified architecture
enable_http_redirect   = true   # Redirect HTTP→HTTPS
appgw_capacity_min     = 1      # Fixed capacity
appgw_capacity_max     = 1      # No auto-scaling

# Production defaults
enable_waf             = false  # Optional (adds ~$150/month)
enable_zone_redundancy = true   # High availability
enable_http_redirect   = true   # Enforce HTTPS
appgw_capacity_min     = 2      # Minimum 2 instances
appgw_capacity_max     = 5      # Auto-scale up to 5
```

---

## Monitoring and Observability

### Application Gateway Metrics

**Key Metrics** (send to Log Analytics):
- Backend Response Time: Average latency to Container Apps
- Failed Requests: Count of 5xx responses
- Unhealthy Host Count: Number of unhealthy backend instances
- Throughput: Bytes/second processed
- Current Connections: Active client connections
- Capacity Units: Combined measure of compute, throughput, connections

**Diagnostic Settings**:
```hcl
resource "azurerm_monitor_diagnostic_setting" "appgw" {
  name                       = "${local.name_prefix}-appgw-diag"
  target_resource_id         = azurerm_application_gateway.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }

  enabled_log {
    category = "ApplicationGatewayPerformanceLog"
  }

  enabled_log {
    category = "ApplicationGatewayFirewallLog"  # WAF logs
  }

  metric {
    category = "AllMetrics"
  }
}
```

### Container Apps Metrics (existing)

- Replica Count: Number of active replicas
- Request Success Rate: Percentage of successful requests
- Response Times: P50, P95, P99 latency
- System Logs: Container logs (stdout/stderr)
- Application Logs: Elixir/Phoenix application logs

### Alerts

**Application Gateway Alerts**:
```hcl
# Unhealthy backend alert
resource "azurerm_monitor_metric_alert" "appgw_unhealthy_backend" {
  name                = "${local.name_prefix}-appgw-unhealthy-backend"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_application_gateway.main.id]
  severity            = 1  # Critical

  criteria {
    metric_name      = "UnhealthyHostCount"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}
```

---

## Deployment Workflow

**Recommended Deployment Order**:

1. **Dev Environment**:
   - Apply Terraform changes to dev environment first
   - Validate Application Gateway → Container Apps connectivity
   - Test WebSocket connections (Phoenix LiveView)
   - Configure custom domain DNS (if using custom domain)
   - Validate ACME certificate provisioning

2. **DNS Configuration** (if custom domain):
   - Update domain registrar NS records to point to Azure DNS name servers
   - ACME provider automatically creates DNS TXT records for validation
   - ACME provider validates domain ownership via DNS-01 challenge
   - Certificate provisioned and uploaded to Application Gateway

3. **Production Environment**:
   - Apply Terraform changes to production after dev validation
   - Monitor ACME certificate renewal (automatic, 30 days before expiry)
   - Test zone-redundant failover (optional)
   - Enable WAF in Detection mode, tune exclusions, switch to Prevention mode

**Terragrunt Commands**:
```bash
# Dev deployment
cd terraform/env/dev
terragrunt plan
terragrunt apply

# Production deployment
cd terraform/env/production
terragrunt plan
terragrunt apply
```

---

## Failure Scenarios and Recovery

### Zone Failure (Production)

**Scenario**: Availability zone 1 becomes unavailable

**Expected Behavior**:
- Application Gateway: Traffic redistributes to instances in zones 2 and 3 within seconds
- Container Apps: Replicas in zone 1 lost; traffic routes to healthy zones; new replicas spawn if needed
- PostgreSQL: Automatic failover to standby in zone 2 in <120 seconds; no data loss (RPO=0)

**User Impact**: Brief connection interruptions (WebSocket reconnections); no data loss

### Certificate Expiry

**Scenario**: Let's Encrypt certificate expires before renewal

**Prevention**:
- ACME provider monitors certificate expiry (min_days_remaining = 30)
- Automatic renewal triggered on next `terraform apply` when threshold reached
- Azure Monitor alert at 30 days before expiry

**Recovery**:
- Manual `terraform apply` triggers immediate renewal
- Certificate uploaded to Application Gateway (zero-downtime rotation)

### Application Gateway Update

**Scenario**: Application Gateway configuration change requires update

**Expected Behavior**:
- Update operation takes 4-7 minutes
- Existing connections maintained during update
- New connections may experience brief latency increase

**Mitigation**: Schedule Application Gateway updates during maintenance windows

---

## References

- **Plan**: [plan.md](./plan.md) - High-level architecture decisions
- **Research**: [research.md](./research.md) - Azure Well-Architected Framework analysis
- **Quickstart**: [quickstart.md](./quickstart.md) - Provisioning guide (to be created)
- **Azure Application Gateway**: https://learn.microsoft.com/azure/application-gateway/
- **Azure Container Apps Networking**: https://learn.microsoft.com/azure/container-apps/networking
- **ACME Provider**: https://registry.terraform.io/providers/vancluever/acme/2.43.0
