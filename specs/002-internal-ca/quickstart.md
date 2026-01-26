# Provisioning Quickstart Guide

**Branch**: `002-internal-ca` | **Date**: 2026-01-26 | **Plan**: [plan.md](./plan.md)

This guide provides step-by-step instructions for provisioning Azure Application Gateway as a reverse proxy for internal-only Container Apps.

**IMPORTANT**: This guide covers **provisioning steps only** - no Terraform code is included. Terraform implementation will be generated in the next phase by the `/iac.implement` command.

---

## Prerequisites

### Required Tools

**1. Terraform**:
```bash
# Version 1.8+ required (tested with 1.14.3)
terraform version
# Terraform v1.14.3

# If not installed:
# macOS: brew install terraform
# Linux: https://developer.hashicorp.com/terraform/install
# Windows: https://developer.hashicorp.com/terraform/install
```

**2. Terragrunt**:
```bash
# Version 0.50+ required
terragrunt --version
# terragrunt version v0.50.0

# If not installed:
# macOS: brew install terragrunt
# Linux/Windows: https://terragrunt.gruntwork.io/docs/getting-started/install/
```

**3. Azure CLI**:
```bash
# Version 2.50+ required
az --version
# azure-cli 2.50.0

# If not installed:
# macOS: brew install azure-cli
# Linux/Windows: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli
```

**4. Trivy** (security scanning):
```bash
# Version 0.45+ required
trivy --version
# Version: 0.45.0

# If not installed:
# macOS: brew install trivy
# Linux/Windows: https://aquasecurity.github.io/trivy/latest/getting-started/installation/
```

### Azure Account Setup

**1. Azure Subscription**:
- Active Azure subscription with Owner or Contributor role
- Subscription must support canadacentral region
- Quota available for Application Gateway Standard_v2 SKU

**2. Azure CLI Authentication**:
```bash
# Login to Azure
az login

# Set default subscription
az account set --subscription "<subscription-id-or-name>"

# Verify authentication
az account show
```

**3. Service Principal** (for CI/CD):
```bash
# Create service principal with Contributor role
az ad sp create-for-rbac \
  --name "navigator-terraform-sp" \
  --role Contributor \
  --scopes /subscriptions/<subscription-id>

# Output (save securely):
# {
#   "appId": "...",       # AZURE_CLIENT_ID
#   "password": "...",    # AZURE_CLIENT_SECRET
#   "tenant": "..."       # AZURE_TENANT_ID
# }
```

### Repository Setup

**1. Clone Repository**:
```bash
git clone <repository-url>
cd navigator-az-terraform
git checkout 002-internal-ca
```

**2. Verify Existing Infrastructure**:
```bash
# Existing Terraform state should include:
# - Virtual Network (10.240.0.0/16)
# - Container Apps Environment (VNet-integrated)
# - Navigator Container App (public ingress currently)
# - PostgreSQL Flexible Server
# - Subnets: Container Apps (10.240.1.0/24), PostgreSQL (10.240.2.0/24), App Gateway (10.240.3.0/24)

cd terraform/env/dev
terragrunt state list
```

**Expected Resources** (partial list):
```
azurerm_virtual_network.this
azurerm_subnet.ca
azurerm_subnet.db
azurerm_subnet.appgw
azurerm_container_app_environment.this
azurerm_container_app.navigator
azurerm_postgresql_flexible_server.this
```

---

## State Backend Setup

**No state backend setup required** - using existing Azure Blob Storage backend managed by Terragrunt.

**Existing Configuration** (verify in `terraform/env/*/terragrunt.hcl`):
```hcl
remote_state {
  backend = "azurerm"

  config = {
    resource_group_name  = "navigator-terraform-state-rg"
    storage_account_name = "navtfstate<uniqueness>"
    container_name       = "tfstate"
    key                  = "${path_relative_to_include()}/terraform.tfstate"
    use_azuread_auth     = true
    use_msi              = true
  }
}
```

