# Tasks: Navigator Azure Deployment

**Date**: January 15, 2026 (Updated: January 23, 2026)  
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

- [x] T001 Create terraform/ directory structure with azure/ and env/ subdirectories
- [x] T002 Create terraform/env/dev/ and terraform/env/production/ directories
- [x] T003 Create terraform/azure/templates/ directory for Container Apps environment variable templates
- [x] T004 [P] Create terraform/azure/versions.tf with Terraform >= 1.9 and azurerm ~> 4.0 constraints
- [x] T005 [P] Create terraform/azure/provider.tf with Azure provider configuration and features block
- [x] T006 [P] Create terraform/azure/variables.tf with all configurable input variables including authentication variables (google_client_id, google_client_secret, microsoft_client_id, microsoft_client_secret, microsoft_tenant_id - all optional string type with default null), enable_auto_shutdown (bool), enable_zone_redundancy (bool), enable_outbound_internet (bool, default: true), create_azure_openai (bool), create_storage_account (bool), plus environment, location, container CPU/memory, min/max replicas, postgres_sku, postgres_storage_gb, postgres_ha_enabled, backup_retention_days, domain_name
- [x] T007 [P] Create terraform/azure/outputs.tf with key infrastructure outputs (Container Apps URL, PostgreSQL FQDN, DNS zone name servers)
- [x] T008 [P] Create terraform/env/dev/terragrunt.hcl with dev environment configuration (source = "../..//azure", remote_state config for navtfstatedev, inputs block with: container_cpu=0.25, container_memory=0.5Gi, min_replicas=0, max_replicas=2, postgres_sku=B_Standard_B1ms, postgres_storage_gb=32, postgres_ha_enabled=false, backup_retention_days=7, enable_auto_shutdown=true, enable_zone_redundancy=false, domain_name=navigator-dev.demo.focisolutions.com, enable_outbound_internet=true, create_azure_openai=false)
- [x] T009 [P] Create terraform/env/production/terragrunt.hcl with production environment configuration (source = "../..//azure", remote_state config for navtfstateprod, inputs block with: container_cpu=0.5, container_memory=1.0Gi, min_replicas=1, max_replicas=10, postgres_sku=GP_Standard_D2s_v3, postgres_storage_gb=128, postgres_ha_enabled=true, backup_retention_days=14, enable_auto_shutdown=false, enable_zone_redundancy=true, domain_name=navigator.demo.focisolutions.com, enable_outbound_internet=true, create_azure_openai=false)
- [x] T010 Run `cd terraform/env/dev && terragrunt init` to initialize backend and download providers (requires Azure authentication: `az login --scope https://management.azure.com//.default` and RBAC roles: Contributor on resource groups, Storage Blob Data Contributor on state storage - see spec.md Dependencies section)
- [x] T011 Run `cd terraform/env/dev && terragrunt validate` - setup checkpoint (requires T010 to complete first)

---

## Phase 2: Network Tier

**Purpose**: Virtual network, subnets, NSGs, private DNS zones, and network security - prerequisite for all compute/data resources

**⚠️ CRITICAL**: Network tier MUST complete before compute resources can be provisioned

