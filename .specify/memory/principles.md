<!--
SYNC IMPACT REPORT
==================
Version Change: UNVERSIONED → 1.0.0
Date: 2026-01-14

Principles Established:
- NEW: Design for Simplicity (Architecture Principle)
- NEW: Design for Reliability and Resilience (Architecture Principle)
- NEW: Optimize for Cost (Architecture Principle)
- NEW: Leverage Verified Modules (IaC Code Principle)
- NEW: Validate During Development (IaC Code Principle)
- NEW: Manage Secrets Securely (IaC Code Principle)
- NEW: Progressive Environment Complexity (Implementation Approach)
- NEW: Configuration-Driven Environment Strategy (Implementation Approach)

Template Consistency Status:
- ✅ plan-template.md: Reviewed - "Principles Check" section already accommodates configured principles
- ✅ spec-template.md: Reviewed - No changes required (technology-agnostic requirements)
- ✅ tasks-template.md: Reviewed - Task phases align with principle-driven approach
- ✅ No IAC command files found to update

Follow-up TODOs: None - all placeholders filled

Rationale for version 1.0.0:
- Initial principles establishment for Navigator Azure Terraform infrastructure
- Defines governance framework for single-environment deployment across dev/staging/prod
- Balances security, reliability, cost efficiency, and simplicity as specified
-->

# Navigator Azure Infrastructure Principles

## Cloud Architecture Principles

### Design for Simplicity

Phoenix LiveView applications deployed on Azure should prioritize architectural
simplicity to reduce operational overhead and accelerate iteration. For an internal
Government of Canada tool with a single codebase deployed across dev, staging, and
production environments, simplicity minimizes complexity that could introduce bugs,
increase costs, or slow development velocity.

**Baseline (Dev)**: Use single-zone deployments, minimal resource instances, and
default Azure service configurations. Deploy Azure App Service in Basic tier, Azure
Database for PostgreSQL in Burstable tier, and avoid unnecessary networking complexity.

**Enhanced (Staging/Production)**: Increase to zone-redundant deployments with Standard
tiers for App Service and General Purpose tiers for PostgreSQL. Add essential features
like auto-scaling and load balancing, but avoid over-engineering with multi-region
architectures or complex service meshes unless justified by specific requirements.

### Design for Reliability and Resilience

Infrastructure resilience must match business criticality while balancing cost
efficiency. For Navigator, an internal threat modeling tool, availability is important
but must be weighed against infrastructure complexity and cost. The single environment
approach requires reliability patterns that scale from development to production through
configuration.

**Baseline (Dev)**: Accept single-zone deployment with basic health checks. Tolerate
brief downtime for deployments and maintenance. Use Azure App Service deployment slots
for zero-downtime deployments when convenient.

**Enhanced (Staging/Production)**: Implement zone-redundant deployments across Azure
availability zones. Configure auto-scaling policies based on CPU and memory utilization
(scale out at 70% CPU). Enable automated backups for Azure Database for PostgreSQL with
7-day retention. Implement health checks for App Service and database connection
monitoring. Target basic availability (99.9%) appropriate for internal tools.

### Optimize for Cost

Government of Canada environments require careful cost management, balancing performance
requirements with fiscal responsibility. The single environment approach across dev,
staging, and production enables cost optimization through right-sizing and
environment-appropriate resource allocation.

**Baseline (Dev)**: Use smallest viable SKUs (App Service Basic B1, PostgreSQL Burstable
B1ms). Implement auto-shutdown schedules for development resources (evenings, weekends).
Disable expensive features like high-frequency backups, extensive monitoring, and
multi-zone redundancy.

**Enhanced (Staging/Production)**: Right-size based on actual usage patterns. Use
Standard tier for App Service and General Purpose tier for PostgreSQL. Leverage Azure
reservations for production resources with predictable workloads. Monitor costs through
Azure Cost Management and establish budget alerts. Archive logs to cool storage after
30 days. Scale down staging environment during non-business hours while maintaining
production availability.

## IaC Code Principles

### Leverage Verified Modules

Infrastructure code should reuse verified, community-maintained modules to accelerate
development and reduce errors. For Azure Terraform deployments, verified modules provide
tested patterns that follow Azure best practices and security standards.

Use Azure Verified Modules (AVM) from the terraform-azurerm-* namespace for core
infrastructure (virtual networks, resource groups, App Service, PostgreSQL). Pin module
versions using exact version constraints (= X.Y.Z) since modules are not captured in
.terraform.lock.hcl. Prefer official modules over custom resources for standard
infrastructure patterns. Only build custom modules when organizational requirements
diverge significantly from community patterns.

**Progressive Application**: Start with verified modules in Baseline environments to
establish patterns. Extend with custom configuration in Enhanced environments only when
necessary to meet specific requirements.

### Validate During Development

Infrastructure code must be validated early and continuously to catch errors before
deployment. Validation reduces feedback cycles, prevents costly mistakes, and maintains
code quality across the team.

Use `terraform validate` to check syntax and configuration correctness after each file
modification. Run `terraform plan` at tier boundaries (network complete, compute
complete) to preview changes before proceeding. Integrate Checkov or tfsec for security
scanning to catch misconfigurations (exposed storage accounts, missing encryption,
overly permissive network rules). Format code with `terraform fmt` to maintain
consistency. Validate in development environments before promoting configurations to
staging and production.