**Verification**:
```bash
# Check state backend connectivity
cd terraform/env/dev
terragrunt init

# Expected output:
# Initializing the backend...
# Successfully configured the backend "azurerm"!
```

---

## Provisioning Steps

### Phase 1: Dev Environment Deployment

**Purpose**: Validate infrastructure changes in dev environment before promoting to production

**1. Review Terraform Plan**:
```bash
cd terraform/env/dev

# Generate execution plan
terragrunt plan

# Review changes carefully:
# - NEW: Application Gateway resources (gateway, public IP, WAF policy if enabled)
# - NEW: ACME certificate resources (if custom domain provided)
# - NEW: Private DNS zone for Container Apps
# - MODIFIED: Container Apps subnet size (10.240.1.0/24 → 10.240.1.0/23)
# - MODIFIED: Container Apps ingress (external_enabled: true → false)
# - MODIFIED: Container Apps NSG (new rule allowing App Gateway traffic)
# - MODIFIED: DNS A record (points to App Gateway IP instead of Container Apps IP)
```

**2. Apply Infrastructure Changes**:
```bash
# Apply with auto-approval (use with caution)
terragrunt apply

# Expected duration: 8-12 minutes (Application Gateway takes 6-8 minutes to provision)
```

**3. Verify Application Gateway Deployment**:
```bash
# Get Application Gateway details
az network application-gateway show \
  --name nav-dev-appgw \
  --resource-group <resource-group-name> \
  --output table

# Verify public IP assignment
az network public-ip show \
  --name nav-dev-appgw-pip \
  --resource-group <resource-group-name> \
  --query ipAddress \
  --output tsv
```

**4. Verify Container Apps Internal Ingress**:
```bash
# Get Container Apps details
az containerapp show \
  --name nav-dev-ca-001 \
  --resource-group <resource-group-name> \
  --output json | jq '.properties.configuration.ingress'

# Expected output:
# {
#   "external": false,        # ✓ Internal ingress
#   "fqdn": "nav-dev-ca-001.internal.<env-domain>",
#   "targetPort": 4000,
#   ...
# }
```

**5. Verify Private DNS Zone**:
```bash
# List Private DNS zones
az network private-dns zone list \
  --resource-group <resource-group-name> \
  --output table

# Check A records
az network private-dns record-set a list \
  --zone-name <container-apps-env-domain> \
  --resource-group <resource-group-name> \
  --output table

# Expected records:
# * → Container Apps environment static IP
# @ → Container Apps environment static IP
```

**6. Verify NSG Rules**:
```bash
# List NSG rules for Container Apps NSG
az network nsg rule list \
  --nsg-name nav-dev-ca-nsg \
  --resource-group <resource-group-name> \
  --output table

# Expected new rule:
# AllowAppGatewayHttps | Priority: 100 | Allow | TCP | 10.240.3.0/24 → 10.240.1.0/23:443
```

---

### Phase 2: Custom Domain Configuration (Optional)

**Skip this phase if using default Azure domain** (no custom domain provided)

**Prerequisites**:
- Custom domain registered (e.g., `navigator-dev.example.gc.ca`)
- Access to domain registrar for NS record updates

**1. Get Azure DNS Name Servers**:
```bash
# List name servers for Azure DNS zone
az network dns zone show \
  --name <domain-name> \
  --resource-group <resource-group-name> \
  --query nameServers \
  --output table

# Output example:
# ns1-01.azure-dns.com.
# ns2-01.azure-dns.net.
# ns3-01.azure-dns.org.
# ns4-01.azure-dns.info.
```

**2. Update Domain Registrar**:
- Log in to domain registrar control panel
- Update NS records to point to Azure DNS name servers (from step 1)
- Wait for DNS propagation (5 minutes - 24 hours, typically 15-30 minutes)

**3. Verify DNS Propagation**:
```bash
# Check NS records
dig NS <domain-name>

# Expected output should include Azure DNS name servers

# Check A record (should resolve to Application Gateway public IP)
dig A <domain-name>

# Wait until A record resolves to Application Gateway IP before proceeding
```

