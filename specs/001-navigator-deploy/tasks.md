# Tasks: Navigator Azure Deployment

**Input**: Design documents from `/specs/001-navigator-deploy/`
**Prerequisites**: plan.md (required), spec.md (required)

**Organization**: Tasks grouped by infrastructure tier following dependency hierarchy (Setup → Network → Compute/Data → Application → Polish)

## Format: `[ID] [P?] Description`

- **[ID]**: Sequential task number (T001, T002, T003...)
- **[P]**: Can run in parallel (different files, no dependencies) - optional
- **Description**: Clear action with exact file path included

Tasks are organized by infrastructure tier in the phase structure below

## Path Conventions

- **Terraform shared module**: `terraform/azure/` at repository root
- **Terragrunt environment configs**: `terraform/env/{dev,production}/`
- **Main Terraform files**: `terraform/azure/*.tf`

## Phase 1: Setup

**Purpose**: Terragrunt and Terraform project initialization, directory structure, version constraints

- [X] T001 Create terraform/ directory structure with azure/ and env/ subdirectories
- [X] T002 Create terraform/env/dev/ and terraform/env/production/ directories
- [X] T003 [P] Create terraform/azure/versions.tf with Terraform >= 1.9 and azurerm ~> 4.0 constraints
- [X] T004 [P] Create terraform/azure/provider.tf with Azure provider configuration and features block
- [X] T005 [P] Create terraform/azure/variables.tf with all configurable input variables (environment, region, SKUs, scaling, feature flags, enable_outbound_internet)
- [X] T006 [P] Create terraform/azure/outputs.tf with key infrastructure outputs (Container Apps URL, PostgreSQL FQDN, Key Vault URI)
- [X] T007 [P] Create terraform/env/dev/terragrunt.hcl with dev environment configuration (source = "../..//azure", inputs for dev SKUs)
- [X] T008 [P] Create terraform/env/production/terragrunt.hcl with production environment configuration (inputs for production SKUs, HA enabled)
- [X] T009 [P] Create terraform/env/dev/Makefile with dev deployment shortcuts (init, plan, apply)
- [X] T010 [P] Create terraform/env/production/Makefile with production deployment shortcuts
- [X] T011 Run `cd terraform/env/dev && terragrunt init` to initialize backend and download providers (requires Azure authentication: `az login --scope https://management.azure.com//.default` and RBAC roles: Contributor on resource groups, Storage Blob Data Contributor on state storage - see spec.md Dependencies)
- [X] T012 Run `cd terraform/env/dev && terragrunt validate` - setup checkpoint (requires T011 to complete first)

---

## Phase 2: Network Tier

**Purpose**: Virtual network, subnets, NSGs, and network security - prerequisite for all compute/data resources

**⚠️ CRITICAL**: Network tier MUST complete before compute resources can be provisioned

- [X] T013 Create terraform/azure/vnet.tf with Virtual Network (10.240.0.0/16, Canada Central)
- [X] T014 Create Container Apps subnet (10.240.1.0/24) delegated to Microsoft.App/environments in terraform/azure/vnet.tf
- [X] T015 Create PostgreSQL subnet (10.240.2.0/24) delegated to Microsoft.DBforPostgreSQL/flexibleServers in terraform/azure/vnet.tf
- [X] T016 Create Application Gateway subnet (10.240.3.0/24) for future use in terraform/azure/vnet.tf
- [X] T017 [P] Configure Service Endpoints (Microsoft.Storage, Microsoft.KeyVault) on subnets in terraform/azure/vnet.tf
- [X] T018 Create terraform/azure/security.tf with Container Apps NSG (inbound 443 from internet with trivy:ignore, outbound split: Azure service tags + conditional internet with trivy:ignore, documentation comment block)
- [X] T019 Create PostgreSQL NSG (inbound 5432 from Container Apps subnet only) in terraform/azure/security.tf
- [X] T020 Associate NSGs with respective subnets in terraform/azure/security.tf
- [X] T021 [P] Create terraform/azure/identity.tf for Managed Identities configuration structure
- [X] T022 [P] Create IAM access groups and initial RBAC role assignments skeleton in terraform/azure/identity.tf
- [X] T023 Run `cd terraform/env/dev && terragrunt validate` - network tier checkpoint

**Checkpoint**: Network tier complete - compute and data resources can now be provisioned

---

## Phase 3: Compute & Data Tier

**Purpose**: Container Apps, PostgreSQL database, storage, and Key Vault

**Dependencies**: Requires Network Tier (Phase 2) to be complete

