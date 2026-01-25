# Infrastructure Specification: Internal Container Apps with Reverse Proxy

**Spec ID**: `002-internal-ca`
**Created**: 2026-01-25
**Status**: Draft
**Input**: User description: "I need to secure my existing navigator application Azure Container Apps environment configured via terraform/azure/ configurations by making it internal only and routing all external traffic via a reverse proxy."

## Executive Summary *(mandatory)*

This specification defines the infrastructure requirements to secure the Navigator application by converting the existing publicly exposed container application environment to an internal-only deployment with external traffic routed through a reverse proxy (application gateway). The infrastructure will provide defense-in-depth security, centralized traffic management, and enhanced protection against direct internet exposure while maintaining public accessibility.

## Problem Statement *(mandatory)*

### Current State

The Navigator application is currently deployed using container applications with direct external ingress enabled. The container application endpoint is publicly accessible via HTTPS on port 443, with traffic flowing directly from the internet to the container instances. Network security relies primarily on network security groups allowing unrestricted inbound HTTPS traffic (0.0.0.0/0). This architecture exposes the application directly to potential threats and provides limited centralized control over incoming traffic.

### Desired State

The container application environment will be configured for internal-only access, with all external traffic routed through a managed reverse proxy (application gateway). The reverse proxy will serve as the single public entry point, providing SSL/TLS termination, web application firewall capabilities, and centralized traffic management. Container applications will accept traffic only from the reverse proxy via private networking, eliminating direct internet exposure.

### Business Impact

**Benefits:**
- Enhanced security posture with defense-in-depth architecture
- Centralized SSL/TLS certificate management and offloading
- Web application firewall protection against common attacks (OWASP Top 10)
- Improved traffic monitoring and logging at the reverse proxy layer
- Foundation for future advanced routing scenarios (A/B testing, canary deployments)

**Risks if not implemented:**
- Continued direct exposure of application endpoints to internet threats
- Higher attack surface with limited protection layers
- Difficulty implementing centralized security policies
- Potential compliance violations for applications requiring layered security

## Infrastructure Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Infrastructure MUST configure container application ingress as internal-only, preventing direct internet access to container endpoints
- **FR-002**: Infrastructure MUST provision a reverse proxy (application gateway) as the single public entry point for external traffic
- **FR-003**: Infrastructure MUST route all external HTTPS traffic through the reverse proxy to internal container application endpoints
- **FR-004**: Infrastructure MUST configure backend health probes from the reverse proxy to verify container application availability
- **FR-005**: Infrastructure MUST maintain WebSocket support for real-time features (Phoenix LiveView) through the reverse proxy
- **FR-006**: Infrastructure MUST preserve session affinity (sticky sessions) through the reverse proxy to ensure WebSocket connection stability
- **FR-007**: Infrastructure MUST configure SSL/TLS termination at the reverse proxy with automatic certificate management
- **FR-008**: Infrastructure MUST update network security groups to allow traffic only from the reverse proxy subnet to the container application subnet
- **FR-009**: Infrastructure MUST maintain existing custom domain support through the reverse proxy endpoint
- **FR-010**: Infrastructure MUST preserve existing container application scaling behavior and health monitoring

### Non-Functional Requirements

#### Performance

- **NFR-P-001**: Reverse proxy MUST add no more than 10ms latency (p95) to request processing
- **NFR-P-002**: Reverse proxy MUST support at least 50-100 concurrent connections
- **NFR-P-003**: WebSocket connections MUST maintain sub-100ms roundtrip latency through the reverse proxy
- **NFR-P-004**: Backend health probe intervals MUST be 30 seconds or less to detect failures promptly

#### Availability

- **NFR-A-001**: Reverse proxy MUST provide 99.95% uptime SLO (matching or exceeding container platform availability)
- **NFR-A-002**: Reverse proxy MUST support zone-redundant deployment when zone redundancy is enabled for the environment
- **NFR-A-003**: Reverse proxy failures MUST NOT cascade to backend container applications (circuit breaker behavior)
- **NFR-A-004**: Configuration changes to the reverse proxy MUST NOT cause service interruption