**4. Verify ACME Certificate Provisioning**:
```bash
# Check Application Gateway SSL certificate
az network application-gateway ssl-cert show \
  --gateway-name nav-dev-appgw \
  --name navigator-ssl-cert \
  --resource-group <resource-group-name> \
  --output json | jq '.provisioningState'

# Expected: "Succeeded"
```

**5. ACME DNS-01 Challenge Verification** (automatic):
- ACME provider automatically creates DNS TXT records in Azure DNS zone
- Let's Encrypt validates domain ownership via DNS query
- Certificate issued and uploaded to Application Gateway
- TXT records cleaned up after validation

**Note**: ACME staging endpoint used for dev environment to avoid Let's Encrypt rate limits; production uses production endpoint

---

### Phase 3: Validation and Testing

**1. Test Public Access via Application Gateway**:
```bash
# Get Application Gateway public IP
APPGW_IP=$(az network public-ip show \
  --name nav-dev-appgw-pip \
  --resource-group <resource-group-name> \
  --query ipAddress \
  --output tsv)

echo "Application Gateway IP: $APPGW_IP"

# Test HTTP access (should redirect to HTTPS if enabled)
curl -I http://$APPGW_IP

# Expected: 301 Moved Permanently (if HTTP redirect enabled)
# Location: https://$APPGW_IP/

# Test HTTPS access
curl -I https://$APPGW_IP

# Expected: 200 OK (Phoenix app home page)
```

**2. Test Custom Domain** (if configured):
```bash
# Test HTTPS access via custom domain
curl -I https://<domain-name>

# Expected: 200 OK

# Verify TLS certificate
openssl s_client -connect <domain-name>:443 -servername <domain-name> < /dev/null 2>/dev/null | openssl x509 -noout -text | grep -A2 "Issuer"

# Expected: Issuer: CN = Let's Encrypt (or staging CA for dev)
```

**3. Test WebSocket Connections** (Phoenix LiveView):
```bash
# Access Navigator application in browser
open https://$APPGW_IP  # or https://<domain-name>

# Open browser developer console (F12)
# Navigate to Network tab, filter by WS (WebSocket)
# Expected: WebSocket connection established to Phoenix Channels
# ws://[Application Gateway IP]/live/websocket or wss://... for HTTPS
```

**4. Verify Container Apps Not Directly Accessible**:
```bash
# Get Container Apps internal FQDN
CA_FQDN=$(az containerapp show \
  --name nav-dev-ca-001 \
  --resource-group <resource-group-name> \
  --query 'properties.configuration.ingress.fqdn' \
  --output tsv)

echo "Container Apps FQDN: $CA_FQDN"

# Attempt direct access (should fail - internal ingress only)
curl -I https://$CA_FQDN --max-time 10

# Expected: Timeout or connection refused (no direct public access)
```

**5. Test Health Probes**:
```bash
# Check Application Gateway backend health
az network application-gateway show-backend-health \
  --name nav-dev-appgw \
  --resource-group <resource-group-name> \
  --output json | jq '.backendAddressPools[0].backendHttpSettingsCollection[0].servers'

# Expected output:
# [
#   {
#     "health": "Healthy",
#     "ipConfiguration": null,
#     "address": "nav-dev-ca-001.internal.<env-domain>"
#   }
# ]
```

**6. Verify WAF Protection** (if enabled):
```bash
# Test SQL injection payload (should be blocked in Prevention mode)
curl "https://$APPGW_IP/?id=1' OR '1'='1" -I

# Expected (WAF in Detection mode): 200 OK (logged but not blocked)
# Expected (WAF in Prevention mode): 403 Forbidden (blocked)

# Check WAF logs in Log Analytics
az monitor log-analytics query \
  --workspace <log-analytics-workspace-id> \
  --analytics-query "AzureDiagnostics | where Category == 'ApplicationGatewayFirewallLog' | take 10" \
  --output table
```

---

### Phase 4: Production Deployment

**Prerequisites**:
- Dev environment deployed and validated
- Custom domain configured (if using)
- ACME certificate provisioned successfully in dev

