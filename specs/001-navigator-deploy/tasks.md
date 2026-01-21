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

- [ ] T001 Create terraform/ directory structure with azure/ and env/ subdirectories
- [ ] T002 Create terraform/env/dev/ and terraform/env/production/ directories
- [ ] T003 Create terraform/azure/templates/ directory for Container Apps environment variable templates
- [ ] T004 [P] Create terraform/azure/versions.tf with Terraform >= 1.9 and azurerm ~> 4.0 constraints
- [ ] T005 [P] Create terraform/azure/provider.tf with Azure provider configuration and features block
- [ ] T006 [P] Create terraform/azure/variables.tf with all configurable input variables including use_key_vault (bool, default: false), enable_application_insights (bool), enable_auto_shutdown (bool), enable_zone_redundancy (bool), enable_outbound_internet (bool, default: true), create_google_auth (bool), create_azure_ad_b2c (bool), create_azure_openai (bool), create_storage_account (bool), plus environment, location, container CPU/memory, min/max replicas, postgres_sku, postgres_storage_gb, postgres_ha_enabled, backup_retention_days, domain_name
- [ ] T007 [P] Create terraform/azure/outputs.tf with key infrastructure outputs (Container Apps URL, PostgreSQL FQDN, conditional Key Vault URI only when use_key_vault=true, DNS zone name servers)
- [ ] T008 [P] Create terraform/env/dev/terragrunt.hcl with dev environment configuration (source = "../..//azure", remote_state config for navtfstatedev, inputs block with: use_key_vault=false, container_cpu=0.25, container_memory=0.5Gi, min_replicas=0, max_replicas=2, postgres_sku=B_Standard_B1ms, postgres_storage_gb=32, postgres_ha_enabled=false, backup_retention_days=7, enable_application_insights=false, enable_auto_shutdown=true, enable_zone_redundancy=false, domain_name=navigator-dev.cdssandbox.xyz, enable_outbound_internet=true, create_google_auth=false, create_azure_ad_b2c=true, create_azure_openai=false)
- [ ] T009 [P] Create terraform/env/production/terragrunt.hcl with production environment configuration (source = "../..//azure", remote_state config for navtfstateprod, inputs block with: use_key_vault=false, container_cpu=0.5, container_memory=1.0Gi, min_replicas=1, max_replicas=10, postgres_sku=GP_Standard_D2s_v3, postgres_storage_gb=128, postgres_ha_enabled=true, backup_retention_days=14, enable_application_insights=true, enable_auto_shutdown=false, enable_zone_redundancy=true, domain_name=valentine.cds-snc.ca, enable_outbound_internet=true, create_google_auth=true, create_azure_ad_b2c=false, create_azure_openai=false)
- [ ] T010 Run `cd terraform/env/dev && terragrunt init` to initialize backend and download providers (requires Azure authentication: `az login --scope https://management.azure.com//.default` and RBAC roles: Contributor on resource groups, Storage Blob Data Contributor on state storage - see spec.md Dependencies section)
- [ ] T011 Run `cd terraform/env/dev && terragrunt validate` - setup checkpoint (requires T010 to complete first)

---

## Phase 2: Network Tier

**Purpose**: Virtual network, subnets, NSGs, private DNS zones, and network security - prerequisite for all compute/data resources

**⚠️ CRITICAL**: Network tier MUST complete before compute resources can be provisioned