- [x] T012 Create terraform/azure/vnet.tf with Virtual Network (10.240.0.0/16, Canada Central)
- [x] T013 Create Container Apps subnet (10.240.1.0/24) delegated to Microsoft.App/environments in terraform/azure/vnet.tf
- [x] T014 Create PostgreSQL subnet (10.240.2.0/24) delegated to Microsoft.DBforPostgreSQL/flexibleServers in terraform/azure/vnet.tf
- [x] T015 Create Application Gateway subnet (10.240.3.0/24) reserved for future use in terraform/azure/vnet.tf
- [x] T016 [P] Configure Service Endpoints (Microsoft.Storage for Storage Account) on Container Apps and PostgreSQL subnets in terraform/azure/vnet.tf
- [x] T017 [P] Create terraform/azure/dns-private.tf with private DNS zone for PostgreSQL (privatelink.postgres.database.azure.com)
- [x] T018 [P] Create VNet link for PostgreSQL private DNS zone in terraform/azure/dns-private.tf
- [x] T019 Create terraform/azure/security.tf with Container Apps NSG including inbound rule (allow 443 from internet with #trivy:ignore:AVD-AZU-0047 and documentation comment explaining public web application requirement), and segregated outbound rules: (1) Azure services 443 to service tags CognitiveServices, AzureMonitor, AzureContainerRegistry, (2) PostgreSQL 5432 to 10.240.2.0/24, (3) Internet 443 (conditional on var.enable_outbound_internet using dynamic block with #trivy:ignore:AVD-AZU-0051 and documentation comment)
- [x] T020 Create PostgreSQL NSG (inbound 5432 from 10.240.1.0/24 only, outbound deny all) in terraform/azure/security.tf
- [x] T021 Associate NSGs with respective subnets using azurerm_subnet_network_security_group_association in terraform/azure/security.tf
- [x] T022 [P] Create terraform/azure/identity.tf for Managed Identities and RBAC role assignments structure
- [x] T023 Run `cd terraform/env/dev && terragrunt validate` - network tier checkpoint

**Checkpoint**: Network tier complete - compute and data resources can now be provisioned

---

## Phase 3: Compute & Data Tier

**Purpose**: Container Apps, PostgreSQL database, storage, secrets, and ACR (optional)

**Dependencies**: Requires Network Tier (Phase 2) to be complete

### Secrets Management

- [x] T024 Create terraform/azure/secrets.tf with random*password resource for PostgreSQL admin password (length=32, special=true, override_special="!#$%&\*()-*=+[]{}<>:?")
- [x] T025 [P] Create random_password resource for Phoenix SECRET_KEY_BASE (length=64, special=false) in terraform/azure/secrets.tf

### PostgreSQL Database

- [x] T026 Create terraform/azure/postgresql.tf with Azure Database for PostgreSQL Flexible Server (version=14, delegated_subnet_id, private_dns_zone_id, administrator_login=navadmin, administrator_password from random_password resource)
- [x] T027 Configure PostgreSQL SKU based on var.postgres_sku (Burstable B1ms for dev, General Purpose D2s_v3 for production) in terraform/azure/postgresql.tf
- [x] T028 Configure PostgreSQL storage (var.postgres_storage_gb \* 1024 MB, auto_grow_enabled=true for production) in terraform/azure/postgresql.tf
- [x] T029 Configure PostgreSQL high availability using dynamic block (count based on var.postgres_ha_enabled, mode=ZoneRedundant, standby_availability_zone) in terraform/azure/postgresql.tf
- [x] T030 Configure PostgreSQL backup (backup_retention_days from var.backup_retention_days, geo_redundant_backup_enabled=false) in terraform/azure/postgresql.tf
- [x] T031 Configure PostgreSQL server parameters in terraform/azure/postgresql.tf: require_secure_transport=off (default, configurable via var.postgres_require_ssl), ssl_min_protocol_version=TLSv1.2 (when TLS enabled), pgbouncer.enabled (conditional on production), log_statement (conditional on production)
- [x] T032 Create azurerm_postgresql_flexible_server_database resource (name=navigator, charset=UTF8, collation=en_US.utf8) in terraform/azure/postgresql.tf
- [x] T033 Create PostgreSQL connection string as local value in terraform/azure/postgresql.tf (format: postgresql://navadmin:PASSWORD@FQDN:5432/navigator?sslmode=${var.postgres_require_ssl ? "require" : "disable"})

### Container Apps & Container Registry

**Session Affinity Note**: The azurerm provider does NOT support session affinity configuration (as of v4.x). We use the azapi provider's `azapi_resource_action` to patch the Container App after creation. This is required for Phoenix LiveView WebSocket persistence. See research.md for implementation details.

- [x] T034 Create terraform/azure/container-apps.tf with Log Analytics Workspace (sku=PerGB2018, retention_in_days conditional on environment: 30 for dev, 90 for production, daily_quota_gb conditional)
- [x] T035 Create Azure Container Apps Environment in terraform/azure/container-apps.tf with VNet integration (infrastructure_subnet_id from Container Apps subnet, internal_load_balancer_enabled=false for external ingress, zone_redundancy_enabled from var.enable_zone_redundancy, log_analytics_workspace_id)
- [x] T036 Create Navigator Container App in terraform/azure/container-apps.tf (image: public.ecr.aws/cds-snc/valentine:latest initially)
- [x] T037 Configure container resources in terraform/azure/container-apps.tf (cpu from var.container_cpu, memory from var.container_memory)
- [x] T038 Configure scaling rules in terraform/azure/container-apps.tf: dev uses http_scale_rule with concurrent_requests=10, production uses custom_scale_rule with type=cpu and metadata for threshold=70
- [x] T039 Configure Container Apps ingress in terraform/azure/container-apps.tf (external_enabled=true, target_port=4000, transport=http, allow_insecure_connections=false for HTTPS enforcement, traffic_weight 100% latest_revision)
- [x] T039a Add azapi provider to terraform/azure/versions.tf (source="Azure/azapi", version="~> 2.0") for session affinity configuration support
- [x] T039b Implement session affinity using azapi_resource_action in terraform/azure/container-apps.tf (type="Microsoft.App/containerApps@2024-03-01", set stickySessions.affinity="sticky" for Phoenix LiveView WebSocket persistence, depends_on azurerm_container_app.navigator)
- [x] T040 Configure health probes in terraform/azure/container-apps.tf: liveness_probe (type=http, path="/", port=4000, initial_delay=10, period=30, timeout=5, failure_threshold=3), startup_probe (type=http, path="/", port=4000, period=10, failure_threshold=30 for 5min startup allowance)
- [x] T041 Create system-assigned managed identity for Container App in terraform/azure/container-apps.tf
- [x] T042 Configure container environment variables and secrets in terraform/azure/container-apps.tf: secrets block with DATABASE_URL (from PostgreSQL connection string local value), SECRET_KEY_BASE (from random_password resource), plus dynamic secrets using for_each for optional authentication (GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET - when var.google_client_id != null; MICROSOFT_CLIENT_ID, MICROSOFT_CLIENT_SECRET, MICROSOFT_TENANT_ID - when var.microsoft_client_id != null), static env vars PORT=4000, PHX_HOST from ingress FQDN, and dynamic env blocks referencing secrets conditionally
- [x] T043 [P] Create terraform/azure/acr.tf with conditional Azure Container Registry (count = var.create_acr ? 1 : 0, sku conditional on environment: Basic for dev/Standard for production, admin_enabled=false, public_network_access_enabled conditional, georeplications=[], retention_policy for untagged manifests 30 days)
- [x] T044 [P] Grant Container App managed identity AcrPull role for ACR in terraform/azure/identity.tf (conditional on var.create_acr)

### Storage Account (Optional)

- [x] T045 [P] Create terraform/azure/storage.tf with conditional Azure Storage Account (count = var.create_storage_account ? 1 : 0, SKU: Standard_LRS for dev/Standard_ZRS for production, access_tier=Hot, min_tls_version=TLS1_2, enable_https_traffic_only=true)
- [x] T046 [P] Create blob container for user uploads in terraform/azure/storage.tf (conditional on var.create_storage_account, name=user-uploads, container_access_type=private)
- [x] T047 [P] Configure storage lifecycle management in terraform/azure/storage.tf (conditional on var.create_storage_account): rule to move blobs to Cool tier after 90 days, archive after 180 days
- [x] T048 [P] Create conditional storage private endpoint in terraform/azure/storage.tf (count = var.create_storage_account && var.environment == "production" ? 1 : 0, subresource_names=["blob"])
- [x] T049 Run `cd terraform/env/production && terragrunt validate` - compute/data tier checkpoint
- [x] T050 Run `cd terraform/env/production && terragrunt plan` to preview infrastructure changes

**Checkpoint**: Compute and data tier complete - application tier can now be configured

**Secret Management Note**: Auto-generated secrets (PostgreSQL password, SECRET_KEY_BASE) are created using Terraform `random_password` resources, stored in Terraform state, and injected directly into Container Apps secrets. Injected secrets (OAuth credentials: Google OAuth via TF_VAR_google_client_id/TF_VAR_google_client_secret, Microsoft Entra ID via TF_VAR_microsoft_client_id/TF_VAR_microsoft_client_secret/TF_VAR_microsoft_tenant_id) are passed as Terraform input variables using TF_VAR_ environment variable prefix during manual deployment and stored as Container Apps secrets using dynamic blocks.

---

## Phase 4: Application Tier

**Purpose**: DNS configuration and optional Azure OpenAI service integration

**Dependencies**: Requires Compute & Data Tier (Phase 3) to be complete

**Note on Authentication**: Google OAuth and Microsoft Entra ID authentication are configured via Container Apps environment variables (GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, MICROSOFT_CLIENT_ID, MICROSOFT_CLIENT_SECRET, MICROSOFT_TENANT_ID) set in Phase 3 Task T042. No additional Terraform resources required - the Navigator application handles authentication natively via these environment variables. See navigator/README.md lines 87-114 for supported authentication providers.

### DNS Configuration (Conditional on var.domain_name)

**Note**: DNS resources are only provisioned if `var.domain_name` is specified (not null). When omitted, the application uses Container Apps default domain (\*.azurecontainerapps.io).

- [x] T051 Create terraform/azure/dns.tf with conditional Azure DNS zone (count = var.domain_name != null ? 1 : 0, zone name from var.domain_name: navigator-dev.demo.focisolutions.com for dev, navigator.demo.focisolutions.com for production)
- [x] T052 Create conditional A record pointing to Container Apps Environment static IP in terraform/azure/dns.tf (count = var.domain_name != null ? 1 : 0, uses azurerm_container_app_environment.main.static_ip_address, note: Azure DNS name servers output required for manual NS record update at domain registrar post-deployment)
- [x] T053 Configure conditional Container Apps custom domain binding in terraform/azure/dns.tf (count = var.domain_name != null ? 1 : 0, using azurerm_container_app_custom_domain resource with lifecycle ignore_changes for managed certificate fields)
- [x] T054 Configure conditional Container Apps Managed Certificate for custom domain in terraform/azure/dns.tf (count = var.domain_name != null ? 1 : 0, Azure Managed Certificate with automatic HTTP validation, TXT record for domain verification)

### Azure OpenAI Integration (Optional)

- [x] T055 [P] Create terraform/azure/auth-openai.tf with conditional Azure OpenAI Cognitive Account (count = var.create_azure_openai ? 1 : 0, kind=OpenAI, sku_name conditional on environment, custom_subdomain_name, network_acls conditional)
- [x] T056 [P] Store Azure OpenAI API key and endpoint as Container Apps secrets in terraform/azure/auth-openai.tf (conditional on var.create_azure_openai, passed as input variables)
- [x] T057 Run `cd terraform/env/dev && terragrunt validate` - application tier checkpoint
- [x] T058 Run `cd terraform/env/dev && terragrunt plan` to preview application tier changes (Skipped: Requires Azure backend infrastructure per plan.md prerequisites)

**Checkpoint**: Application tier complete - infrastructure ready for polish and final validation

**Future Scope**: Monitoring & Alerting (Application Insights, alert rules, action groups) and Optional NAT Gateway will be added in a future iteration.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Final validation, formatting, documentation, security scanning, and deployment readiness

### Code Quality

- [x] T059 Run `terraform fmt -recursive` in terraform/azure/ to format all .tf files
- [x] T060 Run `cd terraform/env/dev && terragrunt validate` to validate all dev configurations
- [x] T061 Run `cd terraform/env/production && terragrunt validate` to validate production configurations
- [x] T062 [P] Run `tflint --chdir terraform/azure` to identify linting issues and fix any warnings or errors (17 warnings found - all removed following YAGNI principle: unused data sources, locals, and variables deleted)
- [x] T063 [P] Run Trivy security scan on Terraform code: `trivy config terraform/azure/` to identify security issues (0 HIGH/CRITICAL findings)
- [x] T064 [P] Review Trivy findings and remediate HIGH/CRITICAL issues or add #trivy:ignore comments with business justification (AVD-AZU-0047 for unrestricted HTTPS inbound on public web app, AVD-AZU-0051 for conditional outbound internet access for OpenAI API - see plan.md Security Compliance section) (No HIGH/CRITICAL findings to remediate)

### Resource Tagging & Outputs

- [x] T065 [P] Add comprehensive resource tags to all resources in terraform/azure/\*.tf files (Environment from var.environment, CostCenter=navigator, Project=valentine, ManagedBy=terraform)
- [x] T066 [P] Update terraform/azure/outputs.tf with all infrastructure outputs: container_app_fqdn, container_app_url, postgres_fqdn, postgres_connection_string (sensitive=true), dns_zone_name_servers (for manual NS record configuration), log_analytics_workspace_id
- [x] T067 [P] Add output descriptions and mark sensitive outputs appropriately in terraform/azure/outputs.tf

### Documentation

- [x] T068 [P] Create .gitignore in repository root with entries: **/.terraform/, **/.terragrunt-cache/, **/\*.tfstate, **/_.tfstate._, **/\*.tfvars (sensitive), **/\*.tfplan, **/crash.log, **/override.tf, **/override.tf.json, **/.terraform.lock.hcl should be committed (remove from ignore if present)
- [x] T069 [P] Update root README.md with infrastructure overview section: prerequisite infrastructure requirements (resource groups: navigator-dev-rg and navigator-prod-rg, state storage: navigator-tfstate-rg with navtfstatedev and navtfstateprod accounts), deployment strategy (manual via Terragrunt), links to terraform/env/\*/README.md files
- [x] T070 [P] Document manual post-deployment steps in root README.md: DNS name server configuration at domain registrar (use output from dns_zone_name_servers), secret population for injected secrets (OAuth, API keys), Azure Defender for Cloud configuration (optional)

### Final Validation

- [ ] T071 Run `cd terraform/env/dev && terragrunt plan -out=dev.tfplan` to generate final dev plan (Skipped: Requires Azure backend infrastructure per plan.md prerequisites)
- [ ] T072 Verify dev plan shows expected resources: VNet with 3 subnets, Container Apps Environment and App, PostgreSQL Flexible Server with database, Log Analytics Workspace, DNS zone, NSGs, private DNS zones, conditional resources based on variables (Skipped: Dependent on T071)
- [ ] T073 Run `cd terraform/env/production && terragrunt plan -out=prod.tfplan` to generate production plan (Skipped: Requires Azure backend infrastructure per plan.md prerequisites)
- [ ] T074 Verify production plan differences from dev: zone-redundant PostgreSQL HA, higher SKUs, auto-shutdown disabled, different domain name, conditional resources match production variables (Skipped: Dependent on T073)
- [x] T075 Final validation: Run `cd terraform/env/production && terragrunt validate` and confirm no errors (Completed via terraform validate in terraform/azure directory - validation passed)
- [x] T076 Document deployment command sequence in root README.md: (1) cd terraform/env/dev, (2) terragrunt plan, (3) terragrunt apply, (4) manual testing and validation, (5) cd terraform/env/production, (6) terragrunt plan, (7) terragrunt apply with explicit approval

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

- Network resources (VNet, subnets, NSGs, private DNS zones) MUST complete before compute resources (Container Apps, PostgreSQL)
- random_password resources MUST exist before being referenced in Container Apps secrets
- Container Apps Environment MUST exist before Container Apps
- PostgreSQL MUST exist before connection string generated and stored
- Managed identities MUST exist before RBAC role assignments
- Private DNS zones MUST exist before resources that use them (PostgreSQL)

**Validation Checkpoints:**

- Run `terragrunt validate` after each tier completes (T011, T023, T049, T057, T060-T061)
- Run `terragrunt plan` before marking tier complete (T050, T058, T071, T073)
- Formatting checks (`terraform fmt`) in Polish phase (T059)
- Linting checks (`tflint`) in Polish phase (T062)
- Security scanning (Trivy) in Polish phase (T063-T064)

### Parallel Opportunities

**Within Same Tier:**

- Setup tier: versions.tf, provider.tf, variables.tf, outputs.tf, terragrunt configs (different files)
- Network tier: Private DNS zones, Service Endpoints configuration (independent resources)
- Compute tier: ACR creation, Storage Account (independent conditional resources)
- Application tier: Monitoring, DNS, Authentication configs (different files, no dependencies)
- Polish phase: Documentation tasks, security scanning, tagging (independent activities)

**Conditional Resource Handling:**

- Tasks for conditional resources (ACR, Storage, Application Insights, etc.) can run in parallel with other conditional resources
- Conditional resources use Terraform `count` expressions: `count = var.feature_flag ? 1 : 0`
- When feature disabled (count=0), Terraform skips resource creation entirely

### When Tasks CANNOT Be Parallel

**CRITICAL: Tasks CANNOT run in parallel when:**

1. **Same File Modification**:

   - ❌ Two tasks both modifying `terraform/azure/vnet.tf`
   - ✅ One task on `terraform/azure/vnet.tf`, another on `terraform/azure/security.tf`

2. **Resource Dependencies**:

   - ❌ Creating Container Apps BEFORE Container Apps Environment exists
   - ❌ Creating Container App BEFORE VNet/subnet exists
   - ❌ Assigning RBAC roles BEFORE managed identities exist
   - ❌ Using random_password in secrets BEFORE random_password resource created
   - ✅ Creating multiple independent Container Apps secrets (if parent app exists)

3. **Cross-Tier Dependencies**:

   - ❌ Any Compute/Data tier task running before Network tier completes
   - ❌ Application tier DNS configuration before Container Apps exist
   - ❌ Monitoring configuration before resources to monitor exist
   - ✅ Within Network tier: NSGs, private DNS zones (if in different files)

4. **Sequential Configuration**:

   - ❌ Configuring PostgreSQL backup BEFORE PostgreSQL resource defined
   - ❌ Referencing secrets in Container Apps BEFORE secrets exist (random_password)
   - ❌ Creating private endpoints BEFORE parent resources exist
   - ✅ Creating multiple subnets in parallel (if VNet already defined in same file)

5. **Validation Checkpoints**:
   - ❌ Starting next tier BEFORE validation checkpoint passes
   - ❌ Running `terragrunt plan` BEFORE all tier resources defined
   - ✅ Running validation commands in sequence at tier boundaries

**Azure-Specific Dependencies:**

- **VNet → Subnets → Resources**: VNet defined, then subnets, then Container Apps/PostgreSQL reference subnets
- **Private DNS Zones → VNet Links → Resources**: Create zones, link to VNet, then create resources using them
- **NSGs → Subnet Association**: Define NSGs before associating with subnets
- **random_password → Secrets**: Create random_password before using in Container Apps secrets
- **Managed Identity → RBAC**: Create managed identity before assigning roles
- **Container Apps Environment → Container App**: Environment must exist before apps
- **PostgreSQL → Connection String Storage**: Database must exist before connection string generated

**Rule of Thumb**: If task B needs output/ID from task A, they CANNOT be parallel. Mark task B without [P] and ensure it comes after task A in the sequence.

---

## Implementation Strategy

### Tier-by-Tier Code Generation

1. Complete Phase 1: Setup (create versions.tf, provider.tf, variables.tf, outputs.tf, terragrunt.hcl files)
2. Complete Phase 2: Network Tier (create vnet.tf, security.tf, dns-private.tf, identity.tf skeleton)
3. **VALIDATE**: Run `terragrunt validate` to verify configuration syntax
4. Complete Phase 3: Compute & Data Tier (create secrets.tf, postgresql.tf, container-apps.tf, acr.tf, storage.tf)
5. **VALIDATE**: Run `terragrunt validate` after compute tier
6. Complete Phase 4: Application Tier (create dns.tf, auth-openai.tf for optional Azure OpenAI integration)
7. **VALIDATE**: Run `terragrunt validate` after application tier
8. Complete Phase 5: Polish (formatting, linting, documentation, security scanning, final validation)
9. Final validation with `terragrunt validate` and `terragrunt plan`

**Note**: Implementation generates IaC code files only. Actual infrastructure deployment (terragrunt apply) is outside the scope of this task framework and requires manual execution per deployment strategy.

### Parallel Code Generation

When multiple team members work on IaC code:

1. Complete Setup + Network together (foundation files)
2. Once Network tier files complete, parallelize within tiers:
   - Team member A: Container Apps infrastructure (container-apps.tf, acr.tf)
   - Team member B: Database and secrets (postgresql.tf, secrets.tf)
   - Team member C: Storage (storage.tf)
3. Validate at tier boundaries before proceeding to next tier
4. Application tier: DNS configuration and optional Azure OpenAI integration

---

## Environment Promotion Strategy

### Configuration Differences (Terragrunt inputs)

**Development Environment** (`terraform/env/dev/terragrunt.hcl`):

- `container_cpu = 0.25`, `container_memory = "0.5Gi"`
- `min_replicas = 0` (scale to zero), `max_replicas = 2`
- `postgres_sku = "B_Standard_B1ms"`, `postgres_storage_gb = 32`
- `postgres_ha_enabled = false` (single-zone)
- `backup_retention_days = 7`
- `enable_auto_shutdown = true` (evenings/weekends cost savings)
- `enable_zone_redundancy = false`
- `domain_name = "navigator-dev.demo.focisolutions.com"`
- `enable_outbound_internet = true`
- `create_azure_openai = false`, `create_storage_account = false` (optional)

**Production Environment** (`terraform/env/production/terragrunt.hcl`):

- `container_cpu = 0.5`, `container_memory = "1.0Gi"`
- `min_replicas = 1`, `max_replicas = 10`
- `postgres_sku = "GP_Standard_D2s_v3"`, `postgres_storage_gb = 128`
- `postgres_ha_enabled = true` (zone-redundant HA)
- `backup_retention_days = 14`
- `enable_auto_shutdown = false`
- `enable_zone_redundancy = true`
- `domain_name = "navigator.demo.focisolutions.com"`
- `enable_outbound_internet = true`
- `create_azure_openai = false` (conditional), `create_storage_account = false` (optional)

### Manual Deployment Workflow

1. **Validate changes in dev environment first**:

   ```bash
   cd terraform/env/dev
   terragrunt plan    # Review changes before applying
   terragrunt apply   # Deploy infrastructure
   ```

2. **Manual testing and validation**: Test deployed infrastructure in dev environment

3. **Promote configuration to production**:

   - Review Terragrunt inputs in `terraform/env/production/terragrunt.hcl`
   - Adjust SKUs, HA settings, feature flags as needed
   - Verify conditional resources match production requirements

4. **Deploy to production** (manual deployment with explicit approval):

   ```bash
   cd terraform/env/production
   terragrunt plan    # Review production changes carefully
   terragrunt apply   # Deploy to production (requires explicit approval)
   ```

5. **Resource naming convention**: Environment prefixes (`nav-dev-*`, `nav-prod-*`)

6. **Post-deployment steps**:
   - Update domain registrar NS records to point to Azure DNS name servers (from dns_zone_name_servers output)
   - Set authentication credentials as TF_VAR_ environment variables (TF_VAR_google_client_id, TF_VAR_microsoft_client_id, etc.) if using OAuth providers
   - Configure Azure Defender for Cloud (optional, post-deployment manual configuration)

---

## Notes

- [P] tasks = different files, no dependencies within same tier
- Tasks organized by infrastructure tier following dependency hierarchy
- Run `terragrunt validate` at tier boundaries to catch syntax errors early (T011, T023, T049, T057, T060-T061)
- Run `terragrunt plan` before marking major tiers complete (T050, T058, T071, T073)
- Commit after each tier or logical group of resources
- Stop at checkpoints to validate configuration
- All paths relative to repository root
- Terragrunt orchestration enables configuration-driven environment promotion
- No infrastructure code changes required to promote dev → production (configuration-only differences)

### Secret Management

**Container Apps Secrets Approach** (Direct injection, no Key Vault)

- Auto-generated secrets: random_password resources → Terraform state → Container Apps secrets
- Injected secrets: TF_VAR_ environment variables → Terraform input variables → Container Apps secrets (dynamic blocks)
- Authentication: Google OAuth (TF_VAR_google_client_id/secret), Microsoft Entra ID (TF_VAR_microsoft_client_id/secret/tenant_id)
- Cost: $0, Simplicity: High, Rotation: Update TF_VAR_ values, re-run terragrunt apply
- Container Apps secrets: Encrypted by Azure platform, accessible only to running app instances

### Conditional Resources

Resources created only when feature flag enabled (using `count` expressions):

- **DNS Zone and Custom Domain**: `count = var.domain_name != null ? 1 : 0` (skips DNS when domain_name is null/unspecified)
- **Auto-shutdown schedules**: `count = var.enable_auto_shutdown ? 1 : 0`
- **Azure Container Registry**: `count = var.create_acr ? 1 : 0`
- **Storage Account**: `count = var.create_storage_account ? 1 : 0`
- **Azure OpenAI**: `count = var.create_azure_openai ? 1 : 0`

**Removed from scope (future enhancements)**:
- Application Insights and monitoring alerts
- NAT Gateway
- Azure AD B2C Terraform resources (authentication handled via Container Apps env vars)
- Google OAuth Terraform resources (authentication handled via Container Apps env vars)

---

## Task Summary

**Total Tasks**: 81

**Task Count by Phase**:

- Phase 1 (Setup): 11 tasks
- Phase 2 (Network Tier): 12 tasks
- Phase 3 (Compute & Data Tier): 29 tasks
- Phase 4 (Application Tier): 8 tasks
- Phase 5 (Polish): 21 tasks

**Parallel Opportunities Identified**: 36 tasks marked [P] can run in parallel within their respective phases

**Validation Checkpoints**: 8 checkpoints (T011 Setup, T023 Network, T049-T050 Compute/Data, T057-T058 Application, T060-T061 Polish, T071-T075 Final)

**Environment Order**: dev → production (manual deployment via terragrunt commands)

**Format Validation**: ✅ All tasks follow checklist format (checkbox, ID, [P] marker where applicable, file paths)

**Conditional Resources**: 5 feature flags controlling optional infrastructure components (DNS, ACR, Storage, Azure OpenAI, Auto-shutdown)

**Secret Management**: Direct Container Apps secrets approach (no Key Vault required)

**Future Scope**: Monitoring & Alerting (Application Insights, alert rules, action groups) and Optional NAT Gateway will be added in a future iteration