**1. Review Production Terragrunt Configuration**:
```bash
cd terraform/env/production

# Review production-specific inputs
cat terragrunt.hcl

# Key differences from dev:
# - appgw_capacity_min: 2 (vs 1 in dev)
# - appgw_capacity_max: 5 (vs 1 in dev)
# - enable_zone_redundancy: true (vs false in dev)
# - acme_server_url: production endpoint (vs staging in dev)
# - domain_name: navigator.example.gc.ca (vs null in dev)
```

**2. Generate Terraform Plan**:
```bash
# Generate execution plan
terragrunt plan

# Review changes carefully:
# - Same resources as dev, but with production configuration
# - Zone-redundant Application Gateway (zones 1, 2, 3)
# - Autoscaling configuration (min 2, max 5 instances)
# - Production ACME endpoint (Let's Encrypt production)
```

**3. Apply Infrastructure Changes**:
```bash
# Apply with auto-approval (use with caution)
terragrunt apply

# Expected duration: 10-15 minutes (zone-redundant Application Gateway takes longer)
```

**4. Verify Zone-Redundant Deployment**:
```bash
# Check Application Gateway zones
az network application-gateway show \
  --name nav-production-appgw \
  --resource-group <resource-group-name> \
  --query 'zones' \
  --output table

# Expected: ["1", "2", "3"]

# Check public IP zones
az network public-ip show \
  --name nav-production-appgw-pip \
  --resource-group <resource-group-name> \
  --query 'zones' \
  --output table

# Expected: ["1", "2", "3"]
```

**5. Verify Autoscaling Configuration**:
```bash
# Check autoscale configuration
az network application-gateway show \
  --name nav-production-appgw \
  --resource-group <resource-group-name> \
  --query 'autoscaleConfiguration' \
  --output json

# Expected:
# {
#   "minCapacity": 2,
#   "maxCapacity": 5
# }
```

**6. Test Production Deployment**:
- Repeat validation steps from Phase 3 for production environment
- Verify custom domain resolves to production Application Gateway IP
- Verify Let's Encrypt production certificate (not staging)
- Test WebSocket connections under load (multiple concurrent users)

**7. Enable WAF** (optional):
```bash
# Update terragrunt.hcl
# enable_waf = true

# Apply changes
terragrunt apply

# Verify WAF policy attached
az network application-gateway show \
  --name nav-production-appgw \
  --resource-group <resource-group-name> \
  --query 'firewallPolicy.id' \
  --output tsv

# Expected: /subscriptions/.../resourceGroups/.../providers/Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies/nav-production-waf-policy
```

---

## Monitoring and Observability

### Enable Diagnostic Settings

**1. Application Gateway Logs**:
```bash
# Create Log Analytics workspace (if not exists)
az monitor log-analytics workspace create \
  --resource-group <resource-group-name> \
  --workspace-name nav-<env>-law

# Enable diagnostic settings for Application Gateway
az monitor diagnostic-settings create \
  --name appgw-diag \
  --resource <application-gateway-resource-id> \
  --workspace <log-analytics-workspace-id> \
  --logs '[{"category": "ApplicationGatewayAccessLog", "enabled": true}, {"category": "ApplicationGatewayPerformanceLog", "enabled": true}, {"category": "ApplicationGatewayFirewallLog", "enabled": true}]' \
  --metrics '[{"category": "AllMetrics", "enabled": true}]'
```

**2. Container Apps Logs** (existing):
- Log Analytics integration already enabled
- No changes required

**3. PostgreSQL Logs** (existing):
- Enhanced Metrics and Query Performance Insight enabled
- No changes required

### Configure Alerts

**1. Application Gateway Unhealthy Backend Alert**:
```bash
# Create action group (if not exists)
az monitor action-group create \
  --name nav-<env>-alerts \
  --resource-group <resource-group-name> \
  --short-name NavAlerts \
  --email-receiver name=DevOps email=devops@example.gc.ca

# Create metric alert
az monitor metrics alert create \
  --name appgw-unhealthy-backend \
  --resource-group <resource-group-name> \
  --scopes <application-gateway-resource-id> \
  --condition "avg UnhealthyHostCount > 0" \
  --action <action-group-id> \
  --description "Alert when Application Gateway backend is unhealthy" \
  --severity 1
```

