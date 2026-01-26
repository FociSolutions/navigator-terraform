# Tasks: Internal Container Apps with Application Gateway

**Input**: Design documents from `/specs/002-internal-ca-appgw/`
**Prerequisites**: plan.md, spec.md, research.md, architecture.md, modules.md, quickstart.md

**Organization**: Tasks grouped by infrastructure tier following dependency hierarchy (Foundation → Network → Compute/Data → Application)

## Format: `[ID] [P?] Description`

- **[ID]**: Sequential task number (T001, T002, T003...)
- **[P]**: Can run in parallel (different files, no dependencies) - optional
- **Description**: Clear action with exact file path included

---

## Phase 1: Setup

**Purpose**: Provider configuration and variable setup for Application Gateway and ACME integration

- [X] T001 [P] Add ACME provider version constraint to terraform/azure/versions.tf (~> 2.43)
- [X] T002 [P] Configure ACME provider in terraform/azure/provider.tf with server_url variable
- [X] T003 [P] Add Application Gateway variables to terraform/azure/variables.tf (appgw_sku_name, appgw_tier, appgw_capacity_min, appgw_capacity_max)
- [X] T004 [P] Add WAF variables to terraform/azure/variables.tf (enable_waf, waf_mode)
- [X] T005 [P] Add ACME variables to terraform/azure/variables.tf (acme_server_url, acme_email_address)
- [X] T006 [P] Add feature flag variables to terraform/azure/variables.tf (enable_zone_redundancy, enable_http_redirect)
- [X] T007 [P] Add Application Gateway naming to terraform/azure/locals.tf (appgw_name, appgw_pip_name)
- [X] T008 Run `terraform fmt` and `terraform validate` - setup checkpoint

---

## Phase 2: Network Tier

**Purpose**: Network infrastructure changes - subnet expansion, NSG rules, Private DNS

**⚠️ CRITICAL**: Network tier MUST complete before Application Gateway can be provisioned

- [X] T009 Modify Container Apps subnet size in terraform/azure/vnet.tf (10.240.1.0/24 → 10.240.1.0/23)
- [X] T010 [P] Add NSG rule in terraform/azure/security.tf (AllowAppGatewayHttps: 10.240.3.0/24 → 10.240.1.0/23:443)
- [X] T011 [P] Create Private DNS zone in terraform/azure/dns-private.tf (Container Apps environment default domain)
- [X] T012 [P] Create virtual network link in terraform/azure/dns-private.tf (link Private DNS zone to VNet)
- [X] T013 [P] Create wildcard A record in terraform/azure/dns-private.tf (* → Container Apps static IP)
- [X] T014 [P] Create root A record in terraform/azure/dns-private.tf (@ → Container Apps static IP)
- [X] T015 Run `terraform validate` - network tier checkpoint

**Checkpoint**: Network tier complete - Application Gateway can now be provisioned

---

## Phase 3: Compute & Data Tier

**Purpose**: Application Gateway, ACME certificates, and Container Apps ingress modifications

**Dependencies**: Requires Network Tier (Phase 2) to be complete

### Application Gateway Resources

- [X] T016 Create Application Gateway public IP in terraform/azure/app-gateway.tf (Standard SKU, static, zone-redundant conditional)
- [X] T017 Create Application Gateway resource in terraform/azure/app-gateway.tf (Standard_v2 SKU, frontend IP config)
- [X] T018 [P] Configure HTTPS listener in terraform/azure/app-gateway.tf (port 443, TLS 1.2 policy, SSL certificate)
- [X] T019 [P] Configure HTTP listener in terraform/azure/app-gateway.tf (port 80, optional for redirect)
- [X] T020 [P] Create backend pool in terraform/azure/app-gateway.tf (Container Apps internal FQDN)
- [X] T021 [P] Configure backend HTTP settings in terraform/azure/app-gateway.tf (HTTPS, session affinity, 180s timeout, health probe)
- [X] T022 [P] Create health probe in terraform/azure/app-gateway.tf (HTTPS, path /, 30s interval, 3 unhealthy threshold)
- [X] T023 [P] Create HTTPS routing rule in terraform/azure/app-gateway.tf (listener → backend pool → HTTP settings)
- [X] T024 [P] Create HTTP→HTTPS redirect configuration in terraform/azure/app-gateway.tf (conditional on enable_http_redirect)
- [X] T025 [P] Create HTTP redirect routing rule in terraform/azure/app-gateway.tf (conditional on enable_http_redirect)

### ACME Certificate Resources

- [X] T026 [P] Create ACME account private key in terraform/azure/acme.tf (RSA 4096)
- [X] T027 [P] Create ACME account registration in terraform/azure/acme.tf (email_address variable)
- [X] T028 [P] Create ACME certificate resource in terraform/azure/acme.tf (conditional on domain_name, DNS-01 challenge, min_days_remaining=30)
- [X] T029 [P] Create certificate P12 password in terraform/azure/acme.tf (random_password 32 chars)
- [X] T030 [P] Add SSL certificate configuration to Application Gateway in terraform/azure/app-gateway.tf (conditional on domain_name)