**Progressive Application**: Baseline environments require syntax validation and plan
review. Enhanced environments add security scanning, cost estimation with Infracost, and
automated validation in CI/CD pipelines.

### Manage Secrets Securely

Secrets and sensitive configuration must never be hardcoded in infrastructure code or
committed to version control. Azure Key Vault provides centralized secret management
with access controls and audit logging.

Store database passwords, API keys, and connection strings in Azure Key Vault. Reference
secrets in Terraform using azurerm_key_vault_secret data sources rather than hardcoding
values. Use Azure Managed Identities for App Service to access Key Vault without storing
credentials. Never commit .tfvars files containing secrets to git - use .gitignore to
exclude terraform.tfvars files and document required variables in README.md. For local
development, use environment variables or terraform.tfvars.local (gitignored).

**Progressive Application**: Baseline environments require no hardcoded credentials and
basic Key Vault usage. Enhanced environments add Managed Identities, secret rotation
policies, and audit logging for secret access.

## Implementation Approaches

### Progressive Environment Complexity

The single-codebase, multi-environment approach requires infrastructure complexity to
scale progressively from development through production. Configuration-driven decisions
determine which features activate in each environment, avoiding separate codebases while
maintaining appropriate controls.

**Development**: Optimize for speed and simplicity. Use Basic B1 App Service, Burstable
B1ms PostgreSQL, single-zone deployment in Canada Central. Implement auto-shutdown
schedules (weeknights, weekends). Skip expensive monitoring, extensive backups, and
multi-zone redundancy. Accept brief downtime for deployments. Use local Terraform state
for solo development or shared Azure Storage Account with state locking for team
collaboration.

**Staging**: Mirror production architecture to validate operational patterns. Use
Standard S1 App Service, General Purpose GP_Gen5_2 PostgreSQL, zone-redundant deployment
across Canada Central availability zones. Implement production-like auto-scaling,
monitoring with Azure Monitor, and daily backups with 7-day retention. Use shared Azure
Storage Account backend with state locking. Scale down during off-hours to optimize
costs.

**Production**: Balance reliability with cost efficiency for internal tool usage. Use
Standard S2 App Service with auto-scaling (2-10 instances), General Purpose GP_Gen5_4
PostgreSQL with zone redundancy, daily backups with 30-day retention. Configure
Application Insights for monitoring and alerting. Use Azure Storage Account backend with
versioning and encryption. Target 99.9% availability (basic availability tier).

### Configuration-Driven Environment Strategy

A single Terraform codebase deploys across all environments using variable files to
control resource sizing, feature enablement, and cost/complexity trade-offs. This
approach maintains consistency while enabling environment-appropriate architecture.

Create separate variable files: terraform.tfvars.dev, terraform.tfvars.staging,
terraform.tfvars.prod. Parameterize resource SKUs (app_service_sku, postgres_sku), scaling
limits (min_instances, max_instances), feature flags (enable_auto_shutdown,
enable_multi_zone), and backup retention (backup_retention_days). Use Terraform
workspaces (terraform workspace select dev/staging/prod) to isolate state files while
sharing code.

Deploy to environments sequentially: validate in dev → promote to staging → deploy to
production. Use consistent resource naming with environment prefixes
(nav-dev-app-service, nav-prod-postgres). Tag all resources with environment, project,
and cost-center for Azure Cost Management tracking.

## Governance

**Authority and Precedence**: These principles govern all infrastructure development for
the Navigator Azure deployment. They reflect the project requirements for a Government
of Canada internal tool balancing security, reliability, cost efficiency, and simplicity.
When architectural decisions conflict, these principles guide the resolution.

**Compliance and Accountability**: All infrastructure specifications, plans, and
Terraform code must demonstrate alignment with these principles. Code reviews verify
compliance with security practices (no hardcoded secrets, proper network isolation) and
cost optimization (appropriate SKUs, auto-shutdown schedules for dev). Automated
validation through terraform validate, security scanning, and cost estimation enforces
ongoing compliance.

**Justification for Complexity**: Architectural decisions extending beyond Baseline
patterns require documented justification. Development environments prioritize simplicity
and cost efficiency. Staging mirrors production to validate operational patterns.
Production justifies added complexity (zone redundancy, comprehensive monitoring) with
internal tool reliability requirements and user impact.

**Deviation and Exception Process**: Deviations from these principles require explicit
acknowledgment and documented rationale in the architecture plan. Examples requiring
justification: multi-region deployment (adds significant cost and complexity), Premium
tier services (ensure value justifies cost), custom modules instead of verified modules
(document why community solutions insufficient).

**Amendment and Evolution**: These principles evolve as the Navigator application
matures, Azure capabilities change, or Government of Canada requirements shift.
Amendments follow semantic versioning (MAJOR for breaking governance changes, MINOR for
new principles, PATCH for clarifications). Principle updates require review of existing
infrastructure and migration guidance when changes impact deployed resources.

**Relationship to Operational Guidance**: These principles establish WHAT outcomes the
infrastructure achieves and WHY they matter for the Navigator Azure deployment.
Operational documentation (deployment runbooks, troubleshooting guides) addresses
day-to-day HOW. Principles remain stable as foundational governance; operational guidance
adapts more frequently to tooling updates and process improvements.

**Version**: 1.0.0 | **Ratified**: 2026-01-14 | **Last Amended**: 2026-01-14
