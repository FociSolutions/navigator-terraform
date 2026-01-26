# Module Specifications

**Branch**: `002-internal-ca` | **Date**: 2026-01-26 | **Plan**: [plan.md](./plan.md) | **Research**: [research.md](./research.md)

---

## Module Strategy

### Decision: Direct Resources (No Custom Modules)

**Approach**: Use direct `azurerm_*` resource blocks instead of creating custom Terraform modules or using Azure Verified Modules (AVM).

**Rationale** (from Navigator principles.md):

**Principle: "Prefer Resource Simplicity"** states:
> "Infrastructure code must prioritize clarity and maintainability through direct resource definitions over module abstractions. Direct resources provide transparency, reduce indirection, and simplify debugging compared to wrapped module interfaces that obscure configuration details."

**Application to this feature**:
1. **Application Gateway configuration** is straightforward: SKU, listeners, backend pools, routing rules, health probes
2. **Container Apps ingress change** is a single attribute modification: `external_enabled = false`
3. **Private DNS zone** is simple: zone creation, virtual network link, A records
4. **NSG rule addition** is explicit: single inbound rule allowing Application Gateway → Container Apps

None of these warrant module abstraction. Direct resources make configuration explicit and enable straightforward troubleshooting.

**From research.md**:
> "While not using modules for this implementation, AVM modules are documented here for reference... **For this infrastructure**: None of the above conditions apply. Application Gateway, Container Apps, and PostgreSQL configurations are straightforward enough for direct resources."

---

## Direct Resource Blocks

### New Resources (this feature)

**1. Application Gateway**:
```hcl
# File: terraform/azure/app-gateway.tf
resource "azurerm_application_gateway" "main" {
  name                = local.appgw_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  sku {
    name = var.appgw_sku_name
    tier = var.appgw_tier
  }

  # ... explicit configuration (no module abstraction)
}
```

**Rationale**: Application Gateway resource block with ~100-150 lines of configuration is manageable and explicit; module would hide important details

**2. Application Gateway Public IP**:
```hcl
# File: terraform/azure/app-gateway.tf
resource "azurerm_public_ip" "appgw" {
  name                = "${local.name_prefix}-appgw-pip"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "Standard"
  allocation_method   = "Static"
  zones               = var.enable_zone_redundancy ? ["1", "2", "3"] : null
}
```

**Rationale**: Simple resource, no abstraction needed

**3. WAF Policy** (optional):
```hcl
# File: terraform/azure/app-gateway.tf
resource "azurerm_web_application_firewall_policy" "main" {
  count = var.enable_waf ? 1 : 0

  name                = "${local.name_prefix}-waf-policy"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  # ... policy configuration
}
```

**Rationale**: Feature flag with count makes optional WAF explicit; module would add unnecessary complexity

**4. ACME Certificate**:
```hcl
# File: terraform/azure/acme.tf
resource "acme_certificate" "navigator" {
  count = var.domain_name != null ? 1 : 0

  account_key_pem = acme_registration.account.account_key_pem
  common_name     = var.domain_name

  # ... DNS challenge configuration
}
```

**Rationale**: ACME provider integration is provider-specific; module would obscure certificate lifecycle

**5. Private DNS Zone**:
```hcl
# File: terraform/azure/dns-private.tf
resource "azurerm_private_dns_zone" "ca" {
  name                = azurerm_container_app_environment.this.default_domain
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "ca" {
  name                  = "${local.name_prefix}-ca-dns-link"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.ca.name
  virtual_network_id    = azurerm_virtual_network.this.id
}

resource "azurerm_private_dns_a_record" "ca_wildcard" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.ca.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  records             = [azurerm_container_app_environment.this.static_ip_address]
}
```

**Rationale**: Three simple resources with clear dependencies; module would add indirection without benefit

### Modified Resources

**1. Container Apps NSG**:
```hcl
# File: terraform/azure/security.tf
# NEW RULE: Allow HTTPS from Application Gateway
resource "azurerm_network_security_rule" "ca_allow_appgw" {
  name                        = "AllowAppGatewayHttps"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "10.240.3.0/24"  # Application Gateway subnet
  destination_address_prefix  = "10.240.1.0/23"  # Container Apps subnet
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.ca.name
}
```

**Rationale**: Single NSG rule addition; explicit source/destination prefixes visible in code

**2. Container Apps Subnet**:
```hcl
# File: terraform/azure/vnet.tf
resource "azurerm_subnet" "ca" {
  name                 = "${local.name_prefix}-ca-snet"
  # ...
  address_prefixes     = ["10.240.1.0/23"]  # CHANGED from /24 to /23
  # ...
}
```