### WAF Policy (Optional)

- [X] T031 [P] Create WAF policy resource in terraform/azure/app-gateway.tf (conditional on enable_waf, OWASP CRS 3.2)
- [X] T032 [P] Attach WAF policy to Application Gateway in terraform/azure/app-gateway.tf (conditional on enable_waf)

### Container Apps Modifications

- [X] T033 Modify Container Apps ingress in terraform/azure/container-apps.tf (external_enabled: true → false)

### DNS Modifications

- [X] T034 Modify DNS A record in terraform/azure/dns.tf (point to Application Gateway public IP instead of Container Apps)
- [X] T035 [P] Remove Container Apps TXT verification record in terraform/azure/dns.tf (azurerm_dns_txt_record.verification)
- [X] T036 [P] Remove Container Apps custom domain binding in terraform/azure/dns.tf (azurerm_container_app_custom_domain.main)
- [X] T037 [P] Remove Azure Managed Certificate in terraform/azure/dns.tf (azapi_resource.managed_certificate)
- [X] T038 [P] Remove certificate bind action in terraform/azure/dns.tf (azapi_resource_action.bind_certificate)
- [X] T039 [P] Remove certificate unbind action in terraform/azure/dns.tf (azapi_resource_action.unbind_certificate)

- [X] T040 Run `terraform validate` - compute/data tier checkpoint
- [ ] T041 Run `terraform plan` to preview changes

**Checkpoint**: Compute and data tier complete - outputs and Terragrunt configuration can now be finalized

---

## Phase 4: Application Tier

**Purpose**: Outputs, Terragrunt environment configurations, and documentation

**Dependencies**: Requires Compute & Data Tier (Phase 3) to be complete

### Terraform Outputs

- [X] T042 [P] Add Application Gateway outputs in terraform/azure/outputs.tf (appgw_public_ip, appgw_fqdn)
- [X] T043 [P] Add certificate outputs in terraform/azure/outputs.tf (certificate_expiry)
- [X] T044 [P] Add Private DNS outputs in terraform/azure/outputs.tf (private_dns_zone_name, container_apps_internal_fqdn)

### Terragrunt Environment Configurations

- [X] T045 [P] Update dev terragrunt.hcl in terraform/env/dev/terragrunt.hcl (Application Gateway and ACME inputs)
- [X] T046 [P] Update production terragrunt.hcl in terraform/env/production/terragrunt.hcl (Application Gateway and ACME inputs)

### Documentation Updates

- [ ] T047 Update README.md architecture section with Application Gateway details
- [ ] T048 Update README.md deployment workflow with custom domain DNS configuration steps
- [ ] T049 Update README.md troubleshooting section with Application Gateway and ACME troubleshooting
- [ ] T050 Update README.md outputs section with Application Gateway and certificate outputs
- [ ] T051 Update README.md security section with WAF and ACME certificate management

- [ ] T052 Run `terraform validate` - application tier checkpoint
- [ ] T053 Run `terraform plan -var-file=terraform.tfvars.dev` to preview dev environment changes

**Checkpoint**: Application tier complete - infrastructure ready for deployment validation

---

## Phase 5: Polish & Validation

**Purpose**: Final validation, formatting, security scanning, and deployment readiness

- [ ] T054 Run `terraform fmt -recursive` to format all .tf files
- [ ] T055 Run `terraform validate` across all configurations
- [ ] T056 [P] Run Trivy security scan on terraform/azure/ (trivy config terraform/azure/)
- [ ] T057 [P] Review Trivy findings and document expected exceptions (Application Gateway subnet without NSG, public IP)
- [ ] T058 [P] Verify resource naming follows conventions in terraform/azure/locals.tf
- [ ] T059 [P] Verify all sensitive variables marked as sensitive in terraform/azure/variables.tf
- [ ] T060 Run `terraform plan` for dev environment final validation
- [ ] T061 Cross-reference generated code with quickstart.md validation steps

---

## Dependencies & Execution Order

### Phase Dependencies

**Infrastructure Tiers - Dependency Chain:**
- **Phase 1: Setup**: No dependencies - can start immediately
- **Phase 2: Network Tier**: Depends on Setup - BLOCKS Application Gateway provisioning
- **Phase 3: Compute & Data Tier**: Depends on Network Tier - provisions Application Gateway, ACME certificates, modifies Container Apps
- **Phase 4: Application Tier**: Depends on Compute & Data Tier - finalizes outputs and Terragrunt configurations
- **Phase 5: Polish**: Depends on all infrastructure tiers being complete

### Critical Dependencies

