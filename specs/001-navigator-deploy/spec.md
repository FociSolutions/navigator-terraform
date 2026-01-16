# Infrastructure Specification: Navigator Threat Modeling Application

**Spec ID**: `001-navigator-deploy`
**Created**: January 14, 2026
**Status**: Draft
**Input**: User description: "I need to deploy the @navigator/ app. Start small with only the required bits."

## Executive Summary

This specification defines the minimal infrastructure requirements to deploy the Navigator threat modeling application. Navigator is an Elixir/Phoenix web application that provides real-time collaborative threat modeling with AI assistance. The infrastructure will support a small initial deployment suitable for dev/staging environments with capacity for 50-100 concurrent users.

## Problem Statement

### Current State

The Navigator application has an existing AWS deployment (reference architecture available at https://github.com/cds-snc/valentine-terraform/). This specification aims to create a new deployment in the Azure environment so that teams within the organization can use the threat modeling tool. Development is also done locally using docker-compose.

### Desired State

A deployed instance of Navigator accessible via the web, with proper database persistence, optional AI capabilities, and basic operational monitoring. The infrastructure should be simple to manage and cost-effective for initial deployment.

### Business Impact

**Benefits**: Enables teams within the organization to access Navigator for threat modeling in Azure environment, supports team collaboration across the organization, provides Azure-based deployment option alongside existing AWS infrastructure.

**Risks if not implemented**: Teams requiring Azure deployment cannot access the tool, limited to AWS-only deployment, reduced organizational flexibility in cloud platform choice.

## Infrastructure Requirements

### Functional Requirements

- **FR-001**: Infrastructure MUST provide container hosting to run the Navigator Phoenix application
- **FR-002**: Infrastructure MUST provide managed relational database compatible with PostgreSQL 13+ with persistent storage (implementation uses PostgreSQL 14.x to match AWS reference architecture)
- **FR-003**: Infrastructure MUST support TLS/HTTPS for secure web access
- **FR-004**: Infrastructure MUST provide secure storage for application secrets (database credentials, API keys, encryption keys)
- **FR-005**: Infrastructure MUST support secure environment variable configuration for runtime settings (DATABASE_URL, SECRET_KEY_BASE, OPENAI_API_KEY) via secrets management service
- **FR-006**: Infrastructure SHOULD support optional integration with OpenAI API or Azure OpenAI for AI features

### Non-Functional Requirements

#### Performance

- Support 50-100 concurrent users
- Web page load time < 2 seconds under normal load (50 concurrent users, 5 requests/second average)
- Database query response time p95 < 500ms

#### Availability

- Application availability target > 85% (dev environment; enhanced environments target 99.9%)
- Acceptable downtime: Up to 1-hour planned maintenance windows weekly for dev environment
- Single availability zone deployment acceptable for dev environment
- Backup strategy with daily snapshots retained for 14 days

#### Security

- TLS 1.2+ for all HTTPS communications
- Database accessible only from application compute resources via private endpoint (no public internet access)
- Secrets stored encrypted, not in application code or environment files
- Network isolation between public-facing and data tier components
- HTTPS enforcement (HTTP redirects to HTTPS)

#### Scalability

- Initial deployment: single application instance
- Database sized for up to 10GB expected data volume (provisioned storage: 32GB dev, 128GB production with auto-grow enabled per plan for automatic expansion beyond initial allocation)
- Ability to manually scale application instances if needed (not auto-scaling required)

## Service Level Objectives (SLOs)

- **Response Time**: 95th percentile page load time < 2 seconds
- **Data Durability**: Zero data loss from database failures (automated backups with 14-day retention)
- **Recovery Time**: Application restoration within 4 hours of infrastructure failure

## Cost Constraints

### Budget

- Monthly operating cost target: $50-150/month
- Initial setup costs: Under $100 (includes Azure Container Registry Basic SKU ~$5/month, Azure DNS zone ~$0.50/month, managed TLS certificates at no cost)
- Annual target: ~$1,000-1,800 for dev environment

### Cost Optimization

- Use smallest instance sizes sufficient for 50-100 users
- Database sized conservatively (can scale storage as needed)
- No redundancy/high-availability features for initial deployment
- Use free tier where applicable for ancillary services

## Success Criteria

### Code Validation

- [ ] Infrastructure code passes validation and linting checks
- [ ] All required configuration variables documented
- [ ] Secrets properly parameterized (not hardcoded)
- [ ] Infrastructure can be deployed repeatably

### Security Validation

- [ ] HTTPS enabled with valid TLS certificate
- [ ] Database not publicly accessible
- [ ] Secrets stored in secure secret management service
- [ ] Network security rules restrict access appropriately
- [ ] All HIGH/CRITICAL findings in infrastructure security scans remediated or documented with business justification

### Functional Validation

- [ ] Navigator application accessible via HTTPS URL
- [ ] Database connection successful and migrations applied
- [ ] Application seeds loaded successfully
- [ ] User can create workspace and perform basic threat modeling
- [ ] Real-time collaboration features working (WebSocket connections)
- [ ] Optional: AI features functional if API keys configured

### Operational Validation

- [ ] Basic monitoring/logging configured
- [ ] Database backups configured and verified
- [ ] Application logs accessible for troubleshooting
- [ ] Database backup restoration tested (verify point-in-time restore capability within retention window)
- [ ] Deployment documentation created

## Assumptions

- Target environment is development/staging (not production scale initially)
- Up to 100 concurrent users maximum in initial deployment
- Single geographic region deployment sufficient
- Manual deployment process acceptable (CI/CD can be added later)
- Active development means occasional planned maintenance windows acceptable
- AI features are optional and can be configured post-deployment
- Authentication can start without IDP integration (can add Azure AD B2C/Google/Microsoft later per plan)

## Out of Scope

- CI/CD pipeline automation (manual deployment acceptable initially)
- Multi-region deployment or disaster recovery
- Auto-scaling capabilities
- Advanced monitoring/observability (basic Application Insights acceptable for production; APM and distributed tracing not required)
- Custom domain name (can use platform-provided domain initially)
- Identity Provider integration (optional for later)
- Content Delivery Network for static assets
- Load balancing (single instance sufficient)
- Creation of baseline organizational infrastructure (resource groups, projects, etc.)
- Setup of IaC state management infrastructure (remote backend, state locking) - **MUST exist as prerequisite** (see Dependencies section)

## Dependencies

### Infrastructure Prerequisites (Must Exist Before Implementation)

- **Baseline organizational infrastructure**:
  - Azure: Resource groups (e.g., `navigator-dev-rg`, `navigator-prod-rg`)
  - Google Cloud: Projects with appropriate IAM bindings
  - AWS: Account structure with appropriate organizational units

- **IaC state management infrastructure**:
  - Remote backend storage for Terraform state (Azure Storage Account with container, AWS S3 bucket, or GCS bucket)
  - State locking mechanism (Azure Blob Storage lease-based locking, DynamoDB table for AWS, or GCS native locking)
  - RBAC permissions configured:
    - CI/CD service principals: Storage Blob Data Contributor (Azure) or equivalent write access
    - Developers: Storage Blob Data Reader (Azure) or equivalent read-only access
    - Ops team: Storage Blob Data Contributor (Azure) or equivalent full access for emergency recovery

### Application Dependencies

- Application container image built from navigator/valentine/Dockerfile
- PostgreSQL 13+ compatible database service (PostgreSQL 14.x recommended to match AWS reference architecture)
- Reference architecture: https://github.com/cds-snc/valentine-terraform/ (AWS-based implementation)

### Optional Dependencies

- OpenAI API key or Azure OpenAI credentials for AI features
- OAuth credentials for authentication providers (can be added later)

## Notes

- This specification focuses on minimal viable infrastructure ("start small with only the required bits")
- An existing AWS-based reference architecture is available at https://github.com/cds-snc/valentine-terraform/ which can guide implementation decisions
- The application is Elixir/Phoenix based, runs on port 4000, requires database migrations on startup
- Application includes real-time features (WebSockets) which need persistent connections
- The SECRET_KEY_BASE must be properly generated using cryptographically secure random generator (e.g., `openssl rand -base64 64`, not the example from docker-compose.yml) and stored in secrets management service
- Application supports both OpenAI and Azure OpenAI for AI features
- Application can run without authentication initially, but supports multiple IdP options
- Target availability is > 85% (not a strict uptime SLO, suitable for pilot/dev environments)
- **Prerequisites**: This specification assumes baseline organizational infrastructure (resource groups, projects) and IaC state management (remote backend, locking) are already in place
- **DNS Configuration**: After infrastructure deployment, domain registrar NS records must be manually updated to point to cloud provider DNS name servers (output by infrastructure code after DNS zone creation)
- **Post-Deployment Security**: Cloud provider security monitoring (e.g., Microsoft Defender for Cloud, AWS Security Hub, Google Security Command Center) recommended for production (manual configuration, not included in IaC scope)

---

**Next Steps**: Proceed to `/iac.plan` to design the infrastructure implementation.