- [X] T024 Create terraform/azure/keyvault.tf with Azure Key Vault (Standard SKU for dev, soft delete enabled)
- [X] T025 [P] Configure Key Vault RBAC access policy in terraform/azure/keyvault.tf
- [X] T026 [P] Create azurerm_key_vault_secret resources for PostgreSQL admin password placeholder in terraform/azure/keyvault.tf (Note: Database connection string secret created in postgresql.tf to avoid duplication)
- [X] T027 [P] Create azurerm_key_vault_secret for Phoenix SECRET_KEY_BASE placeholder in terraform/azure/keyvault.tf
- [X] T028 [P] Create azurerm_key_vault_secret for OpenAI/Azure OpenAI API key placeholder in terraform/azure/keyvault.tf
- [X] T028b [P] Create azurerm_cognitive_account for Azure OpenAI (conditional on var.create_azure_openai) in terraform/azure/auth-openai.tf
- [X] T029 [P] Configure Key Vault private endpoint (conditional on var.enable_private_endpoints) in terraform/azure/keyvault.tf
- [X] T030 Create terraform/azure/postgresql.tf with Azure Database for PostgreSQL Flexible Server
- [X] T031 Configure PostgreSQL SKU (Burstable B1ms for dev, General Purpose D2s_v3 for production) in terraform/azure/postgresql.tf
- [X] T032 Configure PostgreSQL storage (32GB dev, 128GB production, auto-grow enabled) in terraform/azure/postgresql.tf
- [X] T033 Configure PostgreSQL HA (disabled for dev, zone-redundant for production with var.postgres_ha_enabled) in terraform/azure/postgresql.tf
- [X] T034 Configure PostgreSQL backup (7-14 day retention based on var.backup_retention_days) in terraform/azure/postgresql.tf
- [X] T035 Configure PostgreSQL private endpoint in VNet (PostgreSQL subnet) in terraform/azure/postgresql.tf
- [X] T036 Configure PostgreSQL SSL/TLS enforcement (TLS 1.2+) in terraform/azure/postgresql.tf
- [X] T037 Store PostgreSQL connection string in Key Vault using azurerm_key_vault_secret in terraform/azure/postgresql.tf
- [X] T038 Create terraform/azure/container-apps.tf with Azure Container Apps Environment
- [X] T039 Configure Container Apps Environment with VNet integration (Container Apps subnet) in terraform/azure/container-apps.tf
- [X] T040 Create Log Analytics Workspace for Container Apps logging in terraform/azure/container-apps.tf
- [X] T041 Create Navigator Container App (image: public.ecr.aws/cds-snc/valentine:latest) in terraform/azure/container-apps.tf
- [X] T042 Configure container resources (0.25 vCPU/0.5GB for dev, 0.5 vCPU/1.0GB for production) in terraform/azure/container-apps.tf
- [X] T043 Configure scaling (min 0/max 2 for dev, min 1/max 10 for production) in terraform/azure/container-apps.tf
- [X] T044 Configure Container Apps ingress (HTTPS only, external, port 4000) in terraform/azure/container-apps.tf
- [X] T045 Configure health probes (HTTP liveness on "/" endpoint) in terraform/azure/container-apps.tf
- [X] T046 Create system-assigned managed identity for Container App in terraform/azure/container-apps.tf
- [X] T047 Grant Container App managed identity Key Vault Secrets User role in terraform/azure/identity.tf
- [X] T048 Configure container environment variables with Key Vault secret references in terraform/azure/container-apps.tf
- [X] T049 [REMOVED] Not required - environment variables defined in HCL in T048, no external template needed
- [X] T050 [P] Create terraform/azure/storage.tf with Azure Storage Account (conditional on var.create_storage_account)
- [X] T051 [P] Configure Storage Account SKU (Standard LRS for dev, Standard ZRS for production) in terraform/azure/storage.tf
- [X] T052 [P] Create blob container for user uploads in terraform/azure/storage.tf
- [X] T053 [P] Configure storage lifecycle management (Move to Cool tier after 90 days, Archive tier after 180 days for long-term retention) in terraform/azure/storage.tf
- [X] T054 [P] Configure storage private endpoint (conditional, production) in terraform/azure/storage.tf
- [X] T055 Run `cd terraform/env/production && terragrunt validate` - compute/data tier checkpoint
- [X] T056 Run `cd terraform/env/production && terragrunt plan` to preview infrastructure changes

**Checkpoint**: Compute and data tier complete - application tier can now be configured