- [ ] T012 Create terraform/azure/vnet.tf with Virtual Network (10.240.0.0/16, Canada Central)
- [ ] T013 Create Container Apps subnet (10.240.1.0/24) delegated to Microsoft.App/environments in terraform/azure/vnet.tf
- [ ] T014 Create PostgreSQL subnet (10.240.2.0/24) delegated to Microsoft.DBforPostgreSQL/flexibleServers in terraform/azure/vnet.tf
- [ ] T015 Create Application Gateway subnet (10.240.3.0/24) reserved for future use in terraform/azure/vnet.tf
- [ ] T016 [P] Configure Service Endpoints (Microsoft.Storage for Storage Account, Microsoft.KeyVault conditional on var.use_key_vault) on Container Apps and PostgreSQL subnets in terraform/azure/vnet.tf
- [ ] T017 [P] Create terraform/azure/dns-private.tf with private DNS zone for PostgreSQL (privatelink.postgres.database.azure.com)
- [ ] T018 [P] Create VNet link for PostgreSQL private DNS zone in terraform/azure/dns-private.tf
- [ ] T019 Create terraform/azure/security.tf with Container Apps NSG including inbound rule (allow 443 from internet with #trivy:ignore:AVD-AZU-0047 and documentation comment explaining public web application requirement), and segregated outbound rules: (1) Azure services 443 to service tags AzureKeyVault (conditional - only if var.use_key_vault=true using dynamic block), CognitiveServices, AzureMonitor, AzureContainerRegistry, (2) PostgreSQL 5432 to 10.240.2.0/24, (3) Internet 443 (conditional on var.enable_outbound_internet using dynamic block with #trivy:ignore:AVD-AZU-0051 and documentation comment)
- [ ] T020 Create PostgreSQL NSG (inbound 5432 from 10.240.1.0/24 only, outbound deny all) in terraform/azure/security.tf
- [ ] T021 Associate NSGs with respective subnets using azurerm_subnet_network_security_group_association in terraform/azure/security.tf
- [ ] T022 [P] Create terraform/azure/identity.tf for Managed Identities and RBAC role assignments structure
- [ ] T023 Run `cd terraform/env/dev && terragrunt validate` - network tier checkpoint

**Checkpoint**: Network tier complete - compute and data resources can now be provisioned

---

## Phase 3: Compute & Data Tier

**Purpose**: Container Apps, PostgreSQL database, storage, Key Vault (conditional), secrets, and ACR (optional)

**Dependencies**: Requires Network Tier (Phase 2) to be complete

### Secrets & Key Vault (Conditional)

- [ ] T024 Create terraform/azure/secrets.tf with random_password resource for PostgreSQL admin password (length=32, special=true, override_special="!#$%&*()-_=+[]{}<>:?")
- [ ] T025 [P] Create random_password resource for Phoenix SECRET_KEY_BASE (length=64, special=false) in terraform/azure/secrets.tf
- [ ] T026 [P] Create terraform/azure/keyvault.tf with conditional Azure Key Vault (count = var.use_key_vault ? 1 : 0, SKU: standard for dev/premium for production based on var.environment, soft_delete_retention_days=90, purge_protection_enabled conditional on environment, enable_rbac_authorization=true, network_acls with default_action conditional on environment)
- [ ] T027 [P] Configure conditional Key Vault RBAC role assignment for Terraform deployment identity (Key Vault Secrets Officer role, conditional on var.use_key_vault) in terraform/azure/identity.tf
- [ ] T028 [P] Create conditional azurerm_key_vault_secret resources in terraform/azure/keyvault.tf (count = var.use_key_vault ? 1 : 0): postgres-admin-password (from random_password), phoenix-secret-key-base (from random_password), with depends_on for RBAC role assignment
- [ ] T029 [P] Create conditional Key Vault private endpoint in terraform/azure/keyvault.tf (count = var.use_key_vault && var.environment == "production" ? 1 : 0)
- [ ] T030 [P] Create conditional private DNS zone for Key Vault (privatelink.vaultcore.azure.net) in terraform/azure/dns-private.tf (count = var.use_key_vault && var.environment == "production" ? 1 : 0)

### PostgreSQL Database

- [ ] T031 Create terraform/azure/postgresql.tf with Azure Database for PostgreSQL Flexible Server (version=14, delegated_subnet_id, private_dns_zone_id, administrator_login=navadmin, administrator_password from random_password resource)
- [ ] T032 Configure PostgreSQL SKU based on var.postgres_sku (Burstable B1ms for dev, General Purpose D2s_v3 for production) in terraform/azure/postgresql.tf
- [ ] T033 Configure PostgreSQL storage (var.postgres_storage_gb * 1024 MB, auto_grow_enabled=true for production) in terraform/azure/postgresql.tf
- [ ] T034 Configure PostgreSQL high availability using dynamic block (count based on var.postgres_ha_enabled, mode=ZoneRedundant, standby_availability_zone) in terraform/azure/postgresql.tf
- [ ] T035 Configure PostgreSQL backup (backup_retention_days from var.backup_retention_days, geo_redundant_backup_enabled=false) in terraform/azure/postgresql.tf
- [ ] T036 Configure PostgreSQL server parameters in terraform/azure/postgresql.tf: require_secure_transport=on, ssl_min_protocol_version=TLSv1.2, pgbouncer.enabled (conditional on production), log_statement (conditional on production)
- [ ] T037 Create azurerm_postgresql_flexible_server_database resource (name=navigator, charset=UTF8, collation=en_US.utf8) in terraform/azure/postgresql.tf
- [ ] T038 Create PostgreSQL connection string as local value in terraform/azure/postgresql.tf (format: postgresql://navadmin:PASSWORD@FQDN:5432/navigator?sslmode=require)
- [ ] T039 Store PostgreSQL connection string conditionally: (1) if var.use_key_vault=true create azurerm_key_vault_secret, (2) if var.use_key_vault=false store as Container Apps secret in container-apps.tf (dual-mode configuration)

### Container Apps & Container Registry

- [ ] T040 Create terraform/azure/container-apps.tf with Log Analytics Workspace (sku=PerGB2018, retention_in_days conditional on environment: 30 for dev, 90 for production, daily_quota_gb conditional)
- [ ] T041 Create Azure Container Apps Environment in terraform/azure/container-apps.tf with VNet integration (infrastructure_subnet_id from Container Apps subnet, internal_load_balancer_enabled=false for external ingress, zone_redundancy_enabled from var.enable_zone_redundancy, log_analytics_workspace_id)
- [ ] T042 Create Navigator Container App in terraform/azure/container-apps.tf (image: public.ecr.aws/cds-snc/valentine:latest initially)
- [ ] T043 Configure container resources in terraform/azure/container-apps.tf (cpu from var.container_cpu, memory from var.container_memory)
- [ ] T044 Configure scaling rules in terraform/azure/container-apps.tf: dev uses http_scale_rule with concurrent_requests=10, production uses custom_scale_rule with type=cpu and metadata for threshold=70
- [ ] T045 Configure Container Apps ingress in terraform/azure/container-apps.tf (external_enabled=true, target_port=4000, transport=http, allow_insecure_connections=false for HTTPS enforcement, traffic_weight 100% latest_revision, session_affinity sticky sessions enabled)
- [ ] T046 Configure health probes in terraform/azure/container-apps.tf: liveness_probe (type=http, path="/", port=4000, initial_delay=10, period=30, timeout=5, failure_threshold=3), startup_probe (type=http, path="/", port=4000, period=10, failure_threshold=30 for 5min startup allowance)
- [ ] T047 Create system-assigned managed identity for Container App in terraform/azure/container-apps.tf
- [ ] T048 Configure container environment variables with dual-mode secret references in terraform/azure/container-apps.tf: (1) if var.use_key_vault=true use secret blocks with key_vault_secret_id for DATABASE_URL, SECRET_KEY_BASE, (2) if var.use_key_vault=false use secret blocks with value from Terraform state/random_password resources, plus static env vars PORT=4000, PHX_HOST from ingress FQDN
- [ ] T049 Grant Container App managed identity Key Vault Secrets User role in terraform/azure/identity.tf (conditional on var.use_key_vault, principal_id from container app identity, scope=key_vault_id)
- [ ] T050 [P] Create terraform/azure/acr.tf with conditional Azure Container Registry (count = var.create_acr ? 1 : 0, sku conditional on environment: Basic for dev/Standard for production, admin_enabled=false, public_network_access_enabled conditional, georeplications=[], retention_policy for untagged manifests 30 days)
- [ ] T051 [P] Grant Container App managed identity AcrPull role for ACR in terraform/azure/identity.tf (conditional on var.create_acr)

### Storage Account (Optional)

- [ ] T052 [P] Create terraform/azure/storage.tf with conditional Azure Storage Account (count = var.create_storage_account ? 1 : 0, SKU: Standard_LRS for dev/Standard_ZRS for production, access_tier=Hot, min_tls_version=TLS1_2, enable_https_traffic_only=true)
- [ ] T053 [P] Create blob container for user uploads in terraform/azure/storage.tf (conditional on var.create_storage_account, name=user-uploads, container_access_type=private)
- [ ] T054 [P] Configure storage lifecycle management in terraform/azure/storage.tf (conditional on var.create_storage_account): rule to move blobs to Cool tier after 90 days, archive after 180 days
- [ ] T055 [P] Create conditional storage private endpoint in terraform/azure/storage.tf (count = var.create_storage_account && var.environment == "production" ? 1 : 0, subresource_names=["blob"])
- [ ] T056 Run `cd terraform/env/production && terragrunt validate` - compute/data tier checkpoint
- [ ] T057 Run `cd terraform/env/production && terragrunt plan` to preview infrastructure changes

**Checkpoint**: Compute and data tier complete - application tier can now be configured

**Secret Management Note**: Tasks T024-T028 implement dual-mode secret management:
- **Mode A** (use_key_vault=false, default): Auto-generated secrets (random_password) stored in Terraform state, injected into Container Apps secrets directly
- **Mode B** (use_key_vault=true, optional): Auto-generated secrets stored in Key Vault, Container Apps references via secret URI
- Injected secrets (OAuth, API keys) passed as Terraform input variables during manual deployment, stored according to mode

---

## Phase 4: Application Tier

**Purpose**: DNS, monitoring, alerting, authentication configuration, and optional NAT gateway

**Dependencies**: Requires Compute & Data Tier (Phase 3) to be complete

### DNS Configuration

- [ ] T058 Create terraform/azure/dns.tf with Azure DNS zone (zone name from var.domain_name: navigator-dev.cdssandbox.xyz for dev, valentine.cds-snc.ca for production)
- [ ] T059 Create A record pointing to Container Apps default domain FQDN in terraform/azure/dns.tf (note: Azure DNS name servers output required for manual NS record update at domain registrar post-deployment)
- [ ] T060 Configure Container Apps custom domain binding in terraform/azure/dns.tf (using azurerm_container_app_custom_domain resource)
- [ ] T061 Configure Container Apps Managed Certificate for custom domain in terraform/azure/dns.tf (certificate_binding_type=SniEnabled, automatic DNS validation)

### Monitoring & Alerting

- [ ] T062 [P] Create terraform/azure/monitoring.tf with conditional Application Insights (count = var.enable_application_insights ? 1 : 0, application_type=web, workspace_id from Log Analytics, sampling_percentage=100 for no sampling, retention_in_days conditional on environment)
- [ ] T063 [P] Configure Application Insights connection to Container Apps Environment in terraform/azure/monitoring.tf (dapr_ai_instrumentation_key conditional on enable_application_insights)
- [ ] T064 [P] Create terraform/azure/alerts.tf with conditional monitoring alert rules (count = var.enable_application_insights ? 1 : 0): high CPU alert (>80% for 5 min), high memory alert (>80%), database connection failures, Container Apps HTTP 5xx errors
- [ ] T065 [P] Configure alert action groups in terraform/azure/alerts.tf (email notifications, webhook for incident management integration)

### Authentication & External Services

- [ ] T066 [P] Create terraform/azure/auth-b2c.tf for conditional Azure AD B2C configuration (count = var.create_azure_ad_b2c ? 1 : 0) with placeholder for tenant configuration
- [ ] T067 [P] Create terraform/azure/auth-google.tf for conditional Google OAuth configuration (count = var.create_google_auth ? 1 : 0) with variables for client_id and client_secret
- [ ] T068 [P] Store OAuth credentials conditionally in terraform/azure/auth-google.tf: if var.use_key_vault=true create azurerm_key_vault_secret resources, else pass as Container Apps secrets
- [ ] T069 [P] Create terraform/azure/auth-openai.tf with conditional Azure OpenAI Cognitive Account (count = var.create_azure_openai ? 1 : 0, kind=OpenAI, sku_name conditional on environment, custom_subdomain_name, network_acls conditional)
- [ ] T070 [P] Store Azure OpenAI API key and endpoint conditionally: if var.use_key_vault=true create azurerm_key_vault_secret, else pass as input variable to Container Apps secrets

### Optional NAT Gateway

- [ ] T071 [P] Create conditional NAT Gateway in terraform/azure/vnet.tf (count = var.create_nat_gateway ? 1 : 0 where create_nat_gateway defaults to false, optional even for production, provides consistent outbound IP for allowlisting)
- [ ] T072 [P] Create public IP for NAT Gateway in terraform/azure/vnet.tf (conditional on var.create_nat_gateway)
- [ ] T073 [P] Associate NAT Gateway with Container Apps subnet in terraform/azure/vnet.tf (conditional on var.create_nat_gateway)
- [ ] T074 Run `cd terraform/env/dev && terragrunt validate` - application tier checkpoint
- [ ] T075 Run `cd terraform/env/dev && terragrunt plan` to preview application tier changes

**Checkpoint**: Application tier complete - infrastructure ready for polish and final validation

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Final validation, formatting, documentation, security scanning, and deployment readiness

### Code Quality

- [ ] T076 Run `terraform fmt -recursive` in terraform/azure/ to format all .tf files
- [ ] T077 Run `cd terraform/env/dev && terragrunt validate` to validate all dev configurations
- [ ] T078 Run `cd terraform/env/production && terragrunt validate` to validate production configurations
- [ ] T079 [P] Run Trivy security scan on Terraform code: `trivy config terraform/azure/` to identify security issues
- [ ] T080 [P] Review Trivy findings and remediate HIGH/CRITICAL issues or add #trivy:ignore comments with business justification (AVD-AZU-0047 for unrestricted HTTPS inbound on public web app, AVD-AZU-0051 for conditional outbound internet access for OpenAI API - see plan.md Security Compliance section)

### Resource Tagging & Outputs

- [ ] T081 [P] Add comprehensive resource tags to all resources in terraform/azure/*.tf files (Environment from var.environment, CostCenter=navigator, Project=valentine, ManagedBy=terraform)
- [ ] T082 [P] Update terraform/azure/outputs.tf with all infrastructure outputs: container_app_fqdn, container_app_url, postgres_fqdn, postgres_connection_string (sensitive=true), key_vault_uri (conditional on var.use_key_vault with condition in output), dns_zone_name_servers (for manual NS record configuration), log_analytics_workspace_id, application_insights_instrumentation_key (conditional)
- [ ] T083 [P] Add output descriptions and mark sensitive outputs appropriately in terraform/azure/outputs.tf

### Documentation

- [ ] T084 [P] Create terraform/azure/README.md with module documentation: purpose, architecture overview, variables reference table, outputs reference table, usage examples for dev and production deployments, conditional resources explanation (Key Vault, Application Insights, auto-shutdown, ACR, Storage, NAT Gateway), secret management modes
- [ ] T085 [P] Create terraform/env/dev/README.md with dev environment deployment instructions: prerequisites checklist (reference plan.md lines 641-654), terragrunt init/plan/apply commands, manual secret population steps for injected secrets, validation steps
- [ ] T086 [P] Create terraform/env/production/README.md with production deployment guide: prerequisites checklist, deployment approval workflow, terragrunt commands, environment promotion strategy (dev → staging → production), rollback procedures
- [ ] T087 [P] Create .gitignore in repository root with entries: **/.terraform/, **/.terragrunt-cache/, **/*.tfstate, **/*.tfstate.*, **/*.tfvars (sensitive), **/*.tfplan, **/crash.log, **/override.tf, **/override.tf.json, **/.terraform.lock.hcl should be committed (remove from ignore if present)
- [ ] T088 [P] Update root README.md with infrastructure overview section: prerequisite infrastructure requirements (resource groups: navigator-dev-rg and navigator-prod-rg, state storage: navigator-tfstate-rg with navtfstatedev and navtfstateprod accounts), deployment strategy (manual via Terragrunt), links to terraform/env/*/README.md files
- [ ] T089 [P] Document manual post-deployment steps in root README.md: DNS name server configuration at domain registrar (use output from dns_zone_name_servers), secret population for injected secrets (OAuth, API keys), Azure Defender for Cloud configuration (optional)

### Final Validation

- [ ] T090 Run `cd terraform/env/dev && terragrunt plan -out=dev.tfplan` to generate final dev plan
- [ ] T091 Verify dev plan shows expected resources: VNet with 3 subnets, Container Apps Environment and App, PostgreSQL Flexible Server with database, Log Analytics Workspace, DNS zone, NSGs, private DNS zones, conditional resources based on variables (Key Vault only if use_key_vault=true, Application Insights only if enable_application_insights=true, etc.)
- [ ] T092 Run `cd terraform/env/production && terragrunt plan -out=prod.tfplan` to generate production plan
- [ ] T093 Verify production plan differences from dev: zone-redundant PostgreSQL HA, higher SKUs, Application Insights enabled, auto-shutdown disabled, different domain name, conditional resources match production variables
- [ ] T094 Final validation: Run `cd terraform/env/production && terragrunt validate` and confirm no errors
- [ ] T095 Document deployment command sequence in root README.md: (1) cd terraform/env/dev, (2) terragrunt plan, (3) terragrunt apply, (4) manual testing and validation, (5) cd terraform/env/production, (6) terragrunt plan, (7) terragrunt apply with explicit approval

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
- random_password resources MUST exist before being referenced in Key Vault secrets or Container Apps secrets
- Key Vault MUST exist before storing secrets (when use_key_vault=true)
- Container Apps Environment MUST exist before Container Apps
- PostgreSQL MUST exist before connection string generated and stored
- Managed identities MUST exist before RBAC role assignments
- Private DNS zones MUST exist before resources that use them (PostgreSQL, Key Vault private endpoints)

**Validation Checkpoints:**
- Run `terragrunt validate` after each tier completes (T011, T023, T056, T074, T077-T078)
- Run `terragrunt plan` before marking tier complete (T057, T075, T090, T092)
- Formatting checks (`terraform fmt`) in Polish phase (T076)
- Security scanning (Trivy) in Polish phase (T079-T080)

### Parallel Opportunities

**Within Same Tier:**
- Setup tier: versions.tf, provider.tf, variables.tf, outputs.tf, terragrunt configs (different files)
- Network tier: Private DNS zones, Service Endpoints configuration (independent resources)
- Compute tier: Key Vault setup, ACR creation, Storage Account (independent conditional resources)
- Application tier: Monitoring, DNS, Authentication configs (different files, no dependencies)
- Polish phase: Documentation tasks, security scanning, tagging (independent activities)

**Conditional Resource Handling:**
- Tasks for conditional resources (Key Vault, ACR, Storage, Application Insights, etc.) can run in parallel with other conditional resources
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
   - ❌ Storing secrets in Key Vault BEFORE Key Vault created
   - ❌ Assigning RBAC roles BEFORE managed identities exist
   - ❌ Using random_password in secrets BEFORE random_password resource created
   - ✅ Creating multiple independent Key Vault secrets (if parent vault exists)

3. **Cross-Tier Dependencies**:
   - ❌ Any Compute/Data tier task running before Network tier completes
   - ❌ Application tier DNS configuration before Container Apps exist
   - ❌ Monitoring configuration before resources to monitor exist
   - ✅ Within Network tier: NSGs, private DNS zones (if in different files)

4. **Sequential Configuration**:
   - ❌ Configuring PostgreSQL backup BEFORE PostgreSQL resource defined
   - ❌ Referencing secrets in Container Apps BEFORE secrets exist (random_password or Key Vault)
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
- **random_password → Secrets**: Create random_password before using in Key Vault secrets or Container Apps secrets
- **Managed Identity → RBAC**: Create managed identity before assigning roles
- **Key Vault → RBAC → Secrets**: Create Key Vault, assign RBAC roles, then store secrets
- **Container Apps Environment → Container App**: Environment must exist before apps
- **PostgreSQL → Connection String Storage**: Database must exist before connection string generated

**Rule of Thumb**: If task B needs output/ID from task A, they CANNOT be parallel. Mark task B without [P] and ensure it comes after task A in the sequence.

---

## Implementation Strategy

### Tier-by-Tier Code Generation

1. Complete Phase 1: Setup (create versions.tf, provider.tf, variables.tf, outputs.tf, terragrunt.hcl files)
2. Complete Phase 2: Network Tier (create vnet.tf, security.tf, dns-private.tf, identity.tf skeleton)
3. **VALIDATE**: Run `terragrunt validate` to verify configuration syntax
4. Complete Phase 3: Compute & Data Tier (create secrets.tf, keyvault.tf, postgresql.tf, container-apps.tf, acr.tf, storage.tf)
5. **VALIDATE**: Run `terragrunt validate` after compute tier
6. Complete Phase 4: Application Tier (create dns.tf, monitoring.tf, alerts.tf, auth-*.tf)
7. **VALIDATE**: Run `terragrunt validate` after application tier
8. Complete Phase 5: Polish (formatting, documentation, security scanning, final validation)
9. Final validation with `terragrunt validate` and `terragrunt plan`

**Note**: Implementation generates IaC code files only. Actual infrastructure deployment (terragrunt apply) is outside the scope of this task framework and requires manual execution per deployment strategy.

### Parallel Code Generation

When multiple team members work on IaC code:

1. Complete Setup + Network together (foundation files)
2. Once Network tier files complete, parallelize within tiers:
   - Team member A: Container Apps infrastructure (container-apps.tf, acr.tf)
   - Team member B: Database and secrets (postgresql.tf, secrets.tf, keyvault.tf)
   - Team member C: Storage and monitoring (storage.tf, monitoring.tf, alerts.tf)
3. Validate at tier boundaries before proceeding to next tier
4. Application tier can be parallelized across DNS, monitoring, authentication

---

## Environment Promotion Strategy

### Configuration Differences (Terragrunt inputs)

**Development Environment** (`terraform/env/dev/terragrunt.hcl`):
- `use_key_vault = false` (direct Container Apps secrets)
- `container_cpu = 0.25`, `container_memory = "0.5Gi"`
- `min_replicas = 0` (scale to zero), `max_replicas = 2`
- `postgres_sku = "B_Standard_B1ms"`, `postgres_storage_gb = 32`
- `postgres_ha_enabled = false` (single-zone)
- `backup_retention_days = 7`
- `enable_application_insights = false` (basic monitoring only)
- `enable_auto_shutdown = true` (evenings/weekends cost savings)
- `enable_zone_redundancy = false`
- `domain_name = "navigator-dev.cdssandbox.xyz"`
- `enable_outbound_internet = true`
- `create_google_auth = false`, `create_azure_ad_b2c = true`
- `create_azure_openai = false`, `create_storage_account = false` (optional)

**Production Environment** (`terraform/env/production/terragrunt.hcl`):
- `use_key_vault = false` (default, enable if GC compliance requires)
- `container_cpu = 0.5`, `container_memory = "1.0Gi"`
- `min_replicas = 1`, `max_replicas = 10`
- `postgres_sku = "GP_Standard_D2s_v3"`, `postgres_storage_gb = 128`
- `postgres_ha_enabled = true` (zone-redundant HA)
- `backup_retention_days = 14`
- `enable_application_insights = true` (APM and distributed tracing)
- `enable_auto_shutdown = false`
- `enable_zone_redundancy = true`
- `domain_name = "valentine.cds-snc.ca"`
- `enable_outbound_internet = true`
- `create_google_auth = true`, `create_azure_ad_b2c = false`
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
   - Populate injected secrets (OAuth credentials, API keys) if applicable
   - Configure Azure Defender for Cloud (optional, post-deployment manual configuration)

---

## Notes

- [P] tasks = different files, no dependencies within same tier
- Tasks organized by infrastructure tier following dependency hierarchy
- Run `terragrunt validate` at tier boundaries to catch syntax errors early (T011, T023, T056, T074, T077-T078)
- Run `terragrunt plan` before marking major tiers complete (T057, T075, T090, T092)
- Commit after each tier or logical group of resources
- Stop at checkpoints to validate configuration
- All paths relative to repository root
- Terragrunt orchestration enables configuration-driven environment promotion
- No infrastructure code changes required to promote dev → production (configuration-only differences)

### Key Vault Modes

**Mode A: Direct Secret Injection** (use_key_vault=false, DEFAULT)
- Auto-generated secrets: random_password resources → Terraform state → Container Apps secrets
- Injected secrets: Terraform input variables → Container Apps secrets
- Cost: $0, Simplicity: High, Rotation: Re-run terragrunt apply

**Mode B: Key Vault Integration** (use_key_vault=true, OPTIONAL)
- Auto-generated secrets: random_password resources → Key Vault → Container Apps secret references
- Injected secrets: Terraform input variables → Key Vault → Container Apps secret references
- Cost: ~$2-5/month, Complexity: Medium, Rotation: Update Key Vault → restart app

### Conditional Resources

Resources created only when feature flag enabled (using `count` expressions):
- **Key Vault**: `count = var.use_key_vault ? 1 : 0`
- **Application Insights**: `count = var.enable_application_insights ? 1 : 0`
- **Auto-shutdown schedules**: `count = var.enable_auto_shutdown ? 1 : 0`
- **Azure Container Registry**: `count = var.create_acr ? 1 : 0`
- **Storage Account**: `count = var.create_storage_account ? 1 : 0`
- **Google OAuth**: `count = var.create_google_auth ? 1 : 0`
- **Azure AD B2C**: `count = var.create_azure_ad_b2c ? 1 : 0`
- **Azure OpenAI**: `count = var.create_azure_openai ? 1 : 0`
- **NAT Gateway**: `count = var.create_nat_gateway ? 1 : 0`

---

## Task Summary

**Total Tasks**: 95

**Task Count by Phase**:
- Phase 1 (Setup): 11 tasks
- Phase 2 (Network Tier): 12 tasks
- Phase 3 (Compute & Data Tier): 34 tasks
- Phase 4 (Application Tier): 18 tasks
- Phase 5 (Polish): 20 tasks

**Parallel Opportunities Identified**: 48 tasks marked [P] can run in parallel within their respective phases

**Validation Checkpoints**: 8 checkpoints (T011 Setup, T023 Network, T056-T057 Compute/Data, T074-T075 Application, T077-T078 Polish, T090-T094 Final)

**Environment Order**: dev → production (manual deployment via terragrunt commands)

**Format Validation**: ✅ All tasks follow checklist format (checkbox, ID, [P] marker where applicable, file paths)

**Conditional Resources**: 9 feature flags controlling optional infrastructure components

**Secret Management**: Dual-mode implementation (direct Container Apps secrets vs Key Vault integration)
