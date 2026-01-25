# Navigator Azure Infrastructure

This repository contains Terraform infrastructure-as-code (IaC) for deploying the [Navigator](https://github.com/canada-ca/navigator/) threat modeling application to Microsoft Azure.

Navigator is an Elixir/Phoenix web application providing real-time threat modeling capabilities with collaborative features.

---

## 🏗️ Architecture Overview

### Azure Services Deployed

- **Azure Container Apps**: Serverless container runtime for Navigator application
  - VNet-integrated with private subnet
  - Session affinity enabled for Phoenix LiveView WebSocket support
  - Auto-scaling based on HTTP requests (dev) or CPU utilization (production)
  - Health probes for startup and liveness monitoring

- **Azure Database for PostgreSQL Flexible Server**: Managed PostgreSQL database
  - Private VNet integration with delegated subnet
  - Zone-redundant high availability (production only)
  - Automated backups with configurable retention
  - Private DNS zone for secure connectivity

- **Azure Virtual Network**: Network isolation and security
  - 3 subnets: Container Apps, PostgreSQL, Application Gateway (reserved)
  - Network Security Groups (NSGs) for traffic control
  - Service Endpoints for secure Azure service access
  - Optional NAT Gateway for static outbound IP (zone-redundant environments)

- **Azure DNS Zone** (optional): Custom domain support
  - Managed DNS zone for custom domains
  - Automatic SSL certificate provisioning via Azure Managed Certificates
  - A records pointing to Container Apps ingress

- **Log Analytics Workspace**: Centralized logging and monitoring
  - Container Apps logs and metrics
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

## ✅ Prerequisites

### Required Azure Resources (Must Exist Before Deployment)

These resources must be created manually before running Terraform:

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

## 📁 Repository Structure

```
navigator-az-terraform/
├── terraform/
│   ├── azure/                    # Shared Terraform module (infrastructure code)
│   │   ├── versions.tf           # Provider version constraints
│   │   ├── provider.tf           # Azure provider configuration
│   │   ├── variables.tf          # Input variable definitions
│   │   ├── outputs.tf            # Infrastructure outputs
│   │   ├── vnet.tf               # Virtual Network, subnets, NAT Gateway
│   │   ├── security.tf           # Network Security Groups (NSGs)
│   │   ├── dns-private.tf        # Private DNS zones for PostgreSQL
│   │   ├── dns.tf                # Public DNS zone and custom domain (optional)
│   │   ├── postgresql.tf         # PostgreSQL Flexible Server + database
│   │   ├── secrets.tf            # Random passwords for PostgreSQL, Phoenix
│   │   ├── container-apps.tf     # Container Apps Environment + Navigator app
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

## 🚀 Deployment Strategy

### Environment Promotion Workflow

1. **Development First**: Always validate changes in the `dev` environment before production
2. **Configuration-Driven**: Environment differences managed via Terragrunt inputs (no code changes)
3. **Manual Deployment**: Explicit approval required for each deployment (no automation)
4. **Sequential Promotion**: `dev` → testing/validation → `production`

### Resource Naming Convention

Pattern: `{project}-{env}-{descriptor}-{type}[-{instance}]`

Examples:
- `nav-dev-vnet` (Virtual Network)
- `nav-dev-ca-001` (Container App instance)
- `nav-dev-psql` (PostgreSQL Flexible Server)
- `nav-dev-kv-1a2b3c4d` (Key Vault with uniqueness hash)
- `navdevst1a2b3c4d` (Storage Account - no hyphens, includes hash)

---

## 📦 Manual Deployment Steps

### Initial Deployment

#### Important Note: Custom Domain Deployment

**If deploying with a custom domain** (`domain_name` variable set):

The **first `terraform apply` will fail** during custom domain binding. This is expected. Follow this workflow:

1. **Run initial deployment:**
   ```bash
   terragrunt apply
   ```
   This creates the DNS zone but fails at custom domain binding.

2. **Configure NS records at your domain registrar:**
   ```bash
   # Retrieve Azure DNS name servers
   terragrunt output dns_zone_nameservers
   ```
   Update your domain registrar's NS records with these 4 Azure DNS name servers.

3. **Wait for DNS propagation** (15 minutes to 48 hours). Verify with:
   ```bash
   dig NS navigator-dev.demo.focisolutions.com
   ```

4. **Re-run deployment:**
   ```bash
   terragrunt apply
   ```
   This completes the certificate creation and HTTPS binding.

**Without a custom domain**, deployment succeeds on first apply.

### Incremental Updates

```bash
cd terraform/env/{dev|production}

# Review changes before applying
terragrunt plan

# Apply only if changes are expected and reviewed
terragrunt apply
```

### Destroying Infrastructure

⚠️ **WARNING**: This will permanently delete all resources and data.

```bash
cd terraform/env/{dev|production}

# Review resources to be destroyed
terragrunt plan -destroy

# Destroy infrastructure (requires manual confirmation)
terragrunt destroy
```

---

## ⚙️ Post-Deployment Configuration

### 1. DNS Name Server Configuration

**⚠️ REQUIRED during initial deployment if using custom domain** (`domain_name` variable set):

#### First Apply (Will Fail - Expected)

```bash
cd terraform/env/{dev|production}
terragrunt apply  # Creates DNS zone, fails at custom domain binding
```

#### Configure Name Servers

1. **Retrieve Azure DNS name servers:**
   ```bash
   terragrunt output dns_zone_nameservers
   ```

2. **Update NS records at your domain registrar** with the 4 Azure DNS name servers from output above.

3. **Wait for DNS propagation** (15 minutes to 48 hours). Verify:
   ```bash
   dig NS navigator-dev.demo.focisolutions.com
   # Should return Azure DNS name servers
   ```

#### Second Apply (Will Succeed)

Once DNS propagates, re-run deployment:

```bash
terragrunt apply  # Completes domain verification, certificate creation, HTTPS binding
```

Verify HTTPS access:
```bash
curl -I https://navigator-dev.demo.focisolutions.com  # Should show 200 OK with valid SSL
```

### 2. Authentication Provider Configuration (Optional)

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

### 3. Azure Defender for Cloud (Optional)

Enable Azure Defender for enhanced security monitoring:

1. Navigate to **Azure Security Center** > **Pricing & Settings**
2. Select your subscription
3. Enable **Enhanced Security** for:
   - Container Apps
   - PostgreSQL databases
   - Storage accounts (if created)
4. Configure alert notifications and policies as needed

---

## 🔧 Environment Configuration

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

## 📤 Outputs

### Key Infrastructure Outputs

After deployment, retrieve outputs with:

```bash
cd terraform/env/{dev|production}
terragrunt output
```

**Available Outputs**:

- `container_apps_url`: Full HTTPS URL of the Navigator application
- `container_apps_fqdn`: FQDN of the Container App ingress
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

## 🔒 Security & Compliance

### Security Features

1. **Network Isolation**:
   - Private VNet integration for all compute and data resources
   - Network Security Groups (NSGs) with least-privilege rules
   - Private DNS zones for internal name resolution
   - Service Endpoints for secure Azure service access

2. **Data Encryption**:
   - Encryption at rest for PostgreSQL (Azure-managed keys)
   - TLS encryption for data in transit (PostgreSQL, Container Apps)
   - Container Apps secrets encrypted by Azure platform

3. **Secret Management**:
   - Auto-generated secrets via Terraform `random_password` resources
   - Secrets stored in Terraform state (encrypted at rest in Azure Storage)
   - Container Apps secrets injected at runtime (not visible in logs)

4. **Access Control**:
   - Azure RBAC for resource-level permissions
   - Managed identities for Container Apps (no credentials in code)
   - PostgreSQL accessible only from Container Apps subnet

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

## 📚 Additional Resources

- [Navigator Application Repository](https://github.com/canada-ca/navigator/)
- [Reference AWS Implementation](https://github.com/cds-snc/valentine-terraform/)
- [Azure Container Apps Documentation](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Azure PostgreSQL Flexible Server Documentation](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

---

## 🆘 Troubleshooting

### Common Issues

**Issue**: `terragrunt plan` fails with authentication error

**Solution**: Ensure you're authenticated to Azure:
```bash
az login --scope https://management.azure.com//.default
az account show  # Verify correct subscription
```

---

**Issue**: DNS resolution fails after deployment

**Solution**:
1. Verify NS records at domain registrar match Azure DNS name servers
2. Wait for DNS propagation (24-48 hours)
3. Use `nslookup` or `dig` to verify DNS resolution

---

**Issue**: Container App fails health checks

**Solution**:
1. Check Container Apps logs in Azure Portal or via Azure CLI:
   ```bash
   az containerapp logs show --name nav-{env}-ca-001 --resource-group navigator-{env}-rg
   ```
2. Verify PostgreSQL connectivity from Container Apps subnet
3. Check environment variable configuration (PHX_HOST, DATABASE_URL, SECRET_KEY_BASE)

---

## 📝 License

This infrastructure code is maintained as part of the Navigator project. See the [Navigator repository](https://github.com/canada-ca/navigator/) for license information.
