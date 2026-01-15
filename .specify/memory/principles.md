<!--
SYNC IMPACT REPORT
==================
Version Change: 2.1.0 → 3.0.0
Date: 2026-01-15

Changes:
- MERGED: "Favor Managed Services" + "Enforce Cloud Service Hierarchy" → "Prefer Managed Services" (BREAKING) [v3.0.0]
- MERGED: "Validate During Development" + "Design for Continuous Deployment" → "Automate Validation and Deployment" (BREAKING) [v3.0.0]
- UPDATED: All principles now cloud-agnostic (generic service types instead of Azure-specific names)
- UPDATED: Implementation Approaches - condensed and generalized for any cloud provider
- CONDENSED: Governance section - removed redundant language, consolidated deviation/justification guidance
- REMOVED: Duplicate content across principles (zero-downtime mentioned in multiple places)

Template Consistency Status:
- ✅ plan-template.md: No changes required - Principles Check accommodates consolidated principles
- ✅ spec-template.md: No changes required (technology-agnostic requirements)
- ✅ tasks-template.md: No changes required - Task phases align with principles
- ✅ IAC command files: No changes required

Follow-up TODOs: None

Rationale for version 3.0.0 (MAJOR):
- BREAKING: Removed two principles through consolidation (5 arch + 4 code → 4 arch + 3 code)
- Fundamental restructuring - merged overlapping principles that address same outcomes
- Backward incompatible - references to "Enforce Cloud Service Hierarchy" or "Design for Continuous Deployment" 
  as distinct principles will no longer resolve
- Migration guidance: Principle intent preserved but consolidated - no infrastructure changes needed
-->

# Navigator Infrastructure Principles

## Architecture Principles

### Prefer Managed Services

Infrastructure must prioritize fully-managed platform services (PaaS/SaaS) over
self-managed infrastructure (IaaS) to reduce operational overhead, improve security
posture, and accelerate delivery. Follow the service hierarchy: Software as a Service
first, Platform as a Service second, Infrastructure as a Service only when higher-level
services cannot meet requirements. Managed services provide built-in availability,
automated patching, and compliance certifications, allowing teams to focus on
application value rather than infrastructure maintenance.

**Baseline (Dev)**: Use managed platform services for all core components: managed
compute (eliminates server management), managed databases (automated backups, patching),
and managed storage (built-in redundancy). Avoid self-managed virtual machines,
container orchestration, or database installations. Accept default service
configurations to minimize complexity. Evaluate SaaS offerings for auxiliary functions
before building custom solutions.

**Enhanced (Staging/Production)**: Leverage advanced managed service capabilities:
zone-redundant deployments for high availability, managed secrets storage, managed
observability platforms, and managed security services. Prefer managed service features
(auto-scaling, automated failover) over custom implementations. Reserve self-managed
infrastructure only for specific requirements that managed services cannot satisfy.
Require documented rationale for any self-managed infrastructure adoption.

### Design for Simplicity

Infrastructure should prioritize architectural simplicity to reduce operational overhead
and accelerate iteration. For an internal Government of Canada tool with a single
codebase deployed across dev, staging, and production environments, simplicity minimizes
complexity that could introduce bugs, increase costs, or slow development velocity.

**Baseline (Dev)**: Use single-zone deployments, minimal resource instances, and default
service configurations. Deploy entry-level service tiers and avoid unnecessary
networking complexity.

**Enhanced (Staging/Production)**: Increase to zone-redundant deployments with
production-grade service tiers. Add essential features like auto-scaling and load
balancing, but avoid over-engineering with multi-region architectures or complex service
meshes unless justified by specific requirements.

### Design for Reliability and Resilience

Infrastructure resilience must match business criticality while balancing cost
efficiency. For Navigator, an internal threat modeling tool, availability is important
but must be weighed against infrastructure complexity and cost. Design systems to assume
failure will happen, handle errors gracefully through distributed architecture patterns,
and support zero-downtime deployments for both planned and unplanned maintenance.