**2. Certificate Expiry Alert**:
```bash
# Create alert for certificate expiry (30 days before)
# Note: This requires custom metric from Terraform output

# Alternative: Monitor via Terraform output
terragrunt output certificate_expiry

# Set up calendar reminder 30 days before expiry to trigger renewal via terraform apply
```

### Access Logs

**1. Application Gateway Access Logs**:
```bash
# Query recent access logs
az monitor log-analytics query \
  --workspace <log-analytics-workspace-id> \
  --analytics-query "AzureDiagnostics | where Category == 'ApplicationGatewayAccessLog' | order by TimeGenerated desc | take 100" \
  --output table
```

**2. WAF Logs** (if enabled):
```bash
# Query WAF blocked requests
az monitor log-analytics query \
  --workspace <log-analytics-workspace-id> \
  --analytics-query "AzureDiagnostics | where Category == 'ApplicationGatewayFirewallLog' and action_s == 'Blocked' | order by TimeGenerated desc | take 100" \
  --output table
```

**3. Container Apps Logs** (existing):
```bash
# Query Container Apps system logs
az monitor log-analytics query \
  --workspace <log-analytics-workspace-id> \
  --analytics-query "ContainerAppSystemLogs_CL | where ContainerAppName_s == 'nav-<env>-ca-001' | order by TimeGenerated desc | take 100" \
  --output table
```

---

## Certificate Renewal

### Automatic Renewal (ACME Provider)

**Renewal Trigger**:
- ACME provider monitors certificate expiry in Terraform state
- Automatic renewal triggered when `min_days_remaining = 30` threshold reached
- Renewal requires running `terraform apply`

**Recommended Schedule**:
```bash
# Set up scheduled Terraform apply (CI/CD pipeline)
# Run weekly or bi-weekly to catch renewal window
# Example: GitHub Actions scheduled workflow

# Manual renewal (if needed)
cd terraform/env/<environment>
terragrunt apply

# ACME provider will automatically renew if within 30-day threshold
```

**Certificate Rotation**:
- New certificate uploaded to Application Gateway during `terraform apply`
- Zero-downtime rotation (Application Gateway supports live certificate updates)
- Old certificate remains valid until expiry (no immediate revocation)

**Monitoring Certificate Expiry**:
```bash
# Check current certificate expiry
terragrunt output certificate_expiry

# Expected output: "2026-04-26T00:00:00Z" (90 days from issuance)
```

**Manual Renewal** (emergency):
```bash
# Force certificate renewal before threshold
# 1. Taint ACME certificate resource
terragrunt state rm acme_certificate.navigator[0]

# 2. Re-apply to trigger new certificate request
terragrunt apply

# 3. Verify new certificate provisioned
terragrunt output certificate_expiry
```

---

## Rollback Procedures

### Scenario 1: Application Gateway Deployment Fails

**Symptoms**:
- `terraform apply` fails during Application Gateway creation
- Partial resources created (public IP, subnets)

**Rollback Steps**:
```bash
# 1. Review error message
terragrunt apply 2>&1 | tee apply-error.log

# 2. Destroy failed resources
terragrunt destroy -target=azurerm_application_gateway.main

# 3. Fix configuration issue (based on error message)
# 4. Re-apply
terragrunt apply
```

### Scenario 2: Container Apps Unreachable After Deployment

**Symptoms**:
- Application Gateway deployed successfully
- Backend health probe shows "Unhealthy"
- Container Apps not accessible

**Diagnosis**:
```bash
# Check backend health
az network application-gateway show-backend-health \
  --name nav-<env>-appgw \
  --resource-group <resource-group-name> \
  --output json | jq '.backendAddressPools[0].backendHttpSettingsCollection[0].servers'

# Common issues:
# 1. Private DNS zone not linked to VNet
# 2. NSG rules blocking traffic
# 3. Container Apps replicas not running
```

