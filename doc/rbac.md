# RBAC — CI/CD identity (authored in the canonical repo)

The OIDC identity this repo's pipeline authenticates as — and every permission that identity
holds — is **owned by the canonical identity repo, not this one**. This repo's workflows only
*consume* the resulting ids; its own `rbac.tf` (if any) is limited to data-plane,
resource-to-resource assignments between resources it creates. The pipeline must never be able
to modify its own permissions.

This document describes what the canonical repo needs to create, in Terraform, for this
project. It is a reference — none of the code below is applied from this repo.

## What the canonical repo creates

1. **Entra app registration + service principal** — the identity GitHub Actions federates into.
2. **Federated identity credential** — trusts GitHub's OIDC issuer for this repo/branch, so no
   client secret exists anywhere.
3. **Control-plane role assignment** — Contributor for the principal, scoped to this project's
   well-known resource group (preferred) or the subscription.

## Terraform (canonical repo)

```hcl
# Providers: azuread for the identity, azurerm for the role assignment.

resource "azuread_application" "todo_ci" {
  display_name = "gh-serverless-todo-app-azure-ci"
}

resource "azuread_service_principal" "todo_ci" {
  client_id = azuread_application.todo_ci.client_id
}

# Trust GitHub Actions OIDC for pushes to master of this repo.
# workflow_dispatch runs on master present the same subject.
resource "azuread_application_federated_identity_credential" "todo_ci_master" {
  application_id = azuread_application.todo_ci.id
  display_name   = "gh-serverless-todo-app-azure-master"
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:simonangel-fong/serverless-todo-app-azure:ref:refs/heads/master"
  audiences      = ["api://AzureADTokenExchange"]
}
```

### Role assignment — two scoping options

**Option A — resource-group scope (preferred, least privilege).** The grant targets the
project's well-known RG name (the contract with `infra/locals.tf` in this repo). The RG must
exist before the assignment can be applied — this repo's Phase 2 manual apply creates it,
then the canonical repo applies the grant.

```hcl
data "azurerm_subscription" "current" {}

resource "azurerm_role_assignment" "todo_ci_contributor" {
  scope = "${data.azurerm_subscription.current.id}/resourceGroups/<well-known-rg-name>"
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.todo_ci.object_id
}
```

**Option B — subscription scope (simpler bootstrap, broader blast radius).** No ordering
dependency — the pipeline could even create the RG itself — at the cost of Contributor across
the whole subscription.

```hcl
resource "azurerm_role_assignment" "todo_ci_contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.todo_ci.object_id
}
```

Notes:

- **Contributor cannot write role assignments** (`Microsoft.Authorization/roleAssignments/write`
  is excluded). That is intentional: it is what prevents this repo's pipeline from escalating
  itself. Any data-plane assignments this repo ever needs (e.g., Function App managed identity
  → Cosmos DB data role) are created *by* the pipeline only if Contributor suffices for them at
  the RG scope; the CI principal's own grants always stay in the canonical repo.
- Whoever applies the canonical repo needs `Owner` or `Role Based Access Control Administrator`
  on the target scope.

## Outputs consumed by this repo

The canonical repo exposes these; they are set as **GitHub Actions repository variables** here
(they are identifiers, not secrets — but variables keep them out of the workflow file):

| Canonical output                          | GitHub variable         | Used by                    |
| ----------------------------------------- | ----------------------- | -------------------------- |
| `azuread_application.todo_ci.client_id`   | `AZURE_CLIENT_ID`       | `azure/login` OIDC step    |
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
