<!--
SYNC IMPACT REPORT
==================
Version Change: 1.0.0 → 2.0.0
Date: 2026-01-14

Changes:
- NEW: Favor Managed Services (Architecture Principle 1) [v1.1.0]
- REMOVED: Progressive Environment Complexity (Implementation Approach) [v1.1.0]
- REORDERED: Existing Architecture Principles renumbered (Simplicity → #2, Reliability → #3, Cost → #4) [v1.1.0]
- UPDATED: Configuration-Driven Environment Strategy - adopted valentine-terraform approach [v1.1.1]
- REDEFINED: Leverage Verified Modules → Prefer Resource Simplicity (BREAKING CHANGE) [v2.0.0]

Template Consistency Status:
- ✅ plan-template.md: No changes required - Principles Check already accommodates principles
- ✅ spec-template.md: No changes required (technology-agnostic requirements)
- ✅ tasks-template.md: No changes required - Task phases align with principles
- ✅ IAC command files: No changes required

Follow-up TODOs: None

Rationale for version 2.0.0 (MAJOR):
- BREAKING: Fundamentally reversed IaC Code Principle from "prefer modules" to "prefer direct resources"
- This is backward incompatible guidance - existing infrastructure following v1.x "module-first" approach
  will conflict with new "resource-first" principle
- Migration guidance: Review existing module usage and consider replacing with direct azurerm resources
  where module abstraction adds unnecessary complexity
-->

# Navigator Azure Infrastructure Principles

## Cloud Architecture Principles

### Favor Managed Services

Infrastructure must prioritize Azure-managed services over self-managed alternatives to
reduce operational overhead, improve security posture, and accelerate delivery. Managed
services provide built-in availability, automated patching, compliance certifications,
and Azure's operational expertise, allowing the team to focus on application value rather
than infrastructure maintenance.

**Baseline (Dev)**: Use Azure-managed services for all core infrastructure components.
Deploy Azure App Service for compute (eliminates server management), Azure Database for
PostgreSQL (automated backups, patching), and Azure Storage Account (built-in redundancy).
Avoid self-managed VMs, container orchestration clusters, or database installations.
Accept default managed service configurations to minimize complexity.

**Enhanced (Staging/Production)**: Leverage advanced managed service capabilities.
Enable zone-redundant deployments for App Service and PostgreSQL to achieve high
availability without managing replication. Use Azure Key Vault for secrets management,
Azure Monitor and Application Insights for observability, and Azure Front Door or
Application Gateway for traffic management. Integrate Azure-managed security services
(Microsoft Defender for Cloud, Azure Policy) for compliance and threat protection.
Prefer managed service features (auto-scaling, automated failover, managed backups)
over custom implementations.

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

### Prefer Resource Simplicity

Infrastructure code must prioritize clarity and maintainability through direct resource
definitions over module abstractions. For Navigator's focused Azure deployment, direct
azurerm resources provide transparency, reduce indirection, and simplify debugging
compared to wrapped module interfaces that obscure configuration details.

Use direct azurerm resource blocks as the default approach (azurerm_app_service,
azurerm_postgresql_flexible_server, azurerm_virtual_network, azurerm_storage_account).
Resource blocks make configuration explicit, enable straightforward troubleshooting, and
avoid module version management overhead. Reserve modules for scenarios where direct
resources genuinely don't fit: (1) complex multi-resource patterns requiring validated
composition (e.g., verified VPC modules with 10+ interdependent resources), (2)
organizational standards mandating specific module usage, or (3) patterns requiring
cross-resource validation logic impossible with individual resources.

When modules are necessary, prefer Azure Verified Modules with exact version pinning
(= X.Y.Z) and comprehensive documentation. Avoid module proliferation - every module
adds abstraction layers requiring additional cognitive load to understand actual
infrastructure configuration.

**Progressive Application**: Baseline environments use direct resources exclusively for
maximum simplicity and learning. Enhanced environments may introduce verified modules
only when managing complex patterns (e.g., enterprise networking with 20+ subnets,
security groups, and route tables) where module abstraction reduces error-prone
repetition.

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

### Configuration-Driven Environment Strategy

Infrastructure code maintains DRY principles through a shared Terraform module deployed
across environments via Terragrunt orchestration. This approach, based on the
valentine-terraform reference architecture, enables environment-specific configuration
while avoiding code duplication and maintaining consistency.

**Module Structure**: Create a shared Terraform module under `terraform/azure/` containing
all infrastructure definitions (provider.tf, variables.tf, app-service.tf, postgresql.tf,
vnet.tf, monitoring.tf, etc.). Use Terragrunt configuration files in
`terraform/env/{dev,staging,production}/terragrunt.hcl` that reference the shared module
via `source = "../..//azure"`. Each environment's Terragrunt file contains
environment-specific inputs parameterizing resource sizing, feature enablement, and
deployment configuration.

**Environment Parameterization**: Use Terragrunt `inputs` block to control differences:
resource SKUs (app_service_sku, postgres_sku), scaling limits (min_instances,
max_instances), feature flags (create_application_insights, enable_auto_shutdown,
enable_zone_redundancy), backup retention (backup_retention_days), domain names, and
billing codes. Implement conditional resource creation in the shared module using count
expressions (e.g., `count = var.create_application_insights ? 1 : 0`) allowing
development environments to skip expensive features while production enables comprehensive
capabilities.

**State Isolation**: Terragrunt auto-generates separate Azure Storage Account backends per
environment. Configure remote_state with unique container names (navigator-dev-tf,
navigator-staging-tf, navigator-prod-tf), encryption enabled, and environment-specific
tags for cost attribution. Each environment manages independent state preventing
cross-environment interference while maintaining identical infrastructure patterns.

**Deployment Strategy**: Validate changes in dev environment first, then promote to
staging for production-like validation, finally deploy to production. Use consistent
resource naming with environment prefixes (nav-dev-app-service, nav-prod-postgres). Tag
all resources with environment, project, and cost-center for Azure Cost Management
tracking. Integrate GitHub Actions workflows with Azure OIDC authentication (Federated
Identity Credentials) eliminating static credentials - dev/staging auto-deploy on merge
to main, production deploys only on release publication providing controlled promotion.

## Governance

**Authority and Precedence**: These principles govern all infrastructure development for
the Navigator Azure deployment. They reflect the project requirements for a Government
of Canada internal tool balancing security, reliability, cost efficiency, and simplicity.
When architectural decisions conflict, these principles guide the resolution. The "Favor
Managed Services" principle takes precedence over self-managed alternatives unless
managed services demonstrably cannot meet technical or compliance requirements.

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
justification: self-managed infrastructure instead of Azure-managed services (document
why managed services cannot meet requirements), multi-region deployment (adds significant
cost and complexity), Premium tier services (ensure value justifies cost), custom modules
instead of verified modules (document why community solutions insufficient).

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

**Version**: 2.0.0 | **Ratified**: 2026-01-14 | **Last Amended**: 2026-01-14
