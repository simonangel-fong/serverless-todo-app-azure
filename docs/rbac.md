# RBAC — CI/CD identity (authored in the canonical repo)

The OIDC identity this repo's pipeline authenticates as — and every permission that identity
holds — is **owned by the canonical identity repo, not this one**. The **resource group itself
is also created and owned by the canonical repo**, not this repo. This repo's `infra/rg.tf`
only *references* that RG via a `data "azurerm_resource_group"` block (see
[infra/locals.tf](../infra/locals.tf), [infra/rg.tf](../infra/rg.tf)); its own `rbac.tf` (if
any) is limited to data-plane, resource-to-resource assignments between resources it creates.
The pipeline must never be able to modify its own permissions.

This document describes what the canonical repo creates, in Terraform, for this project. It is
a reference — none of the code below is applied from this repo.

## What the canonical repo creates

1. **Resource group** — the well-known RG (`serverless-todoapp-dev`) every layer in this repo
   deploys into.
2. **Entra app registration + service principal** — the identity GitHub Actions federates into.
3. **Federated identity credential** — trusts GitHub's OIDC issuer for this repo/branch, so no
   client secret exists anywhere.
4. **Control-plane role assignment** — Contributor for the principal, **subscription-scoped**.

## Terraform (canonical repo)

```hcl
# serverless-todo-app-azure.tf
# Providers: azurerm for the RG + role assignment, azuread for the identity.

locals {
  serverless_todoapp_name     = "serverless-todoapp-dev"
  serverless_todoapp_location = "eastus"
  serverless_todoapp_tags = {
    Project   = "serverless-todoapp"
    ManagedBy = "Terraform"
  }
}

resource "azurerm_resource_group" "serverless_todoapp" {
  name     = local.serverless_todoapp_name
  location = local.serverless_todoapp_location
  tags     = local.serverless_todoapp_tags
}

resource "azuread_application" "serverless_todoapp" {
  display_name = local.serverless_todoapp_name
}

resource "azuread_service_principal" "serverless_todoapp" {
  client_id = azuread_application.serverless_todoapp.client_id
}

# Trust GitHub Actions OIDC for pushes to master of this repo.
# workflow_dispatch runs on master presents the same subject.
resource "azuread_application_federated_identity_credential" "serverless_todoapp_ci" {
  application_id = azuread_application.serverless_todoapp.id
  display_name   = "serverless-todo-app-azure-gh-master"
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:simonangel-fong/serverless-todo-app-azure:ref:refs/heads/master"
  audiences      = ["api://AzureADTokenExchange"]
}

data "azurerm_subscription" "current" {}

resource "azurerm_role_assignment" "serverless_todoapp" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.serverless_todoapp.object_id
}

output "serverless_todoapp_client_id" {
  value = azuread_application.serverless_todoapp.client_id
}
```

### Scope: subscription (not resource-group)

The Contributor grant is scoped to the **subscription**, not the RG. Since the canonical repo
also creates the RG itself, there's no ordering dependency in either direction between the two
repos — this repo's `infra/` only needs the RG's well-known *name* (`serverless-todoapp-dev`,
kept in sync in `infra/locals.tf`) to reference it via a data source. Trade-off: broader blast
radius than an RG-scoped grant, accepted here for simpler bootstrap (single environment, small
project — see SPEC.md non-goals).

Notes:

- **Contributor cannot write role assignments** (`Microsoft.Authorization/roleAssignments/write`
  is excluded). That is intentional: it is what prevents this repo's pipeline from escalating
  itself. Any data-plane assignments this repo ever needs (e.g., Function App managed identity
  → Cosmos DB data role) are created *by* the pipeline only if Contributor suffices for them;
  the CI principal's own grants always stay in the canonical repo.
- Whoever applies the canonical repo needs `Owner` or `Role Based Access Control Administrator`
  on the subscription.

## Outputs consumed by this repo

The canonical repo exposes these; they are set as **GitHub Actions repository variables** here
(they are identifiers, not secrets — but variables keep them out of the workflow file):

| Canonical output                          | GitHub variable         | Used by                    |
| ----------------------------------------- | ----------------------- | -------------------------- |
| `serverless_todoapp_client_id` output     | `AZURE_CLIENT_ID`       | `azure/login` OIDC step    |
| tenant id                                 | `AZURE_TENANT_ID`       | `azure/login` OIDC step    |
| subscription id                           | `AZURE_SUBSCRIPTION_ID` | `azure/login`, provider    |

## Verification (before this repo's Phase 3 goes live)

```sh
az ad app list --display-name serverless-todo-app-azure --query "[].appId"
az role assignment list --assignee 00724cd0-11d9-4218-b161-7423f06097b7 -o table
# Principal                             Role         Scope
# ------------------------------------  -----------  ---------------------------------------------------
# 00724cd0-11d9-4218-b161-7423f06097b7  Contributor  /subscriptions/adb97c42-2927-4b7d-881d-59fc6c69b886
```