**Post-Deployment Secret Population**: Tasks T026-T028 create placeholder secrets in Key Vault. Actual secret values must be populated manually or via CI/CD before application deployment:
- PostgreSQL credentials: Generated during database creation, store in secrets management service
- SECRET_KEY_BASE: Generate using `openssl rand -base64 64` (see spec.md Notes)
- OpenAI/Azure OpenAI API key: Obtain from provider, store in secrets management service
- Implement rotation policy per GC Patch Management Guidance (see principles.md Governance)

---

## Phase 4: Application Tier

**Purpose**: DNS, monitoring, alerting, and authentication configuration

**Dependencies**: Requires Compute & Data Tier (Phase 3) to be complete

- [ ] T057 Create terraform/azure/dns.tf with Azure DNS zone (navigator-dev.cdssandbox.xyz for dev, valentine.cds-snc.ca for production)
- [ ] T058 Create A record pointing to Container Apps environment default domain in terraform/azure/dns.tf
- [ ] T059 Configure Container Apps Managed Certificate for custom domain (baseline) in terraform/azure/dns.tf
- [ ] T060 Configure DNS validation for certificate issuance in terraform/azure/dns.tf
- [ ] T061 [P] Create terraform/azure/monitoring.tf with Application Insights (conditional on var.enable_application_insights)
- [ ] T062 [P] Configure Application Insights connection to Container Apps in terraform/azure/monitoring.tf
- [ ] T063 [P] Create monitoring dashboards for key metrics (CPU, memory, request count) in terraform/azure/monitoring.tf
- [ ] T064 [P] Create terraform/azure/alerts.tf with alerting policies (high CPU, database connection failures)
- [ ] T065 [P] Configure alert notification channels (email, webhook) in terraform/azure/alerts.tf
- [ ] T066 [P] Create terraform/azure/auth-b2c.tf for Azure AD B2C configuration (conditional on var.create_azure_ad_b2c)
- [ ] T067 [P] Create terraform/azure/auth-google.tf for Google OAuth configuration (conditional on var.create_google_auth)
- [ ] T068 [P] Store OAuth credentials in Key Vault using azurerm_key_vault_secret in terraform/azure/auth-google.tf
- [ ] T069 Create terraform/azure/gh-oidc.tf with GitHub OIDC federated credentials for CI/CD
- [ ] T070 Configure service principal with least-privilege RBAC (Contributor on Container App, read-only Key Vault) in terraform/azure/gh-oidc.tf
- [ ] T071 [P] Configure NAT Gateway for outbound connectivity (conditional, production) in terraform/azure/vnet.tf
- [ ] T072 Run `cd terraform/env/dev && terragrunt validate` - application tier checkpoint
- [ ] T073 Run `cd terraform/env/dev && terragrunt plan` to preview application tier changes

**Checkpoint**: Application tier complete - infrastructure ready for polish and final validation

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Final validation, formatting, documentation, security scanning, and deployment readiness