**Rationale**: Single attribute change; module would obscure subnet size modification

**3. Container App Ingress**:
```hcl
# File: terraform/azure/container-apps.tf
resource "azurerm_container_app" "navigator" {
  # ...

  ingress {
    external_enabled           = false  # CHANGED from true
    allow_insecure_connections = false
    target_port                = 4000
  }

  # ...
}
```

**Rationale**: Single attribute change; explicit modification visible in git diff

**4. DNS A Record**:
```hcl
# File: terraform/azure/dns.tf
resource "azurerm_dns_a_record" "main" {
  count               = var.domain_name != null ? 1 : 0
  name                = "@"
  zone_name           = azurerm_dns_zone.main[0].name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  records             = [azurerm_public_ip.appgw.ip_address]  # CHANGED from Container Apps IP
}
```

**Rationale**: Single attribute change (IP address reference); module would hide critical dependency

---

## File Organization

### New Files

**1. terraform/azure/app-gateway.tf**:
- Application Gateway resource (`azurerm_application_gateway`)
- Public IP resource (`azurerm_public_ip`)
- WAF Policy resource (`azurerm_web_application_firewall_policy`) - conditional
- ~200-250 lines total

**2. terraform/azure/acme.tf**:
- ACME provider configuration (`provider "acme"`)
- ACME account registration (`acme_registration`)
- TLS private key for ACME account (`tls_private_key`)
- ACME certificate resource (`acme_certificate`) - conditional
- Random password for certificate P12 (`random_password`)
- ~100-150 lines total

**Rationale**: Separate files for Application Gateway and ACME configuration improve organization; both files contain related resources grouped by functionality

### Modified Files

**1. terraform/azure/versions.tf**:
- Add ACME provider version constraint (`vancluever/acme ~> 2.43`)

**2. terraform/azure/provider.tf**:
- Add ACME provider configuration block

**3. terraform/azure/vnet.tf**:
- Modify Container Apps subnet size (10.240.1.0/23)

**4. terraform/azure/security.tf**:
- Add NSG rule allowing Application Gateway → Container Apps traffic

**5. terraform/azure/container-apps.tf**:
- Modify ingress `external_enabled = false`

**6. terraform/azure/dns.tf**:
- Modify DNS A record to point to Application Gateway public IP
- Remove Container Apps custom domain resources (TXT record, custom domain binding, managed certificate, bind/unbind actions)

**7. terraform/azure/dns-private.tf**:
- Add Private DNS zone for Container Apps internal FQDN
- Add virtual network link
- Add wildcard and root A records

**8. terraform/azure/variables.tf**:
- Add Application Gateway variables (`appgw_sku_name`, `appgw_tier`, `appgw_capacity_min`, `appgw_capacity_max`)
- Add WAF variables (`enable_waf`, `waf_mode`)
- Add ACME variables (`acme_server_url`, `acme_email_address`)
- Add feature flag variables (`enable_zone_redundancy`, `enable_http_redirect`)

**9. terraform/azure/locals.tf**:
- Add Application Gateway resource naming (`appgw_name`, `appgw_pip_name`)

**10. terraform/azure/outputs.tf**:
- Add Application Gateway outputs (`appgw_public_ip`, `appgw_fqdn`, `certificate_expiry`)

---

## Variable Inputs

### Application Gateway Variables

```hcl
# terraform/azure/variables.tf

variable "appgw_sku_name" {
  type        = string
  description = "Application Gateway SKU name (Standard_v2)"
  default     = "Standard_v2"
}

variable "appgw_tier" {
  type        = string
  description = "Application Gateway tier (Standard_v2)"
  default     = "Standard_v2"
}

variable "appgw_capacity_min" {
  type        = number
  description = "Minimum Application Gateway capacity (dev: 1, prod: 2)"
}

variable "appgw_capacity_max" {
  type        = number
  description = "Maximum Application Gateway capacity (dev: 1, prod: 5)"
}

variable "enable_waf" {
  type        = bool
  description = "Enable Web Application Firewall policy"
  default     = false
}

variable "waf_mode" {
  type        = string
  description = "WAF mode: Detection or Prevention"
  default     = "Detection"

  validation {
    condition     = contains(["Detection", "Prevention"], var.waf_mode)
    error_message = "WAF mode must be Detection or Prevention"
  }
}
```

### ACME Variables

```hcl
variable "acme_server_url" {
  type        = string
  description = "ACME server URL (staging for dev, production for prod)"
  # Dev: https://acme-staging-v02.api.letsencrypt.org/directory
  # Prod: https://acme-v02.api.letsencrypt.org/directory
}

variable "acme_email_address" {
  type        = string
  description = "Email for ACME account registration and renewal notifications"
  sensitive   = true
}

variable "domain_name" {
  type        = string
  description = "Custom domain name (triggers ACME certificate provisioning when provided)"
  default     = null
}
```

