# Navigator Azure Infrastructure Provisioning Guide

**Date**: January 15, 2026 (Updated: January 23, 2026)  
**Branch**: `001-navigator-deploy`  
**Purpose**: Step-by-step guide for provisioning Navigator infrastructure on Azure

---

## Overview

This guide provides instructions for deploying Navigator infrastructure to Azure using Terraform and Terragrunt. The infrastructure follows a configuration-driven environment strategy with shared Terraform modules and environment-specific Terragrunt configurations.

**Prerequisites**: This guide assumes prerequisite infrastructure (resource groups, Terraform state storage) already exists. See plan.md for details.

---

## Prerequisites

### 1. Required Tools

Install the following tools before proceeding:

| Tool           | Minimum Version | Installation                                                              |
| -------------- | --------------- | ------------------------------------------------------------------------- |
| **Terraform**  | 1.9.0+          | https://www.terraform.io/downloads                                        |
| **Terragrunt** | 0.55.0+         | https://terragrunt.gruntwork.io/docs/getting-started/install/             |
| **Azure CLI**  | 2.60.0+         | https://learn.microsoft.com/en-us/cli/azure/install-azure-cli             |
| **Git**        | 2.40.0+         | https://git-scm.com/downloads                                             |
| **Trivy**      | 0.50.0+         | https://aquasecurity.github.io/trivy/latest/getting-started/installation/ |

**Verification**:

```bash
terraform version  # Should show 1.9.0 or higher
terragrunt --version  # Should show 0.55.0 or higher
az version  # Should show 2.60.0 or higher
trivy --version  # Should show 0.50.0 or higher
```

### 2. Azure Subscription and Authentication

**Required**:

- Azure subscription with appropriate permissions
- Contributor role on target resource groups
- Storage Blob Data Contributor role on Terraform state storage accounts

**Authentication Methods**:

**Option 1: Azure CLI (Recommended for local development)**:

```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"
az account show  # Verify correct subscription
```

**Option 2: Service Principal (CI/CD)**:

```bash
export ARM_CLIENT_ID="<CLIENT_ID>"
export ARM_CLIENT_SECRET="<CLIENT_SECRET>"
export ARM_SUBSCRIPTION_ID="<SUBSCRIPTION_ID>"
export ARM_TENANT_ID="<TENANT_ID>"
```

**Option 3: GitHub OIDC (GitHub Actions, no secrets)**:

- Configure federated credentials in Azure AD application
- GitHub Actions workflow uses `azure/login@v1` with OIDC

### 3. Prerequisite Infrastructure

**Verify the following resources exist before proceeding**:

**Resource Groups**:

```bash
az group show --name navigator-dev-rg --query "properties.provisioningState"  # Should return "Succeeded"
az group show --name navigator-prod-rg --query "properties.provisioningState"  # Should return "Succeeded"
```

**Terraform State Storage**:

```bash
# Verify state resource group
az group show --name navigator-tfstate-rg

# Verify state storage accounts
az storage account show --name navtfstatedev --resource-group navigator-tfstate-rg
az storage account show --name navtfstateprod --resource-group navigator-tfstate-rg

# Verify state containers
az storage container show --name tfstate --account-name navtfstatedev
az storage container show --name tfstate --account-name navtfstateprod
```

**RBAC Permissions**:

```bash
# Verify your permissions on state storage
az role assignment list --assignee $(az account show --query user.name -o tsv) --scope /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/navigator-tfstate-rg
# Should show "Storage Blob Data Contributor" or "Storage Blob Data Owner"
```

**If Prerequisites Missing**:

- **Manual Creation**: Create resource groups and state storage manually via Azure Portal or CLI
- **Bootstrap Script**: Run a separate bootstrap Terraform configuration (out of scope for this guide)

### 4. Authentication Secrets (Optional)

**Note**: Authentication is configured via Container Apps environment variables, **NOT** Terraform resources. The Navigator application handles Google OAuth and Microsoft Entra ID natively.

**Prepare authentication credentials** (if using OAuth providers):

**Google OAuth** (optional):
```bash
export TF_VAR_google_client_id="123456789.apps.googleusercontent.com"
export TF_VAR_google_client_secret="GOCSPX-..."
```

**Microsoft Entra ID** (optional):
```bash
export TF_VAR_microsoft_client_id="abcd1234-5678-90ef-ghij-klmnopqrstuv"
export TF_VAR_microsoft_client_secret="secret~..."
export TF_VAR_microsoft_tenant_id="tenant-uuid"
```