- [ ] T074 Run `terraform fmt -recursive` in terraform/azure/ to format all .tf files
- [ ] T075 Run `cd terraform/env/dev && terragrunt validate` to validate all dev configurations
- [ ] T076 Run `cd terraform/env/production && terragrunt validate` to validate production configurations
- [ ] T077 [P] Run Trivy security scan on Terraform code: `trivy config terraform/azure/`
- [ ] T078 [P] Review Trivy findings and remediate or document HIGH/CRITICAL issues: fix configuration errors (missing encryption, exposed storage) or add trivy:ignore comments with business justification for intentional design (public HTTPS ingress, conditional outbound internet - see plan.md Security Compliance)
- [ ] T079 [P] Add comprehensive resource tags (Environment, CostCenter=navigator, Project=valentine) to all resources in terraform/azure/*.tf
- [ ] T080 [P] Update terraform/azure/outputs.tf with all key infrastructure values (Container Apps FQDN, PostgreSQL FQDN, Key Vault URI, DNS zone name)
- [ ] T081 [P] Add output descriptions and sensitive markers where appropriate in terraform/azure/outputs.tf
- [ ] T082 Create terraform/azure/README.md with module documentation (variables, outputs, usage examples)
- [ ] T083 Create terraform/env/dev/README.md with dev environment deployment instructions
- [ ] T084 Create terraform/env/production/README.md with production deployment guide and approval requirements
- [ ] T085 [P] Create .gitignore entries for Terraform state, .tfvars, .terraform/, terragrunt cache
- [ ] T086 [P] Document prerequisite infrastructure requirements (resource groups, state storage) in root README.md
- [ ] T087 Run `cd terraform/env/dev && terragrunt plan -out=dev.tfplan` to generate final dev plan
- [ ] T088 Verify dev plan shows expected resources (VNet, Container Apps, PostgreSQL, Key Vault, DNS)
- [ ] T089 [P] Create .github/workflows/terraform-plan.yml for PR plan automation
- [ ] T090 [P] Create .github/workflows/terraform-apply-dev.yml for auto-deploy dev on merge
- [ ] T091 [P] Create .github/workflows/terraform-apply-prod.yml for manual production deployment
- [ ] T092 Document deployment strategy (dev → validate → production) in root README.md
- [ ] T093 Final validation: Run `cd terraform/env/production && terragrunt validate` and confirm no errors

---

## Dependencies & Execution Order

### Phase Dependencies

1. **Phase 1: Setup** - No dependencies, can start immediately
2. **Phase 2: Network Tier** - Depends on Setup - BLOCKS all compute/data resources
3. **Phase 3: Compute & Data Tier** - Depends on Network Tier being complete
4. **Phase 4: Application Tier** - Depends on Compute & Data Tier being complete
5. **Phase 5: Polish** - Depends on all infrastructure tiers being complete

### Infrastructure Task Sequencing Rules

**Critical Dependencies:**
- Network resources (VNet, subnets, NSGs) MUST complete before compute resources (Container Apps, PostgreSQL)
- Security groups MUST be defined before resources that reference them
- Managed identities MUST exist before RBAC role assignments
- Key Vault MUST exist before storing secrets
- Container Apps Environment MUST exist before Container Apps
- PostgreSQL MUST exist before connection string stored in Key Vault

**Validation Checkpoints:**
- Run `terragrunt validate` after each tier completes
- Run `terragrunt plan` before marking tier complete
- Formatting checks (`terraform fmt`) in Polish phase
- Security scanning (Trivy) in Polish phase

### Parallel Opportunities

**Within Same Tier:**
- Network tier: Subnets, NSGs, Service Endpoints (different resources, different files)
- Compute tier: Key Vault secrets, Storage Account (independent resources)
- Application tier: Monitoring, DNS, Authentication configs (different files, no dependencies)
- Polish phase: Documentation tasks, security scanning, GitHub Actions workflows

**Across Environments:**
- Dev and production environments can be validated in parallel during Polish phase
- Each environment follows same tier dependencies independently

### When Tasks CANNOT Be Parallel

**CRITICAL: Tasks CANNOT run in parallel when:**

1. **Same File Modification**:
   - ❌ Two tasks both modifying `terraform/azure/vnet.tf`
   - ✅ One task on `terraform/azure/vnet.tf`, another on `terraform/azure/security.tf`

2. **Resource Dependencies**:
   - ❌ Creating Container Apps BEFORE Container Apps Environment exists
   - ❌ Creating Container App BEFORE VNet/subnet exists
   - ❌ Storing database connection string in Key Vault BEFORE PostgreSQL is created
   - ❌ Assigning RBAC roles BEFORE managed identities exist
   - ✅ Creating multiple independent Key Vault secrets (if parent vault exists)

3. **Cross-Tier Dependencies**:
   - ❌ Any Compute/Data tier task running before Network tier completes
   - ❌ Application tier DNS configuration before Container Apps exist
   - ❌ Monitoring configuration before resources to monitor exist
   - ✅ Within Network tier: NSGs, subnets (if in different files)

4. **Sequential Configuration**:
   - ❌ Configuring PostgreSQL backup BEFORE PostgreSQL resource defined
   - ❌ Referencing Key Vault secrets in Container Apps BEFORE secrets exist
   - ❌ Creating private endpoints BEFORE parent resources exist
   - ✅ Creating multiple subnets in parallel (if VNet already defined in same file)

5. **Validation Checkpoints**:
   - ❌ Starting next tier BEFORE validation checkpoint passes
   - ❌ Running `terragrunt plan` BEFORE all tier resources defined
   - ✅ Running validation commands in sequence at tier boundaries

**Azure-Specific Dependency Examples:**

- **VNet → Subnets → Resources**: VNet defined, then subnets, then Container Apps/PostgreSQL reference subnets
- **NSGs → Subnet Association**: Define NSGs before associating with subnets
- **Managed Identity → RBAC**: Create managed identity before assigning roles
- **Key Vault → Secrets**: Create Key Vault before storing secrets
- **Container Apps Environment → Container App**: Environment must exist before apps
- **PostgreSQL → Connection String Storage**: Database must exist before connection string generated
- **Network → Private Endpoints**: Network infrastructure before private endpoint creation

**Rule of Thumb**: If task B needs output/ID from task A, they CANNOT be parallel. Mark task B without [P] and ensure it comes after task A in the sequence.

---

## Implementation Strategy

### Tier-by-Tier Code Generation

1. Complete Phase 1: Setup (create versions.tf, provider.tf, variables.tf, terragrunt.hcl files)
2. Complete Phase 2: Network Tier (create vnet.tf, security.tf, identity.tf skeleton)
3. **VALIDATE**: Run `terragrunt validate` to verify configuration syntax
4. Complete Phase 3: Compute & Data Tier (create container-apps.tf, postgresql.tf, keyvault.tf, storage.tf)
5. **VALIDATE**: Run `terragrunt validate` after compute tier
6. Complete Phase 4: Application Tier (create dns.tf, monitoring.tf, auth-*.tf, gh-oidc.tf)
7. **VALIDATE**: Run `terragrunt validate` after application tier
8. Complete Phase 5: Polish (formatting, documentation, security scanning, final validation)
9. Final validation with `terragrunt validate` and `terragrunt plan`

**Note**: Implementation generates IaC code files only. Actual infrastructure deployment (terragrunt apply) is outside the scope of this task framework.

### Parallel Code Generation

When multiple team members work on IaC code:

1. Complete Setup + Network together (foundation files)
2. Once Network tier files complete, parallelize within tiers:
   - Team member A: Container Apps infrastructure (container-apps.tf)
   - Team member B: Database and Key Vault (postgresql.tf, keyvault.tf)
   - Team member C: Storage and identity (storage.tf, identity.tf)
3. Validate at tier boundaries before proceeding to next tier
4. Application tier can be parallelized across DNS, monitoring, authentication

---

## Environment Promotion Strategy

### Configuration Differences (Terragrunt inputs)

**Development Environment** (`terraform/env/dev/terragrunt.hcl`):
- `container_cpu = 0.25`, `container_memory = "0.5Gi"`
- `min_replicas = 0` (scale to zero), `max_replicas = 2`
- `postgres_sku = "B_Standard_B1ms"`, `postgres_storage_gb = 32`
- `postgres_ha_enabled = false`
- `backup_retention_days = 7`
- `enable_application_insights = false`
- `enable_auto_shutdown = true`
- `enable_zone_redundancy = false`
- `domain_name = "navigator-dev.cdssandbox.xyz"`
- `create_google_auth = false`
- `create_azure_ad_b2c = true`

**Production Environment** (`terraform/env/production/terragrunt.hcl`):
- `container_cpu = 0.5`, `container_memory = "1.0Gi"`
- `min_replicas = 1`, `max_replicas = 10`
- `postgres_sku = "GP_Standard_D2s_v3"`, `postgres_storage_gb = 128`
- `postgres_ha_enabled = true` (zone-redundant)
- `backup_retention_days = 14`
- `enable_application_insights = true`
- `enable_auto_shutdown = false`
- `enable_zone_redundancy = true`
- `domain_name = "valentine.cds-snc.ca"`
- `create_google_auth = true`
- `create_azure_ad_b2c = false`

### Deployment Workflow

1. Validate changes in dev environment first (`terragrunt plan`, apply, manual testing)
2. Promote configuration to production (review Terragrunt inputs, adjust SKUs/HA settings)
3. Deploy to production (manual approval gate in GitHub Actions)
4. Resource naming convention: Environment prefixes (`nav-dev-*`, `nav-prod-*`)
5. GitHub Actions workflows:
   - Dev: Auto-deploy on merge to main branch (OIDC authentication)
   - Production: Deploy only on release publication (manual trigger, require approval)

---

## Notes

- [P] tasks = different files, no dependencies within same tier
- Tasks organized by infrastructure tier following dependency hierarchy
- Run `terragrunt validate` at tier boundaries to catch syntax errors early
- Run `terragrunt plan` before marking major tiers complete
- Commit after each tier or logical group of resources
- Stop at checkpoints to validate configuration
- Avoid: vague tasks, same file conflicts, violating tier dependencies
- All paths relative to repository root
- Terragrunt orchestration enables configuration-driven environment promotion
- No infrastructure code changes required to promote dev → production (configuration-only differences)

---

## Task Summary

**Total Tasks**: 94

**Task Count by Phase**:
- Phase 1 (Setup): 12 tasks
- Phase 2 (Network Tier): 11 tasks
- Phase 3 (Compute & Data Tier): 34 tasks
- Phase 4 (Application Tier): 17 tasks
- Phase 5 (Polish): 20 tasks

**Parallel Opportunities Identified**: 38 tasks marked [P] can run in parallel within their respective phases

**Validation Checkpoints**: 7 checkpoints (Setup, Network, Compute/Data, Application, and 3 in Polish)

**Environment Order**: dev → production (configuration-driven promotion via Terragrunt)

**Format Validation**: ✅ All tasks follow checklist format (checkbox, ID, labels, file paths)