#### Security

- **NFR-S-001**: Container application endpoints MUST NOT be accessible directly from the internet
- **NFR-S-002**: Reverse proxy MUST enforce TLS 1.2 or higher for all external connections
- **NFR-S-003**: Communication between reverse proxy and container applications MUST use HTTPS
- **NFR-S-004**: Web application firewall MUST be configurable with OWASP Core Rule Set (CRS) protection
- **NFR-S-005**: Network security groups MUST restrict container application inbound traffic to reverse proxy subnet only
- **NFR-S-006**: Reverse proxy MUST support IP allowlist/blocklist capabilities for future access control requirements

#### Scalability

- **NFR-SC-001**: Reverse proxy capacity MUST scale to match maximum container application replica count
- **NFR-SC-002**: Reverse proxy MUST support minimum 2 instances for production environments
- **NFR-SC-003**: Backend pool configuration MUST dynamically adapt to container application scaling events

## Service Level Objectives (SLOs) *(mandatory)*

- **SLO-001**: **Availability**: 99.95% uptime for external access through the reverse proxy, measured over 30-day rolling window using uptime monitoring
- **SLO-002**: **Latency**: 95th percentile end-to-end request latency (including reverse proxy overhead) < 200ms for API requests
- **SLO-003**: **Error Rate**: Less than 0.1% of requests fail due to reverse proxy errors (5xx responses from gateway)
- **SLO-004**: **Security Isolation**: 100% of direct internet traffic to container endpoints blocked, verified through network flow logs
- **SLO-005**: **Health Detection**: Container application failures detected within 60 seconds via reverse proxy health probes

## Cost Constraints *(mandatory)*

### Budget

**Initial Setup**:
- Reverse proxy (application gateway) provisioning: Included in cloud subscription
- SSL/TLS certificate configuration: $0 (using existing managed certificates)
- Network infrastructure updates: No additional cost
- One-time implementation: Negligible (infrastructure-as-code deployment)

**Monthly Operating**:
- Development environment: Additional $100-150/month for reverse proxy (small instance)
- Production environment: Additional $250-400/month for reverse proxy (zone-redundant, higher capacity)
- No changes to existing container application, database, or networking costs
- Data transfer costs: Minimal increase (<5%) for additional reverse proxy hop

**Annual**:
- Development: ~$1,800/year additional
- Production: ~$4,800/year additional

### Cost Optimization

- Use fixed capacity for reverse proxy in development (no auto-scaling)
- Leverage zone redundancy only in production environments
- Start with basic WAF tier, upgrade to advanced features only if required
- Monitor reverse proxy utilization to right-size capacity
- Consider reserved capacity for production reverse proxy if 12-month commitment is feasible

## Compliance Requirements *(include if applicable)*

### Regulatory Frameworks

- Government of Canada security controls (ITSG-33 alignment for threat modeling applications)
- Defense-in-depth security architecture requirements for public-facing applications
- Secure communication protocols (TLS 1.2+ requirement)

### Data Requirements

- All traffic inspection and logging must comply with Canadian privacy laws
- WAF logs containing potential PII must be retained per organizational data retention policies
- No sensitive data should be logged at the reverse proxy layer (application responsibility)

## Success Criteria *(mandatory)*

### Code Validation

- [ ] Container application ingress configuration changed from `external_enabled = true` to `external_enabled = false`
- [ ] Reverse proxy resource defined with appropriate sizing for environment (dev vs production)
- [ ] Backend pool configured with container application internal endpoint
- [ ] Health probe configured matching container application health check path and port
- [ ] Network security group rules updated to allow traffic only from reverse proxy subnet
- [ ] All infrastructure code passes `terraform validate` and `terraform fmt -check`
- [ ] Security scanning (`trivy config terraform/`) shows no HIGH/CRITICAL findings for new resources
- [ ] Required tags applied to all new reverse proxy resources

### Security Validation