**Rollback Steps**:
```bash
# Revert Container Apps ingress to public (temporary)
# 1. Update Terraform configuration
# ingress { external_enabled = true }

# 2. Apply changes
terragrunt apply

# 3. Verify Container Apps accessible directly
curl -I https://<container-apps-fqdn>

# 4. Fix Application Gateway configuration
# 5. Revert Container Apps to internal ingress
# ingress { external_enabled = false }

# 6. Re-apply
terragrunt apply
```

### Scenario 3: ACME Certificate Provisioning Fails

**Symptoms**:
- DNS validation fails
- Certificate not issued by Let's Encrypt
- Application Gateway listener has no SSL certificate

**Diagnosis**:
```bash
# Check DNS TXT records
dig TXT _acme-challenge.<domain-name>

# Check Azure DNS zone
az network dns record-set txt list \
  --zone-name <domain-name> \
  --resource-group <resource-group-name> \
  --output table
```

**Rollback Steps**:
```bash
# 1. Remove custom domain temporarily
# terragrunt.hcl: domain_name = null

# 2. Apply changes (removes ACME certificate resources)
terragrunt apply

# 3. Fix DNS configuration (NS records, zone delegation)

# 4. Re-enable custom domain
# terragrunt.hcl: domain_name = "navigator.example.gc.ca"

# 5. Re-apply
terragrunt apply
```

---

## Troubleshooting

### Issue: Application Gateway Backend Unhealthy

**Diagnosis**:
```bash
# Check backend health details
az network application-gateway show-backend-health \
  --name nav-<env>-appgw \
  --resource-group <resource-group-name> \
  --output json | jq '.backendAddressPools[0].backendHttpSettingsCollection[0].servers[0]'

# Common causes:
# - Health probe path mismatch (ensure Container Apps responds 200 OK on `/`)
# - Private DNS resolution failure (check Private DNS zone link)
# - NSG rules blocking traffic (verify AllowAppGatewayHttps rule)
```

**Resolution**:
```bash
# Verify Container Apps health probe
az containerapp show \
  --name nav-<env>-ca-001 \
  --resource-group <resource-group-name> \
  --query 'properties.template.containers[0].probes' \
  --output json

# Test Private DNS resolution from Application Gateway subnet
# (requires VM in Application Gateway subnet for testing)

# Verify NSG rules
az network nsg rule list \
  --nsg-name nav-<env>-ca-nsg \
  --resource-group <resource-group-name> \
  --output table
```

### Issue: WebSocket Connections Dropping

**Diagnosis**:
```bash
# Check Application Gateway timeout settings
az network application-gateway show \
  --name nav-<env>-appgw \
  --resource-group <resource-group-name> \
  --query 'backendHttpSettingsCollection[0].requestTimeout' \
  --output tsv

# Expected: 180 (seconds)
```

**Resolution**:
```bash
# Increase request timeout if needed
# Update Terraform configuration:
# backend_http_settings { request_timeout = 300 }

# Apply changes
terragrunt apply
```

### Issue: Certificate Renewal Fails

**Diagnosis**:
```bash
# Check ACME provider logs (in Terraform apply output)
terragrunt apply 2>&1 | grep -A10 "acme_certificate"

# Common causes:
# - DNS zone not accessible (NS records changed)
# - Rate limit reached (Let's Encrypt: 50 certificates/week)
# - Azure DNS API authentication failure
```

**Resolution**:
```bash
# Use staging ACME endpoint for testing
# terragrunt.hcl: acme_server_url = "https://acme-staging-v02.api.letsencrypt.org/directory"

# Re-apply
terragrunt apply

# After testing successful, switch back to production endpoint
# terragrunt.hcl: acme_server_url = "https://acme-v02.api.letsencrypt.org/directory"

# Re-apply
terragrunt apply
```

---

## Security Scanning

### Run Trivy Before Deployment

