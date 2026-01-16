# Navigator Azure Terraform Development Guidelines

Auto-generated agent instructions. Last updated: 2026-01-15

## Project Overview

This repository contains Azure infrastructure code to deploy the [Navigator](https://github.com/canada-ca/navigator/) threat modeling application. Navigator is an Elixir/Phoenix web application with real-time collaboration features.

**Repository structure:**
- `navigator/` - Git submodule containing the Navigator application source code (Elixir/Phoenix)
- `iac/` - Terraform infrastructure code for Azure deployment (to be created)
- `specs/` - Feature specifications and planning documents
- `.github/instructions/` - Code conventions and guidelines

### Technology Stack

#### Infrastructure
- **IaC Tool**: Terraform (Azure provider)
- **Cloud Provider**: Microsoft Azure
- **Target Services**: Azure Container Instances/App Service, Azure Database for PostgreSQL, Azure Key Vault

#### Application (navigator/ submodule)
- **Language**: Elixir 1.18.4+
- **Framework**: Phoenix 1.7.18+ with LiveView
- **Database**: PostgreSQL 13+
- **Runtime**: Runs on port 4000, requires WebSocket support

## External File Loading

CRITICAL: When you encounter a file reference (e.g., @rules/general.md), use your Read tool to load it on a need-to-know basis. They're relevant to the SPECIFIC task at hand.

Instructions:

- Do NOT preemptively load all references - use lazy loading based on actual need
- When loaded, treat content as mandatory instructions that override defaults
- Follow references recursively when needed

## Code Style Guidelines

### Terraform Style

For Terraform code conventions, refer to @.github/instructions/terraform.instructions.md

### Elixir/Phoenix Style

For Elixir/Phoenix code conventions, refer to @navigator/valentine/AGENTS.md

## Important Notes

- **Submodule**: `navigator/` is a git submodule - don't commit changes there unless you own the upstream repo
- **Reference architecture**: AWS implementation at https://github.com/cds-snc/valentine-terraform/

## Security Reminders

- Never commit secrets, API keys, or credentials
- Always mark sensitive Terraform variables as `sensitive = true`
- Always run `trivy config terraform/` and fix or justify the issue.
- Keep Terraform providers and modules updated
- Use Azure Key Vault for all secrets
- Ensure database is not publicly accessible
- Enforce HTTPS/TLS for all web traffic