- [ ] External network scan confirms container application endpoint NOT accessible from internet
- [ ] Reverse proxy HTTPS listener configured with TLS 1.2+ minimum version
- [ ] Network security group rules restrict container application inbound to reverse proxy subnet CIDR only
- [ ] WAF capabilities verified available and configurable (even if initially in detection-only mode)
- [ ] No credentials or secrets exposed in infrastructure code (all sensitive values from variables/secrets)

### Performance Validation

- [ ] HTTP requests through reverse proxy complete within 200ms (p95 latency) under normal load
- [ ] WebSocket connections successfully establish and maintain stability through reverse proxy
- [ ] Session affinity (sticky sessions) confirmed working for multi-request user flows
- [ ] Backend health probes successfully detect container application failures within 60 seconds
- [ ] Container application scaling behavior unchanged (scales based on existing rules)

### Operational Validation

- [ ] Custom domain (if configured) resolves to reverse proxy public IP and serves traffic correctly
- [ ] Reverse proxy access logs capturing request details (source IP, URL, response status)
- [ ] Container application logs show requests originating from reverse proxy internal IP only
- [ ] Health probe failures trigger appropriate routing changes (traffic diverted from unhealthy backends)
- [ ] Existing monitoring and alerting continue functioning without disruption
- [ ] Deployment tested successfully in development environment before production

## Assumptions *(include if making assumptions)*

- Assume existing container application health check endpoint (currently `/`) remains valid for reverse proxy health probes
- Assume current container application port (4000) and protocol (HTTP) remain unchanged for backend connectivity
- Assume SSL/TLS certificates for custom domain (if used) can be managed by the reverse proxy platform's certificate service
- Assume development and production environments can share the same reverse proxy configuration pattern with environment-specific sizing
- Assume existing VNet address space has sufficient capacity for a new reverse proxy subnet (minimum /24 recommended)
- Assume WebSocket upgrade requests use standard HTTP upgrade headers compatible with reverse proxy
- Assume session affinity configuration (sticky sessions) currently applied to container apps can be replicated at reverse proxy layer

## Out of Scope *(include if explicitly excluding items)*

- Custom WAF rules or policies beyond default OWASP CRS configuration (future enhancement)
- DDoS protection beyond standard cloud platform capabilities (separate security layer)
- Content caching or CDN integration at the reverse proxy (application-level caching preferred)
- Multi-region reverse proxy deployment (single region deployment only)
- Rate limiting policies beyond basic connection limits (application-level responsibility)
- Application code changes to handle reverse proxy headers (assume compatible architecture)
- Migration of existing custom domain DNS records (operational task, not infrastructure spec)
- Legacy system decommissioning or cleanup of old external endpoints

## Dependencies *(include if external dependencies exist)*

- Existing VNet with sufficient address space for new reverse proxy subnet
- Existing container application environment with documented internal FQDN/endpoint
- SSL/TLS certificate availability for custom domain (if custom domain is configured)
- Network security group modification permissions for container application subnet
- DNS management access for updating custom domain records to point to reverse proxy
- Container application must respond correctly to health probe requests on the configured path
- Phoenix LiveView WebSocket implementation must use standard HTTP upgrade mechanism

## Notes

- The reverse proxy implementation should use managed application gateway service for automated patching and maintenance
- Consider enabling WAF in "detection mode" initially to observe traffic patterns before enforcing blocking rules
- The application gateway subnet must not have network security groups attached (platform limitation)
- Backend pool members can be specified using FQDN (container application default domain) or IP address
- Session affinity at reverse proxy level complements but does not replace container application session affinity
- Monitor both reverse proxy metrics (gateway latency, backend response time) and container application metrics separately
- Plan for gradual rollout: test in dev, validate in staging (if available), then deploy to production
- Document the new architecture in operational runbooks with troubleshooting steps for reverse proxy layer

---

**Specification Quality Checklist**:
- [x] No implementation details (cloud providers, specific tools)
- [x] All requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Cost constraints clearly defined
- [x] Compliance requirements specified (if applicable)