**Baseline (Dev)**: Accept single-zone deployment with basic health checks. Implement
graceful degradation for non-critical features. Use deployment mechanisms supporting
zero-downtime when convenient. Design applications to handle transient failures with
retry logic and connection pooling.

**Enhanced (Staging/Production)**: Implement zone-redundant deployments using
distributed architecture patterns. Configure auto-scaling policies based on resource
utilization. Enable automated backups with appropriate retention. Implement
comprehensive health checks and connection monitoring. Use blue-green or canary
deployment patterns for zero-downtime production releases. Monitor performance and
behavior actively. Target appropriate availability (99.9%) for internal tools.

### Optimize for Cost

Government of Canada environments require careful cost management, balancing performance
requirements with fiscal responsibility. The environment-based approach enables cost
optimization through right-sizing and environment-appropriate resource allocation.

**Baseline (Dev)**: Use smallest viable service tiers. Implement auto-shutdown schedules
for development resources (evenings, weekends). Disable expensive features like
high-frequency backups, extensive monitoring, and multi-zone redundancy.

**Enhanced (Staging/Production)**: Right-size based on actual usage patterns. Use
appropriate production service tiers. Leverage reserved capacity for resources with
predictable workloads. Monitor costs and establish budget alerts. Archive logs to
cheaper storage tiers after retention periods. Scale down non-production environments
during non-business hours while maintaining production availability.

## IaC Code Principles

### Prefer Resource Simplicity

Infrastructure code must prioritize clarity and maintainability through direct resource
definitions over module abstractions. Direct resources provide transparency, reduce
indirection, and simplify debugging compared to wrapped module interfaces that obscure
configuration details.

Use direct resource blocks as the default approach. Resource blocks make configuration
explicit, enable straightforward troubleshooting, and avoid module version management
overhead. Reserve modules for scenarios where direct resources genuinely don't fit:
(1) complex multi-resource patterns requiring validated composition, (2) organizational
standards mandating specific module usage, or (3) patterns requiring cross-resource
validation logic impossible with individual resources.

When modules are necessary, prefer verified modules from cloud provider registries with
exact version pinning and comprehensive documentation. Avoid module proliferation -
every module adds abstraction layers requiring additional cognitive load.

**Progressive Application**: Baseline environments use direct resources exclusively for
maximum simplicity and learning. Enhanced environments may introduce verified modules
only when managing complex patterns where module abstraction reduces error-prone
repetition.

### Automate Validation and Deployment

Infrastructure code must be validated early and continuously through automated testing
and deployment pipelines. Treat infrastructure as code subject to the same quality gates
as application code. Support continuous integration and continuous deployment practices
enabling rapid, safe delivery of infrastructure changes with zero-downtime deployments
for planned maintenance.

Use validation tooling to check syntax and configuration correctness after each
modification. Run preview/plan commands at tier boundaries to review changes before
proceeding. Integrate security scanning to catch misconfigurations (exposed resources,
missing encryption, overly permissive rules). Format code automatically to maintain
consistency. Structure code to enable incremental changes without full rebuilds. Use
lifecycle controls to prevent accidental resource destruction. Tag resources with
version metadata for rollback capability. Separate state per environment preventing
cross-environment changes.

**Progressive Application**: Baseline environments require syntax validation, plan
review, and basic CI checks (validate, format). Enhanced environments implement full
CI/CD automation with automated plan generation on pull requests, security scanning
gates, cost estimation, approval workflows, and automated deployment to non-production
environments. Production deployments require manual approval after automated validation.

### Manage Secrets Securely

Secrets and sensitive configuration must never be hardcoded in infrastructure code or
committed to version control. Use managed secret storage services with access controls
and audit logging. Perform threat modeling during design to minimize attack surface by
limiting services exposed and information exchanged. Design secure interconnections
through secure APIs and managed connectivity.