```bash
# Scan Terraform configuration for security issues
cd terraform/azure
trivy config .

# Expected: No HIGH or CRITICAL issues
# Review MEDIUM and LOW issues, assess risk

# Example issues to fix:
# - Missing NSG rules
# - Overly permissive security groups
# - Unencrypted resources
```

### Common Security Findings

**1. Application Gateway Subnet Without NSG**:
- **Finding**: Application Gateway subnet has no NSG attached
- **Resolution**: This is expected - Azure platform requirement; security managed through backend NSG rules
- **Action**: Suppress finding (false positive)

**2. Public IP Address**:
- **Finding**: Application Gateway has public IP address
- **Resolution**: This is intentional - Application Gateway is internet-facing reverse proxy
- **Action**: Accept risk (required for architecture)

**3. TLS 1.2 Minimum**:
- **Finding**: TLS 1.0/1.1 not explicitly disabled
- **Resolution**: Terraform configuration enforces TLS 1.2 minimum via `min_protocol_version = "TLSv1_2"`
- **Action**: Verify configuration, suppress finding if correct

---

## Cost Estimation

### Monthly Cost Breakdown

**Dev Environment**:
```
Application Gateway Standard_v2 (1 instance):     ~$150/month
Container Apps (existing):                        ~$50/month
PostgreSQL Burstable (existing):                  ~$100/month
VNet, NSG, DNS (existing):                        ~$10/month
---------------------------------------------------------
Total Dev Environment:                            ~$310/month
```

**Production Environment**:
```
Application Gateway Standard_v2 (2-5 instances):  ~$250/month
WAF Policy (optional):                            ~$150/month
Container Apps zone-redundant (existing):         ~$200/month
PostgreSQL General Purpose HA (existing):         ~$500/month
VNet, NSG, DNS, NAT Gateway (existing):           ~$50/month
---------------------------------------------------------
Total Production (without WAF):                   ~$1,000/month
Total Production (with WAF):                      ~$1,150/month
```

**Cost Optimization Tips**:
- Dev: Use single-zone Application Gateway (current configuration)
- Dev: Disable WAF (current configuration)
- Production: Enable autoscaling to match actual load (current: min 2, max 5)
- Production: Enable WAF only after validation in dev

---

## Next Steps

After successful provisioning:

1. **Enable WAF in Detection Mode** (production):
   - Update `terragrunt.hcl`: `enable_waf = true`, `waf_mode = "Detection"`
   - Apply changes: `terragrunt apply`
   - Monitor WAF logs for false positives (1-2 weeks)
   - Tune exclusions if needed
   - Switch to Prevention mode: `waf_mode = "Prevention"`

2. **Set Up CI/CD Pipeline**:
   - Automate Terraform apply on merge to main (dev environment)
   - Manual approval gate for production deployment
   - Scheduled Terraform apply for certificate renewal (weekly)

3. **Configure Monitoring Dashboards**:
   - Azure Workbooks for Application Gateway metrics
   - Application Insights for end-to-end tracing
   - Alerts for unhealthy backends, certificate expiry

4. **Test Zone-Redundant Failover** (production):
   - Simulate zone failure (optional, requires Azure support ticket)
   - Verify automatic failover and recovery
   - Document RTO/RPO observed

5. **Security Hardening**:
   - Enable Microsoft Defender for Cloud
   - Implement Azure Policy for compliance
   - Review RBAC permissions (least privilege)

---

## References

- **Plan**: [plan.md](./plan.md) - High-level architecture decisions
- **Research**: [research.md](./research.md) - Azure Well-Architected Framework analysis
- **Architecture**: [architecture.md](./architecture.md) - Detailed infrastructure specifications
- **Modules**: [modules.md](./modules.md) - Module specifications (direct resources approach)
- **Azure Application Gateway Documentation**: https://learn.microsoft.com/azure/application-gateway/
- **Container Apps Networking**: https://learn.microsoft.com/azure/container-apps/networking
- **ACME Provider Documentation**: https://registry.terraform.io/providers/vancluever/acme/2.43.0/docs
- **Let's Encrypt Rate Limits**: https://letsencrypt.org/docs/rate-limits/
