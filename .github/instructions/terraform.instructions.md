---
description: 'Terraform Conventions and Guidelines'
applyTo: '**/*.tf'
---

# Terraform Conventions

## Security

- Always use the latest stable version of Terraform and its providers.
  - Regularly update your Terraform configurations to incorporate security patches and improvements.
- Store sensitive information in a secure manner, such as using your cloud provider's secrets management service (e.g., AWS Secrets Manager, Azure Key Vault, Google Secret Manager, HashiCorp Vault).
- Use data sources to reference values stored in your cloud provider's secrets management service.
  - This keeps sensitive values out of your Terraform state files.
- Never commit sensitive information such as cloud provider credentials, API keys, passwords, certificates, or Terraform state to version control.
  - Use `.gitignore` to exclude files containing sensitive information from version control.
- Always mark sensitive variables as `sensitive = true` in your Terraform configurations.
  - This prevents sensitive values from being displayed in the Terraform plan or apply output.
- Regularly review and audit your Terraform configurations for security vulnerabilities.
  - Use tools like `trivy`, `tfsec`, or `checkov` to scan your Terraform configurations for security issues.
- Prefer ephemeral resources and write-only attributes for sensitive fields when available.
  - Ephemeral resources are never stored in state, ideal for temporary credentials and tokens.
  - Write-only attributes accept sensitive input but don't store values in state.
  - Both provide stronger security than `sensitive = true` (which still stores encrypted values in state).

## Modularity

- Prefer verified, cloud provider-maintained modules (e.g., Azure Verified Modules, terraform-google-module) over custom modules.
- Only create custom modules when existing solutions don't meet your specific requirements.
  - Use modules to avoid duplication and encapsulate groups of related resources.
  - Avoid modules for single resources, circular dependencies, and excessive nesting.
- Use `output` blocks to expose important information about your infrastructure.
  - Use outputs to provide information that is useful for other modules or for users of the configuration.
  - Avoid exposing sensitive information in outputs; mark outputs as `sensitive = true` if they contain sensitive data.

## Maintainability

- Write clear, concise, and maintainable configurations.
- Use comments to explain complex logic and design decisions; avoid redundant comments.
- Avoid using hard-coded values; use variables for configuration instead.
  - Set default values for variables, where appropriate.
- Use data sources to retrieve information about existing resources instead of requiring manual configuration.
  - This reduces the risk of errors, ensures that configurations are always up-to-date, and allows configurations to adapt to different environments.
  - Avoid using data sources for resources that are created within the same configuration; use outputs instead.
  - Avoid, or remove, unnecessary data sources; they slow down `plan` and `apply` operations.
- Use `locals` for values that are used multiple times to ensure consistency.

## Style and Formatting

- Follow Terraform best practices for resource naming and organization.
  - Use descriptive names for resources, variables, and outputs.
  - Use consistent naming conventions across all configurations.
- Follow the **Terraform Style Guide** for formatting.
  - Use consistent indentation (2 spaces for each level).
- Group related resources together in the same file.
  - Use a consistent naming convention for resource groups (e.g., `providers.tf`, `variables.tf`, `network.tf`, `ecs.tf`, `mariadb.tf`).
- Place `depends_on` blocks at the very beginning of resource definitions to make dependency relationships clear.
  - Use `depends_on` only when necessary to avoid circular dependencies.
- Place `for_each` and `count` blocks at the beginning of resource definitions to clarify the resource's instantiation logic.
  - Use `for_each` for collections and `count` for numeric iterations.
  - Place them after `depends_on` blocks, if they are present.
- Place `lifecycle` blocks at the end of resource definitions.
- Alphabetize providers, variables, data sources, resources, and outputs within each file for easier navigation.
- Within blocks, group and alphabetize attributes by section (required first, then optional).
  - Separate sections with blank lines for readability.
- Use blank lines to separate logical sections of your configurations.
- Use `terraform fmt` to format your configurations automatically.
- Use `terraform validate` to check for syntax errors and ensure configurations are valid.
- Use `tflint` to check for style violations and ensure configurations follow best practices.
  - Run `tflint` regularly to catch style issues early in the development process.

## Documentation

- Always include `description` and `type` attributes for all variables and outputs.
- Include a `README.md` file in each project to provide an overview of the project and its structure.
  - Include instructions for setting up and using the configurations.
- Use `terraform-docs` to generate documentation for your configurations automatically.

## Testing

- Write tests to validate the functionality of your Terraform configurations.
  - Use the `.tftest.hcl` extension for test files.
  - Write tests to cover both positive and negative scenarios.
  - Ensure tests are idempotent and can be run multiple times without side effects.

## Naming Conventions

Pattern: `{project}-{env}-{descriptor}-{type}[-{instance}]` where project=`nav`, env=`dev|stg|prod`

### Resource Names by Category

**Networking**
```
nav-dev-vnet                    # Virtual Network (vnet)
nav-dev-ca-snet                 # Container Apps Subnet (snet)
nav-dev-db-snet                 # Database Subnet (snet)
nav-dev-ca-nsg                  # Container Apps NSG (nsg)
nav-dev-db-nsg                  # Database NSG (nsg)
nav-dev-natgw                   # NAT Gateway (natgw)
nav-dev-natgw-pip               # NAT Gateway Public IP (pip)
nav-dev-kv-pe                   # Key Vault Private Endpoint (pe)
```

**Compute & Apps**
```
nav-dev-cae                     # Container App Environment (cae)
nav-dev-ca-001                  # Container App instance (ca)
nav-dev-web-ca-001              # Web app (multiple instances: -001, -002)
nav-dev-api-ca-001              # API app (descriptor: web, api, worker)
```

**Data & Storage** (globally scoped, include hash suffix)
```
nav-dev-psql                    # PostgreSQL Flexible Server (psql)
nav-dev-kv-1a2b3c4d             # Key Vault (kv + 8-char hash)
navdevst1a2b3c4d                # Storage Account (NO HYPHENS, st + 8-char hash)
nav-dev-openai                  # Azure OpenAI (openai)
```

**Monitoring**
```
nav-dev-law                     # Log Analytics Workspace (law)
nav-dev-appi                    # Application Insights (appi)
```

**Key Vault Secrets** (kebab-case)
```
db-conn-str, db-admin-pass, phoenix-key, openai-endpoint, openai-api-key
```

### Implementation

Centralize naming in `locals.tf`:

```hcl
locals {
  name_prefix       = "nav-${var.environment}"
  uniqueness_suffix = substr(sha256("${var.resource_group_name}-${var.environment}"), 0, 8)

  # Networking
  vnet_name    = "${local.name_prefix}-vnet"
  ca_snet_name = "${local.name_prefix}-ca-snet"
  db_nsg_name  = "${local.name_prefix}-db-nsg"

  # Globally scoped (with hash)
  kv_name   = "${local.name_prefix}-kv-${local.uniqueness_suffix}"
  st_name   = "nav${var.environment}st${local.uniqueness_suffix}"  # NO HYPHENS
  psql_name = "${local.name_prefix}-psql"
}
```

**Checklist**: `nav` prefix • env valid • descriptor clear • standard abbreviation • zero-padded instances • global resources have hash • storage no hyphens • within Azure length limits • tagged