Store credentials and keys in managed secret storage. Reference secrets via data sources
rather than hardcoding. Use platform-managed identities to access secrets without
storing credentials. Never commit variable files containing secrets - use ignore files
and document required variables. Apply proportionate security measures protecting data
at rest and in transit. Enforce secure protocols (HTTPS, TLS 1.2+) for all
communications.

**Progressive Application**: Baseline environments require no hardcoded credentials and
basic secret storage usage. Enhanced environments add managed identities, secret
rotation policies, audit logging for secret access, and threat modeling documentation.

## Implementation Approaches

### Configuration-Driven Environment Strategy

Infrastructure code maintains DRY principles through a shared module deployed across
environments with environment-specific configuration. This approach enables
parameterization while avoiding duplication and maintaining consistency.

**Module Structure**: Create a shared module containing all infrastructure definitions
(provider, variables, resources). Use orchestration configuration files per environment
that reference the shared module and provide environment-specific inputs for resource
sizing, feature enablement, and deployment configuration.

**Environment Parameterization**: Use configuration inputs to control differences:
service tiers, scaling limits, feature flags (observability, auto-shutdown, redundancy),
backup retention, and cost attribution. Implement conditional resource creation allowing
development environments to skip expensive features while production enables full
capabilities.

**State Isolation**: Use separate state storage per environment with encryption enabled
and environment-specific metadata. Each environment manages independent state preventing
cross-environment interference while maintaining identical infrastructure patterns.

**Deployment Strategy**: Validate changes in dev first, promote to staging for
production-like validation, then deploy to production. Use consistent naming with
environment prefixes. Tag all resources with environment, project, and cost-center.
Integrate CI/CD workflows with secure authentication eliminating static credentials -
dev/staging auto-deploy on merge, production deploys only on release providing
controlled promotion.

## Governance

**Authority and Precedence**: These principles govern all infrastructure development for
Navigator. They reflect requirements for a Government of Canada internal tool balancing
security, reliability, cost efficiency, and simplicity. When architectural decisions
conflict, these principles guide resolution. The "Prefer Managed Services" principle
takes precedence over self-managed alternatives unless managed services demonstrably
cannot meet technical or compliance requirements.

**Compliance and Accountability**: All infrastructure specifications, plans, and code
must demonstrate alignment with these principles. Reviews verify compliance with
security practices (no hardcoded secrets, proper isolation, threat modeling) and cost
optimization (appropriate tiers, auto-shutdown schedules). Automated validation through
syntax checking, security scanning, and cost estimation enforces ongoing compliance.
Infrastructure must align with applicable guidance from Canadian Centre for Cyber
Security IT Security Risk Management Framework (ITSG-22, ITSG-38).

**Security Operations**: Enable event logging per GC Event Logging Guidance. Monitor
systems to detect, prevent, and respond to attacks. Establish incident management plan
aligned with GC Cyber Security Event Management Plan (GC CSEMP). Report incidents to
Canadian Centre for Cyber Security. Implement patch management following GC Patch
Management Guidance. Enforce secure protocols for all connections.

**Deviation Process**: Deviations from principles require explicit acknowledgment and
documented rationale in architecture plans. Examples requiring justification:
self-managed infrastructure when managed services exist, premium service tiers,
multi-region deployment, or custom modules over verified modules. Development
environments prioritize simplicity and cost efficiency. Production justifies added
complexity with reliability requirements and user impact.

**Amendment and Evolution**: Principles evolve as the application matures, cloud
capabilities change, or government requirements shift. Amendments follow semantic
versioning (MAJOR for breaking governance changes, MINOR for new principles, PATCH for
clarifications). Updates require review of existing infrastructure and migration
guidance when changes impact deployed resources.

**Version**: 3.0.0 | **Ratified**: 2026-01-14 | **Last Amended**: 2026-01-15