**Network → Application Gateway:**
- Private DNS zone MUST be linked to VNet before Application Gateway can resolve Container Apps internal FQDN
- NSG rule MUST allow Application Gateway → Container Apps traffic
- Container Apps subnet MUST be expanded to /23 for VNet integration

**Application Gateway → Container Apps:**
- Application Gateway backend pool references Container Apps internal FQDN
- Container Apps internal ingress MUST be enabled (external_enabled = false)

**ACME Certificate → DNS Zone:**
- ACME DNS-01 challenge requires Azure DNS zone for TXT record creation
- Custom domain NS records MUST be updated at domain registrar before ACME validation

**DNS A Record → Application Gateway:**
- DNS A record MUST point to Application Gateway public IP (not Container Apps IP)

### Validation Checkpoints

- Run `terraform validate` after each tier completes (Phases 1, 2, 3, 4)
- Run `terraform plan` after Compute & Data tier and Application tier
- Run Trivy security scan in Polish phase
- Run `terraform fmt` in Polish phase

### Parallel Opportunities

**Within Setup Phase:**
- Variable files, locals, provider configurations can be created in parallel (different files)

**Within Network Tier:**
- NSG rules, Private DNS zone creation, and A records can run in parallel (different resources)

**Within Compute & Data Tier:**
- Application Gateway listeners, backend configuration, and health probes can be created in parallel (same file, different blocks)
- ACME resources can be created in parallel with WAF policy (different files)
- Container Apps modification and DNS modifications can run in parallel (different files)

**Within Application Tier:**
- Terragrunt environment configurations can be updated in parallel (different files)
- Documentation updates can run in parallel with output definitions (different files)

**Within Polish Phase:**
- Security scanning, naming verification, and sensitive variable verification can run in parallel

### When Tasks CANNOT Be Parallel

**CRITICAL: Tasks CANNOT run in parallel when:**

1. **Same File Modification**:
   - ❌ T009 (vnet.tf subnet modification) and another task modifying vnet.tf
   - ✅ T009 (vnet.tf) and T010 (security.tf) can run in parallel

2. **Resource Dependencies**:
   - ❌ T017 (Application Gateway) BEFORE T015 (network tier checkpoint)
   - ❌ T018-T025 (Application Gateway configuration) BEFORE T016 (Application Gateway resource)
   - ❌ T030 (SSL certificate config) BEFORE T028 (ACME certificate resource)

3. **Cross-Tier Dependencies**:
   - ❌ Any Phase 3 task running before Phase 2 completes
   - ❌ T042-T044 (outputs) before T016-T040 (resources they output)

4. **Sequential Configuration**:
   - ❌ T032 (attach WAF) BEFORE T031 (create WAF policy)
   - ❌ T034 (DNS A record modification) BEFORE T016 (Application Gateway public IP creation)

5. **Validation Checkpoints**:
   - ❌ Starting Phase 3 BEFORE T015 (network tier validation)
   - ❌ Running T041 (terraform plan) BEFORE T040 (terraform validate)

---

## Implementation Strategy

### Tier-by-Tier Code Generation

1. Complete Phase 1: Setup (providers, variables, locals)
2. Complete Phase 2: Network Tier (subnet, NSG, Private DNS)
3. **VALIDATE**: Run `terraform validate` (T015)
4. Complete Phase 3: Compute & Data Tier (Application Gateway, ACME, Container Apps modifications)
5. **VALIDATE**: Run `terraform validate` and `terraform plan` (T040-T041)
6. Complete Phase 4: Application Tier (outputs, Terragrunt configs, documentation)
7. **VALIDATE**: Run `terraform validate` and `terraform plan` (T052-T053)
8. Complete Phase 5: Polish (formatting, security scanning, final validation)
9. Final validation with `terraform validate`, `terraform plan`, and Trivy scan

### Parallel Code Generation

When multiple team members work on Terraform code:

1. Complete Setup + Network together (foundation files)
2. Once Network tier validation passes (T015), parallelize within Phase 3:
   - Team member A: Application Gateway resources (T016-T025)
   - Team member B: ACME certificate resources (T026-T030)
   - Team member C: Container Apps and DNS modifications (T033-T039)
3. Validate at tier boundaries before proceeding to next tier

---

## Notes

- [P] tasks = different files or independent resources, no dependencies within same tier
- Tasks organized by infrastructure tier following dependency hierarchy
- Run `terraform validate` at tier boundaries to catch syntax errors early
- Run `terraform plan` after major tiers complete to preview infrastructure changes
- Commit after each tier or logical group of resources
- Stop at checkpoints to validate configuration
- README.md updates included in Phase 4 (Application Tier) to document Application Gateway, ACME, and updated deployment workflow
- Custom domain DNS configuration requires two-step deployment (documented in README.md)
- ACME staging endpoint used for dev environment to avoid Let's Encrypt rate limits
- Certificate renewal automated via ACME provider (min_days_remaining=30)
