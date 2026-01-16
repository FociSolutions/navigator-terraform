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