### Feature Flags

```hcl
variable "enable_zone_redundancy" {
  type        = bool
  description = "Enable zone-redundant deployment (production only)"
  default     = false
}

variable "enable_http_redirect" {
  type        = bool
  description = "Enable HTTP to HTTPS redirect"
  default     = true
}
```

### Terragrunt Configuration

**Dev Environment** (`terraform/env/dev/terragrunt.hcl`):
```hcl
inputs = {
  environment                  = "dev"
  appgw_sku_name              = "Standard_v2"
  appgw_tier                  = "Standard_v2"
  appgw_capacity_min          = 1
  appgw_capacity_max          = 1
  enable_waf                   = false
  enable_zone_redundancy       = false
  enable_http_redirect         = true
  container_apps_subnet_prefix = "10.240.1.0/23"
  acme_email_address          = "devops-dev@example.gc.ca"
  acme_server_url             = "https://acme-staging-v02.api.letsencrypt.org/directory"
  domain_name                 = null  # Use default Container Apps domain
}
```

**Production Environment** (`terraform/env/production/terragrunt.hcl`):
```hcl
inputs = {
  environment                  = "production"
  appgw_sku_name              = "Standard_v2"
  appgw_tier                  = "Standard_v2"
  appgw_capacity_min          = 2
  appgw_capacity_max          = 5
  enable_waf                   = false  # Optional, set to true to enable
  enable_zone_redundancy       = true
  enable_http_redirect         = true
  waf_mode                    = "Detection"  # Used only if enable_waf = true
  container_apps_subnet_prefix = "10.240.1.0/23"
  acme_email_address          = "devops@example.gc.ca"
  acme_server_url             = "https://acme-v02.api.letsencrypt.org/directory"
  domain_name                 = "navigator.example.gc.ca"  # Triggers ACME certificate
}
```

---

## Output Values

### Application Gateway Outputs

```hcl
# terraform/azure/outputs.tf

output "appgw_public_ip" {
  description = "Application Gateway public IP address"
  value       = azurerm_public_ip.appgw.ip_address
}

output "appgw_fqdn" {
  description = "Application Gateway public FQDN"
  value       = azurerm_public_ip.appgw.fqdn
}

output "certificate_expiry" {
  description = "Let's Encrypt certificate expiry date"
  value       = var.domain_name != null ? acme_certificate.navigator[0].certificate_not_after : null
}

output "private_dns_zone_name" {
  description = "Private DNS zone name for Container Apps"
  value       = azurerm_private_dns_zone.ca.name
}

output "container_apps_internal_fqdn" {
  description = "Container Apps internal FQDN"
  value       = azurerm_container_app.navigator.ingress[0].fqdn
}
```

**Rationale**: Outputs provide essential information for DNS configuration, certificate monitoring, and troubleshooting

---

## Dependencies Between Resources

### Resource Graph

```
azurerm_resource_group.this
  ├── azurerm_virtual_network.this
  │   ├── azurerm_subnet.appgw (Application Gateway subnet)
  │   ├── azurerm_subnet.ca (Container Apps subnet - MODIFIED)
  │   └── azurerm_subnet.db (PostgreSQL subnet - existing)
  │
  ├── azurerm_public_ip.appgw [NEW]
  │
  ├── azurerm_container_app_environment.this
  │   ├── azurerm_container_app.navigator (ingress modified)
  │   └── azurerm_private_dns_zone.ca [NEW]
  │       ├── azurerm_private_dns_zone_virtual_network_link.ca
  │       ├── azurerm_private_dns_a_record.ca_wildcard
  │       └── azurerm_private_dns_a_record.ca_root
  │
  ├── azurerm_network_security_group.ca
  │   └── azurerm_network_security_rule.ca_allow_appgw [NEW]
  │
  ├── azurerm_web_application_firewall_policy.main [NEW, optional]
  │
  ├── acme_registration.account [NEW]
  │   └── acme_certificate.navigator [NEW, conditional]
  │
  ├── azurerm_application_gateway.main [NEW]
  │   ├── depends_on: azurerm_subnet.appgw
  │   ├── depends_on: azurerm_public_ip.appgw
  │   ├── depends_on: azurerm_private_dns_zone_virtual_network_link.ca
  │   └── depends_on: azurerm_container_app.navigator
  │
  └── azurerm_dns_zone.main [existing, when custom domain]
      ├── azurerm_dns_a_record.main (points to appgw IP - MODIFIED)
      └── Used by acme_certificate for DNS-01 challenge
```

