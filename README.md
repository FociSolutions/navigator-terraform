# Navigator Azure Infrastructure

This repository contains Terraform infrastructure-as-code (IaC) for deploying the [Navigator](https://github.com/canada-ca/navigator/) threat modeling application to Microsoft Azure.

Navigator is an Elixir/Phoenix web application providing real-time threat modeling capabilities with collaborative features.

---

## Architecture Overview

### Azure Services Deployed

- **Azure Application Gateway**: Reverse proxy with TLS termination and WAF protection
  - Public IP (zone-redundant in production)
  - Let's Encrypt certificates via ACME DNS-01 challenge
  - HTTP→HTTPS redirect
  - Health probes to Container Apps backend
  - Optional Web Application Firewall (OWASP CRS 3.2)

- **Azure Container Apps**: Serverless container runtime for Navigator application
  - Internal load balancer (VNet-only access via Application Gateway)
  - Session affinity for Phoenix LiveView WebSocket support
  - Auto-scaling based on HTTP requests (dev) or CPU utilization (production)
  - Health probes for startup and liveness monitoring

- **Azure Database for PostgreSQL Flexible Server**: Managed PostgreSQL database
  - Private VNet integration with delegated subnet
  - Zone-redundant high availability (production only)
  - Automated backups with configurable retention
  - Private DNS zone for secure connectivity

- **Azure Virtual Network**: Network isolation and security
  - 3 subnets: Container Apps (10.240.0.0/23), PostgreSQL (10.240.2.0/24), Application Gateway (10.240.3.0/24)
  - Network Security Groups (NSGs) for traffic control
  - Private DNS zones for Container Apps internal FQDN resolution
  - Service Endpoints for secure Azure service access
  - Optional NAT Gateway for static outbound IP (zone-redundant environments)

- **Azure DNS Zone** (optional): Custom domain support
  - Public DNS zone for subdomain (navigator-{env}.demo.focisolutions.com)
  - Automatic SSL certificate provisioning via Let's Encrypt (ACME provider)
  - A records pointing to Application Gateway public IP

- **Log Analytics Workspace**: Centralized logging and monitoring
  - Container Apps logs and metrics
  - Application Gateway access and performance logs
  - Query interface for troubleshooting
  - Retention: 30 days (dev), 90 days (production)

- **Azure Cognitive Services - OpenAI** (optional): AI integration
  - Conditional deployment via `create_azure_openai` flag
  - VNet integration for production (network ACLs)
  - API key management through Container Apps secrets

- **Azure Storage Account** (optional): User uploads and file storage
  - Conditional deployment via `create_storage_account` flag
  - Blob containers with lifecycle management
  - Private endpoint for production environments

---

## Prerequisites

### Required Azure Resources (Must Exist Before Deployment)

These resources (or equivalent) must be created manually before running Terraform:

1. **Resource Groups**:
   - `navigator-dev-rg` (Development environment)
   - `navigator-prod-rg` (Production environment)
   - `navigator-tfstate-rg` (Terraform state storage)

2. **Terraform State Storage Accounts** (in `navigator-tfstate-rg`):
   - `navtfstatedev` - Storage account for dev environment state
   - `navtfstateprod` - Storage account for production environment state
   - Both accounts must have:
     - Container named `tfstate`
     - Blob versioning enabled
     - Encryption at rest enabled
     - Access restricted to authenticated users

### Required Permissions

- **Azure RBAC Roles**:
  - `Contributor` on resource groups (`navigator-dev-rg`, `navigator-prod-rg`)
  - `Storage Blob Data Contributor` on state storage accounts

### Required Tools

- [Terraform](https://www.terraform.io/downloads) >= 1.9.0
- [Terragrunt](https://terragrunt.gruntwork.io/docs/getting-started/install/) >= 0.50.0
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) >= 2.50.0
- [Trivy](https://aquasecurity.github.io/trivy/) (optional, for security scanning)

### Authentication

Authenticate to Azure before deployment:

```bash
az login --scope https://management.azure.com//.default
az account set --subscription <SUBSCRIPTION_ID_OR_NAME>
```

---

## Repository Structure

```
navigator-az-terraform/
├── terraform/
│   ├── azure/                    # Shared Terraform module (infrastructure code)
│   │   ├── versions.tf           # Provider version constraints
│   │   ├── provider.tf           # Azure and ACME provider configuration
│   │   ├── variables.tf          # Input variable definitions
│   │   ├── outputs.tf            # Infrastructure outputs
│   │   ├── vnet.tf               # Virtual Network, subnets, NAT Gateway
│   │   ├── security.tf           # Network Security Groups (NSGs)
│   │   ├── dns-private.tf        # Private DNS zones for Container Apps and PostgreSQL
│   │   ├── dns.tf                # Public DNS zone and custom domain (optional)
│   │   ├── postgresql.tf         # PostgreSQL Flexible Server + database
│   │   ├── secrets.tf            # Random passwords for PostgreSQL, Phoenix
│   │   ├── container-apps.tf     # Container Apps Environment + Navigator app
│   │   ├── app-gateway.tf        # Application Gateway, public IP, WAF policy
│   │   ├── acme.tf               # Let's Encrypt certificate management
│   │   ├── acr.tf                # Azure Container Registry (optional)
│   │   ├── storage.tf            # Storage Account for user uploads (optional)
│   │   ├── auth-openai.tf        # Azure OpenAI Cognitive Services (optional)
│   │   └── identity.tf           # Managed identities and RBAC assignments
│   │
│   └── env/                      # Environment-specific configurations (Terragrunt)
│       ├── dev/
│       │   └── terragrunt.hcl    # Dev environment config (lower SKUs, scale-to-zero)
│       └── production/
│           └── terragrunt.hcl    # Production config (HA, zone redundancy, higher SKUs)
│
├── navigator/                    # Git submodule (Navigator application source)
├── specs/                        # Feature specifications and planning documents
├── .github/instructions/         # Code conventions and guidelines
├── .gitignore                    # Version control exclusions
├── AGENTS.md                     # Development guidelines for AI agents
└── README.md                     # This file
```

---

## Manual Deployment Steps

### Initial Deployment

> [!IMPORTANT]
> If deploying with a custom domain (`domain_name` variable set) - deployment requires a **two-step process** for ACME DNS-01 validation.

#### Step 1: Initial Apply (DNS Zone Creation)

1. **Run initial deployment:**
   ```bash
   cd terraform/env/{dev|production}
   terragrunt apply
   ```
   This creates the public DNS zone and Application Gateway infrastructure.

2. **Configure NS records at your domain registrar:**
   ```bash
   # Retrieve Azure DNS name servers
   terragrunt output dns_zone_nameservers
   ```
   Update your domain registrar's NS records with these 4 Azure DNS name servers.

   Example for `demo.focisolutions.com`:
   ```
   demo.focisolutions.com. IN NS ns1-XX.azure-dns.com.
   demo.focisolutions.com. IN NS ns2-XX.azure-dns.net.
   demo.focisolutions.com. IN NS ns3-XX.azure-dns.org.
   demo.focisolutions.com. IN NS ns4-XX.azure-dns.info.
   ```

3. **Wait for DNS propagation** (15 minutes to 48 hours). Verify with:
   ```bash
   dig NS demo.focisolutions.com @8.8.8.8
   ```

#### Step 2: Re-Apply (Certificate Provisioning)

4. **Re-run deployment:**
   ```bash
   terragrunt apply
   ```
   This triggers ACME DNS-01 challenge validation, provisions Let's Encrypt certificate, and uploads to Application Gateway.

**Without a custom domain** (`domain_name = null`), deployment succeeds on first apply using Application Gateway's default domain.

#### Accessing the Application

After successful deployment:

- **With custom domain**: `https://navigator-{env}.demo.focisolutions.com` (e.g., `navigator-dev.demo.focisolutions.com`)
- **Without custom domain**: Use Application Gateway public IP from outputs (`terragrunt output appgw_public_ip`)

### Authentication Provider Configuration (Optional)

**If using Google OAuth or Microsoft Entra ID authentication**:

Set authentication credentials as environment variables, then reference them in your Terragrunt configuration using `get_env()`:

#### Step 1: Set environment variables

```bash
# Google OAuth (optional)
export GOOGLE_CLIENT_ID="your-google-client-id"
export GOOGLE_CLIENT_SECRET="your-google-client-secret"

# Microsoft Entra ID OAuth (optional)
export MICROSOFT_CLIENT_ID="your-microsoft-client-id"
export MICROSOFT_CLIENT_SECRET="your-microsoft-client-secret"
export MICROSOFT_TENANT_ID="your-tenant-id"
```

#### Step 2: Uncomment authentication variables in terragrunt.hcl

Edit the appropriate environment configuration file:
- Development: `terraform/env/dev/terragrunt.hcl`
- Production: `terraform/env/production/terragrunt.hcl`

In the `inputs` block, uncomment the authentication variables you need:

```hcl
inputs = {
  # ... other configuration ...

  # Authentication (uncomment as needed)
  google_client_id         = get_env("GOOGLE_CLIENT_ID")
  google_client_secret     = get_env("GOOGLE_CLIENT_SECRET")
  microsoft_client_id      = get_env("MICROSOFT_CLIENT_ID")
  microsoft_client_secret  = get_env("MICROSOFT_CLIENT_SECRET")
  microsoft_tenant_id      = get_env("MICROSOFT_TENANT_ID")
}
```

#### Step 3: Deploy

```bash
cd terraform/env/{dev|production}
terragrunt apply
```

Credentials are automatically injected into Container Apps secrets and exposed as environment variables to the Navigator application.

### Destroying Infrastructure

> [!WARNING]
> This will permanently delete all resources and data.

```bash
cd terraform/env/{dev|production}

# Review resources to be destroyed
terragrunt plan -destroy

# Destroy infrastructure (requires manual confirmation)
terragrunt destroy
```

---

## Environment Configuration

### Development Environment

Configuration in `terraform/env/dev/terragrunt.hcl`:

```hcl
inputs = {
  environment                 = "dev"
  resource_group_name         = "navigator-dev-rg"
  container_cpu               = 0.25        # 0.25 vCPU
  container_memory            = "0.5Gi"     # 512 MB
  min_replicas                = 0           # Scale to zero when idle
  max_replicas                = 2
  postgres_sku                = "B_Standard_B1ms"  # Burstable tier
  postgres_storage_gb         = 32
  postgres_ha_enabled         = false       # Single-zone
  backup_retention_days       = 7
  enable_auto_shutdown        = true        # Cost savings
  enable_zone_redundancy      = false
  domain_name                 = "navigator-dev.demo.focisolutions.com"
  enable_outbound_internet    = true
  create_azure_openai         = false       # Disabled by default
  create_storage_account      = false       # Disabled by default
}
```

**Cost Optimizations**:
- Burstable PostgreSQL SKU (B1ms)
- Scale-to-zero for Container Apps (min_replicas=0)
- Single-zone deployment (no zone redundancy)
- Auto-shutdown schedules for cost savings

### Production Environment

Configuration in `terraform/env/production/terragrunt.hcl`:

```hcl
inputs = {
  environment                 = "production"
  resource_group_name         = "navigator-prod-rg"
  container_cpu               = 0.5         # 0.5 vCPU
  container_memory            = "1.0Gi"     # 1 GB
  min_replicas                = 1           # Always running
  max_replicas                = 10
  postgres_sku                = "GP_Standard_D2s_v3"  # General Purpose tier
  postgres_storage_gb         = 128
  postgres_ha_enabled         = true        # Zone-redundant HA
  backup_retention_days       = 14
  enable_auto_shutdown        = false       # Always available
  enable_zone_redundancy      = true        # Zone-redundant deployment
  domain_name                 = "navigator.demo.focisolutions.com"
  enable_outbound_internet    = true
  create_azure_openai         = false       # Configure based on requirements
  create_storage_account      = false       # Configure based on requirements
}
```

**Production Hardening**:
- General Purpose PostgreSQL SKU (D2s_v3)
- Zone-redundant high availability
- Always-on (min_replicas=1)
- Extended backup retention (14 days)
- Higher resource limits (max_replicas=10)

---

## Outputs

### Key Infrastructure Outputs

After deployment, retrieve outputs with:

```bash
cd terraform/env/{dev|production}
terragrunt output
```

**Available Outputs**:

- `container_apps_url`: Full HTTPS URL of the Navigator application (via Application Gateway)
- `container_apps_fqdn`: Internal FQDN of the Container App
- `container_apps_internal_fqdn`: Container Apps internal FQDN (backend)
- `appgw_public_ip`: Application Gateway public IP address
- `appgw_fqdn`: Application Gateway public FQDN
- `certificate_expiry`: Let's Encrypt certificate expiry date (if custom domain configured)
- `private_dns_zone_name`: Private DNS zone name for Container Apps
- `postgresql_fqdn`: PostgreSQL server FQDN (sensitive)
- `postgresql_connection_string`: Ecto-format connection string (sensitive)
- `dns_zone_nameservers`: Azure DNS name servers (for NS record configuration)
- `custom_domain_url`: Custom domain URL (if `domain_name` configured)
- `log_analytics_workspace_id`: Log Analytics Workspace ID for monitoring
- `vnet_id`: Virtual Network resource ID
- `storage_account_name`: Storage Account name (if created)

**Sensitive Outputs** (require `-json` flag or explicit `output` command):
- `postgresql_fqdn`
- `postgresql_connection_string`

---

## Security & Compliance

### Security Features

1. **Network Isolation**:
   - Application Gateway as single public entry point with TLS termination
   - Container Apps with internal load balancer (no direct internet access)
   - Private VNet integration for all compute and data resources
   - Network Security Groups (NSGs) with least-privilege rules
   - Private DNS zones for internal name resolution
   - Service Endpoints for secure Azure service access

2. **Defense-in-Depth**:
   - **Layer 1**: Application Gateway with TLS 1.2+ enforcement and strong cipher suites
   - **Layer 2**: Optional Web Application Firewall (OWASP CRS 3.2, Bot Manager)
   - **Layer 3**: NSG rules restricting traffic to Application Gateway subnet only
   - **Layer 4**: Container Apps internal load balancer with VNet-only access
   - **Layer 5**: PostgreSQL private subnet with delegated access

3. **Data Encryption**:
   - Encryption at rest for PostgreSQL (Azure-managed keys)
   - TLS 1.2+ encryption for data in transit (all connections)
   - Container Apps secrets encrypted by Azure platform
   - Let's Encrypt certificates for HTTPS (auto-renewal 30 days before expiry)

4. **Certificate Management**:
   - Automated certificate provisioning via ACME provider (Let's Encrypt)
   - DNS-01 challenge using Azure DNS for domain validation
   - Certificate auto-renewal (min_days_remaining = 30)
   - Certificates uploaded to both Application Gateway and Container Apps Environment
   - Staging endpoint for dev (avoids Let's Encrypt rate limits)
   - Production endpoint for prod (trusted certificates)

5. **Secret Management**:
   - Auto-generated secrets via Terraform `random_password` resources
   - Secrets stored in Terraform state (encrypted at rest in Azure Storage)
   - Container Apps secrets injected at runtime (not visible in logs)
   - ACME account keys stored in state (never exposed in logs)

6. **Access Control**:
   - Azure RBAC for resource-level permissions
   - Managed identities for Container Apps (no credentials in code)
   - PostgreSQL accessible only from Container Apps subnet
   - Application Gateway as single ingress point

### Security Scanning

Run Trivy security scan before deployment:

```bash
trivy config terraform/azure/
```

**Expected Results**: 0 HIGH/CRITICAL findings

**Documented Exceptions**:
- `AVD-AZU-0047`: Unrestricted HTTPS inbound (required for public web application)
- `AVD-AZU-0051`: Conditional outbound internet access (required for external API calls)

### Compliance

- **Backup & Recovery**: Automated PostgreSQL backups (7-14 day retention)
- **High Availability**: Zone-redundant deployment in production
- **Monitoring**: Centralized logging via Log Analytics Workspace
- **Audit Trail**: Terraform state changes tracked in Azure Storage with versioning

---

## Additional Resources

- [Navigator Application Repository](https://github.com/canada-ca/navigator/)
- [Reference AWS Implementation](https://github.com/cds-snc/valentine-terraform/)
- [Azure Container Apps Documentation](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Azure PostgreSQL Flexible Server Documentation](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

---

## License

This infrastructure code is maintained as part of the Navigator project. See the [Navigator repository](https://github.com/canada-ca/navigator/) for license information.