**How to obtain credentials**:

- **Google OAuth**: Create OAuth 2.0 credentials in [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
- **Microsoft Entra ID**: Register application in [Azure Portal → Entra ID → App Registrations](https://portal.azure.com/#blade/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/RegisteredApps)

**Minimal deployment** (no authentication): Skip setting `TF_VAR_` variables. Navigator will run without OAuth providers.

---

## Repository Setup

### 1. Clone Repository

```bash
git clone https://github.com/<YOUR_ORG>/navigator-az-terraform.git
cd navigator-az-terraform
```

### 2. Verify Repository Structure

```bash
tree -L 2 terraform/
# Expected structure:
# terraform/
# ├── azure/               # Shared Terraform module
# │   ├── versions.tf
# │   ├── provider.tf
# │   ├── variables.tf
# │   ├── outputs.tf
# │   ├── vnet.tf
# │   ├── container-apps.tf
# │   ├── postgresql.tf
# │   ├── dns.tf
# │   ├── monitoring.tf
# │   ├── identity.tf
# │   └── security.tf
# └── env/
#     ├── dev/
#     │   ├── terragrunt.hcl
#     │   └── Makefile
#     └── production/
#         ├── terragrunt.hcl
#         └── Makefile
```

---

## Development Environment Deployment

### Step 1: Navigate to Environment Directory

```bash
cd terraform/env/dev
```

### Step 2: Initialize Terragrunt

This downloads Terraform providers and configures the backend:

```bash
terragrunt init
```

**Expected Output**:

```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/azurerm versions matching "~> 4.0"...
- Installing hashicorp/azurerm v4.12.0...
Terraform has been successfully initialized!
```

### Step 3: Validate Configuration

Run validation to check syntax and configuration correctness:

```bash
terragrunt validate
```

**Expected Output**:

```
Success! The configuration is valid.
```

### Step 4: Run Security Scan

Scan infrastructure code for security issues with Trivy:

```bash
cd ../../..  # Return to repo root
trivy config terraform/azure/ --severity CRITICAL,HIGH
```

**Expected Findings**:

- AVD-AZU-0047: Unrestricted inbound NSG rule (suppressed, public web app)
- AVD-AZU-0051: Unrestricted outbound NSG rule (suppressed, documented justification)

**Review suppressions** in `terraform/azure/security.tf` and verify business justifications.

### Step 5: Preview Changes

Generate a Terraform plan to review infrastructure changes:

```bash
cd terraform/env/dev
terragrunt plan -out=tfplan
```

**Review Plan Output**:

- **Resources to create**: ~20-25 resources (VNet, subnets, NSGs, Container Apps, PostgreSQL, etc.)
- **Sensitive values**: Database passwords, secret keys (marked as sensitive in plan)
- **Cost estimate** (if using Infracost): ~$27-45/month for dev environment

**Important Checks**:

- ✅ No resources will be destroyed (first deployment)
- ✅ All secrets stored in Container Apps secrets (platform-encrypted)
- ✅ PostgreSQL uses private networking (delegated subnet, no public access)
- ✅ Container Apps uses managed identity for ACR access (if using ACR)

### Step 6: Apply Configuration

Deploy infrastructure to Azure:

**Option 1: Minimal Deployment (No Authentication)**:

```bash
terragrunt apply tfplan
```

**Option 2: Deployment with Google OAuth**:

```bash
export TF_VAR_google_client_id="123456789.apps.googleusercontent.com"
export TF_VAR_google_client_secret="GOCSPX-..."
terragrunt apply tfplan
```

**Option 3: Deployment with Microsoft Entra ID**:

```bash
export TF_VAR_microsoft_client_id="abcd1234-5678-90ef-ghij-klmnopqrstuv"
export TF_VAR_microsoft_client_secret="secret~..."
export TF_VAR_microsoft_tenant_id="tenant-uuid"
terragrunt apply tfplan
```

**Deployment Time**: 10-15 minutes (PostgreSQL and Container Apps Environment are slowest)

**Monitor Progress**:

- Terraform will show resource creation in real-time
- Azure Portal: Monitor resource group `navigator-dev-rg` for resources appearing
- Errors will be displayed in red with error messages

**Common Issues**:

- **Subnet delegation conflict**: Ensure no existing resources in subnet before delegation
- **DNS zone missing**: DNS zones are created by Terraform (unless using default Container Apps domain)

### Step 7: Verify Deployment

After successful deployment, verify resources:

**Container Apps**:

```bash
az containerapp show \
  --name navigator-dev \
  --resource-group navigator-dev-rg \
  --query "properties.configuration.ingress.fqdn" -o tsv
```

**Expected Output**: `navigator-dev.<random>.canadacentral.azurecontainerapps.io`

**PostgreSQL**:

```bash
az postgres flexible-server show \
  --name nav-dev-postgres \
  --resource-group navigator-dev-rg \
  --query "fullyQualifiedDomainName" -o tsv
```

**Expected Output**: `nav-dev-postgres.postgres.database.azure.com`

**Test Application**:

```bash
FQDN=$(az containerapp show --name navigator-dev --resource-group navigator-dev-rg --query "properties.configuration.ingress.fqdn" -o tsv)
curl -I https://$FQDN
```

**Expected Output**: `HTTP/2 200` (or 301/302 if redirecting to login)

### Step 8: Review Outputs

Terragrunt outputs provide important values for application configuration:

```bash
terragrunt output
```

**Key Outputs**:

- `container_app_fqdn`: Public URL for Navigator application
- `container_app_identity_principal_id`: Managed identity ID (for RBAC assignments)
- `postgres_fqdn`: PostgreSQL server FQDN (private, accessible from VNet only)

---

## Production Environment Deployment

**Prerequisites**:

1. ✅ Development environment deployed and tested successfully
2. ✅ Application tested in development (database migrations, authentication, core functionality)
3. ✅ Security review completed (Trivy scan, NSG rules, private networking)
4. ✅ Cost estimate reviewed and approved

### Step 1: Navigate to Production Environment

```bash
cd terraform/env/production
```

### Step 2: Review Production Configuration

**Terragrunt Configuration** (`terragrunt.hcl`):

```hcl
inputs = {
  environment               = "production"
  location                  = "canadacentral"

  # Container Apps
  container_cpu             = 0.5
  container_memory          = "1.0Gi"
  min_replicas              = 1
  max_replicas              = 10

  # PostgreSQL
  postgres_sku              = "GP_Standard_D2s_v3"
  postgres_storage_gb       = 128
  postgres_ha_enabled       = true
  backup_retention_days     = 14

  # Features
  enable_zone_redundancy      = true
  enable_auto_shutdown        = false

  # Domain
  domain_name = "navigator.demo.focisolutions.com"
}
```

**Configuration Differences from Dev**:

- Larger SKUs (more vCPU, memory)
- Zone-redundant high availability enabled
- Longer backup retention (14 days vs 7 days)
- No auto-shutdown (24/7 availability)

**Note**: Application Insights removed from initial scope (future enhancement). Log Analytics provides basic monitoring.

### Step 3: Initialize and Validate

```bash
terragrunt init
terragrunt validate
```

### Step 4: Security Scan (Critical for Production)

```bash
cd ../../..  # Return to repo root
trivy config terraform/azure/ --severity CRITICAL,HIGH,MEDIUM
```

**Review ALL findings** - medium-severity issues acceptable for dev but should be addressed for production.

### Step 5: Generate and Review Plan

```bash
cd terraform/env/production
terragrunt plan -out=tfplan
```

**Production Plan Review Checklist**:

- ✅ PostgreSQL has zone-redundant HA enabled
- ✅ Container Apps min replicas = 1 (always available)
- ✅ Backup retention = 14 days
- ✅ Lifecycle prevent_destroy = true for critical resources
- ✅ Cost estimate reviewed (~$240-350/month)
- ✅ Authentication credentials prepared as TF_VAR_ environment variables (if using OAuth)

### Step 6: Apply with Manual Approval

**CRITICAL**: Production deployments require manual approval.

**GitHub Actions Workflow** (recommended approach):

1. Push to `main` branch triggers plan generation
2. Review plan in GitHub Actions logs
3. Manual approval gate (protected environment)
4. Auto-apply after approval

**Manual Deployment** (if not using GitHub Actions):

```bash
# Set authentication credentials (if using OAuth)
export TF_VAR_microsoft_client_id="..."
export TF_VAR_microsoft_client_secret="..."
export TF_VAR_microsoft_tenant_id="..."

# ONLY run this after thorough plan review
terragrunt apply tfplan
```

**Deployment Time**: 15-20 minutes (zone-redundant PostgreSQL takes longer)

### Step 7: Post-Deployment Verification

**Verify High Availability**:

```bash
az postgres flexible-server show \
  --name nav-prod-postgres \
  --resource-group navigator-prod-rg \
  --query "highAvailability.mode" -o tsv
```

**Expected Output**: `ZoneRedundant`

**Verify Container Apps Replicas**:

```bash
az containerapp revision list \
  --name navigator-prod \
  --resource-group navigator-prod-rg \
  --query "[].{Name:name,Replicas:properties.replicas}" -o table
```

**Expected Output**: At least 1 active replica

**Test Production URL**:

```bash
FQDN=$(az containerapp show --name navigator-prod --resource-group navigator-prod-rg --query "properties.configuration.ingress.fqdn" -o tsv)
curl -I https://$FQDN
```

**Expected Output**: `HTTP/2 200`

---

## Manual Validation Steps

### 1. Application Health Check

**Container Apps Logs**:

```bash
az containerapp logs show \
  --name navigator-dev \
  --resource-group navigator-dev-rg \
  --tail 100
```

**Expected**: Phoenix server startup messages, no errors

### 2. Database Connectivity

**Connect to PostgreSQL** (from VNet-connected machine or bastion):

```bash
psql "host=nav-dev-postgres.postgres.database.azure.com port=5432 dbname=navigator user=navadmin password=<PASSWORD> sslmode=disable"

# Note: Use sslmode=require if postgres_require_ssl variable is set to true
```

**Run Test Query**:

```sql
SELECT version();
-- Expected: PostgreSQL 16.x on x86_64-pc-linux-gnu
```

### 3. Network Connectivity

**Test VNet Integration**:

```bash
# From Container Apps pod (using Azure CLI container exec)
az containerapp exec \
  --name navigator-dev \
  --resource-group navigator-dev-rg \
  --command "/bin/sh"

# Inside container:
ping nav-dev-postgres.postgres.database.azure.com
# Should resolve to private IP (10.240.2.x)
```

### 4. Monitoring and Logs

**Log Analytics Query**:

```bash
az monitor log-analytics query \
  --workspace <WORKSPACE_ID> \
  --analytics-query "ContainerAppConsoleLogs_CL | where TimeGenerated > ago(1h) | project TimeGenerated, Log_s | order by TimeGenerated desc" \
  --out table
```

**Note**: Application Insights removed from initial scope (future enhancement). Use Log Analytics for basic monitoring.

---

## Rollback Procedures

### Rollback Terraform Changes

If a deployment fails or causes issues, rollback to previous state:

**Method 1: Terraform Destroy (Last Resort)**:

```bash
terragrunt destroy  # DANGER: Deletes all resources
```

**Method 2: Revert to Previous Terraform State**:

```bash
# List state versions
az storage blob list \
  --account-name navtfstatedev \
  --container-name tfstate \
  --prefix navigator.terraform.tfstate \
  --query "[].{Name:name,Modified:properties.lastModified}" -o table

# Download previous version
az storage blob download \
  --account-name navtfstatedev \
  --container-name tfstate \
  --name navigator.terraform.tfstate \
  --version-id <VERSION_ID> \
  --file previous-state.tfstate

# Replace current state (DANGEROUS)
az storage blob upload \
  --account-name navtfstatedev \
  --container-name tfstate \
  --name navigator.terraform.tfstate \
  --file previous-state.tfstate \
  --overwrite
```

**Method 3: Revert Code and Re-apply** (Recommended):

```bash
git checkout <PREVIOUS_COMMIT>
cd terraform/env/dev
terragrunt plan  # Review changes
terragrunt apply  # Revert to previous configuration
```

### Rollback Container App Revision

**List Revisions**:

```bash
az containerapp revision list \
  --name navigator-dev \
  --resource-group navigator-dev-rg \
  --query "[].{Name:name,CreatedTime:properties.createdTime,Active:properties.active}" -o table
```

**Activate Previous Revision**:

```bash
az containerapp revision activate \
  --revision <PREVIOUS_REVISION_NAME> \
  --resource-group navigator-dev-rg
```

---

## Troubleshooting

### Common Issues

#### Issue 1: Terraform State Lock

**Symptom**: `Error acquiring the state lock`

**Cause**: Previous Terraform operation did not release lock (interrupted process)

**Solution**:

```bash
# Force unlock (use with caution)
terragrunt force-unlock <LOCK_ID>
```

#### Issue 2: Container App Not Starting

**Symptom**: Container app shows "ProvisioningFailed" or "ContainerCreateFailed"

**Diagnosis**:

```bash
az containerapp logs show \
  --name navigator-dev \
  --resource-group navigator-dev-rg \
  --tail 100
```

**Common Causes**:

- **Missing environment variable**: Check Container Apps secrets configuration
- **Database connectivity**: Verify PostgreSQL network rules, connection string
- **Image pull failure**: Verify ACR permissions or public ECR access

**Solution**:

```bash
# Restart container app
az containerapp revision restart \
  --resource-group navigator-dev-rg \
  --app navigator-dev \
  --revision <REVISION_NAME>
```

#### Issue 3: PostgreSQL Connection Refused

**Symptom**: Application logs show `connection refused` or `timeout`

**Diagnosis**:

```bash
# Verify PostgreSQL is running
az postgres flexible-server show \
  --name nav-dev-postgres \
  --resource-group navigator-dev-rg \
  --query "state" -o tsv
# Expected: "Ready"

# Verify NSG rules allow traffic
az network nsg rule list \
  --nsg-name nsg-container-apps \
  --resource-group navigator-dev-rg \
  --query "[?destinationPortRange=='5432'].{Name:name,Access:access}" -o table
```

**Solution**:

- Verify Container Apps can reach PostgreSQL subnet (10.240.2.0/24)
- Check NSG rules on both Container Apps and PostgreSQL subnets
- Verify connection string (in Container Apps secrets) matches PostgreSQL TLS configuration (`sslmode=disable` by default, or `sslmode=require` if TLS enabled)

#### Issue 4: Trivy Security Scan Failures

**Symptom**: CI/CD pipeline fails on Trivy scan

**Diagnosis**:

```bash
trivy config terraform/azure/ --severity CRITICAL,HIGH
```

**Solution**:

- Review findings and determine if suppression is justified
- Add `#trivy:ignore:<RULE_ID>` with business justification
- Update security controls if finding indicates real vulnerability

---

## Cleanup

### Development Environment Cleanup

**To save costs** when not using development environment:

```bash
cd terraform/env/dev
terragrunt destroy
```

**Confirmation Required**: Type `yes` when prompted

**Resources Deleted**:

- Container Apps Environment and Navigator app
- PostgreSQL Flexible Server (⚠️ data loss)
- VNet and subnets
- NSGs and diagnostic settings

**Preserved**:

- Resource group (if `prevent_deletion_if_contains_resources = false`)
- Terraform state file (in Azure Blob Storage)

### Production Environment Cleanup

**WARNING**: Production destruction is **PROTECTED** by Terraform lifecycle rules.

**Prerequisites**:

1. Remove lifecycle `prevent_destroy = true` from critical resources
2. Manual approval from operations team
3. Backup verification (PostgreSQL restore tested)

```bash
cd terraform/env/production
terragrunt destroy
```

---

## Next Steps

After successful deployment:

1. **Configure Custom Domain** (optional):

   - Update DNS A record to point to Container Apps FQDN
   - Configure custom domain in Container Apps
   - Verify managed certificate provisioning

2. **Set Up Monitoring Alerts**:

   - CPU/memory utilization alerts
   - Failed request alerts
   - Database connection failures

3. **Configure CI/CD**:

   - GitHub Actions workflow for automated deployments
   - OIDC authentication for GitHub Actions
   - Environment protection rules

4. **Database Migrations**:

   - Run Phoenix database migrations
   - Seed initial data (if applicable)

5. **Load Testing**:
   - Test with 50-100 concurrent users
   - Monitor performance metrics
   - Adjust auto-scaling rules if needed

---

**Document Version**: 1.2.0  
**Last Updated**: January 21, 2026  
**Related Documents**: plan.md, architecture.md, research.md

**Changelog**:

- v1.2.0 (2026-01-21): Removed Azure Key Vault completely - using Container Apps secrets exclusively
- v1.1.0 (2026-01-20): Updated Key Vault references to reflect optional configuration, added use_key_vault variable documentation
- v1.0.0 (2026-01-15): Initial provisioning guide