### Critical Dependencies

**1. Application Gateway → Private DNS Zone**:
- Application Gateway must wait for Private DNS zone to be linked to VNet
- Ensures Application Gateway can resolve Container Apps internal FQDN
- Explicit dependency: `depends_on = [azurerm_private_dns_zone_virtual_network_link.ca]`

**2. Application Gateway → Container Apps**:
- Application Gateway backend pool references Container Apps FQDN
- Implicit dependency via `azurerm_container_app.navigator.ingress[0].fqdn`

**3. ACME Certificate → DNS Zone**:
- ACME DNS-01 challenge requires Azure DNS zone for TXT record creation
- Implicit dependency via `AZURE_ZONE_NAME = var.domain_name`

**4. NSG Rule → Subnets**:
- NSG rule references Application Gateway subnet (10.240.3.0/24) and Container Apps subnet (10.240.1.0/23)
- Implicit dependency via address prefixes

---

## Testing Strategy

**No automated tests required** for this implementation (per Navigator principles: "Design for Simplicity")

**Manual Validation Steps** (documented in quickstart.md):
1. Verify Application Gateway public IP accessible via browser
2. Test HTTP→HTTPS redirect (if enabled)
3. Validate TLS certificate (Let's Encrypt)
4. Test WebSocket connections (Phoenix LiveView)
5. Verify Container Apps internal ingress (no direct public access)
6. Test zone-redundant failover (production only, optional)
7. Validate WAF protection (if enabled, using test payloads)

**Terraform Validation**:
```bash
# Syntax validation
terraform validate

# Security scanning
trivy config terraform/

# Format check
terraform fmt -check -recursive

# Plan review
terragrunt plan
```

---

## Alternative Approaches Considered

### Approach 1: Azure Verified Modules (AVM)

**Description**: Use official Microsoft AVM modules for Application Gateway, Virtual Network, Container Apps, PostgreSQL

**Rejected Rationale**:
- Navigator principle "Prefer Resource Simplicity" mandates direct resources over module abstractions
- AVM modules add indirection that obscures configuration details
- Module version management overhead (not captured in `.terraform.lock.hcl`)
- Team familiarity with direct resources from existing infrastructure
- No complex multi-resource patterns requiring validated composition

**Reference from research.md**:
> "While not using modules for this implementation, AVM modules are documented here for reference... **For this infrastructure**: None of the above conditions apply. Application Gateway, Container Apps, and PostgreSQL configurations are straightforward enough for direct resources."

### Approach 2: Custom Terraform Modules

**Description**: Create custom module `terraform/modules/application-gateway/` with inputs/outputs

**Rejected Rationale**:
- Violates Navigator principle "Prefer Resource Simplicity"
- Application Gateway configuration is straightforward (~200 lines) - manageable without abstraction
- Custom module would add maintenance overhead without benefit
- No reuse opportunity (single Application Gateway per environment)
- Debugging complexity increased with module indirection

### Approach 3: Separate Terraform State per Resource

**Description**: Use separate Terraform workspaces or state files for Application Gateway, Container Apps, networking

**Rejected Rationale**:
- Increases operational complexity (multiple `terraform apply` commands required)
- Dependency management between states is error-prone
- Existing Terragrunt setup already provides environment isolation
- No compliance requirement for separate state files
- Violates "Design for Simplicity" principle

---

## Summary

**Module Strategy**: Direct Terraform resource blocks in shared module (`terraform/azure/`), deployed via Terragrunt with environment-specific inputs

**File Organization**: New files for Application Gateway and ACME configuration; modified files for subnet size, ingress, NSG rules, DNS records

**No Custom Modules**: Navigator principle "Prefer Resource Simplicity" guides decision to use direct `azurerm_*` resources instead of module abstractions

**Dependency Management**: Explicit `depends_on` blocks for critical dependencies (Application Gateway → Private DNS zone); implicit dependencies via attribute references

**Testing**: Manual validation steps documented in quickstart.md; no automated tests required for straightforward infrastructure changes

**Rationale**: This approach maximizes transparency, reduces debugging complexity, and aligns with Navigator principles for simple, maintainable infrastructure code.

---

## References

- **Plan**: [plan.md](./plan.md) - High-level architecture decisions
- **Research**: [research.md](./research.md) - Azure Well-Architected Framework analysis and module recommendations
- **Architecture**: [architecture.md](./architecture.md) - Detailed infrastructure specifications
- **Principles**: [/.specify/memory/principles.md](/.specify/memory/principles.md) - Navigator infrastructure principles
- **Terraform Style Guide**: [.github/instructions/terraform.instructions.md](/.github/instructions/terraform.instructions.md)
