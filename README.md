# Serverless Todo App on Azure

A Todo application built entirely serverless on Azure — Cosmos DB (serverless capacity), Azure
Functions (Python, Consumption plan), and a static frontend on a Storage account — provisioned
end-to-end with Terraform and deployed via GitHub Actions using Azure OIDC (no long-lived
secrets). Authored with [Claude Code](https://claude.com/claude-code); see
[SPEC.md](SPEC.md), [PLAN.md](PLAN.md), and [.claude/](.claude/) for how.

## Architecture

```
GitHub Actions (OIDC) ──apply──▶ Terraform ──provisions──▶ Azure
                                                             │
                    ┌────────────────────────────────────────┼─────────────────────────────┐
                    │                                        │                             │
         Storage static website               Azure Functions (Python, Consumption)   Cosmos DB
         ($web container, no CDN)  ──CORS──▶   /api/todos CRUD                ──────▶  (serverless,
         served over HTTPS                     zip_deploy_file (Terraform-owned)        NoSQL API)
```

- **Data**: Cosmos DB, serverless capacity mode, NoSQL API. No provisioned throughput anywhere —
  scales to zero cost when idle.
- **Compute**: Azure Functions, Python v2 programming model, Consumption (`Y1`/Dynamic) plan.
  Code is deployed *by Terraform* (`zip_deploy_file`), not a separate CI action — one tool owns
  both the app's settings and its running code, so nothing can drift between them.
- **Frontend**: static HTML/JS/CSS on a Storage account's static website endpoint, served
  directly with no CDN in front — Azure Front Door is blocked on Free Trial subscriptions and
  classic Azure CDN can no longer be created for new resources (deprecated 2025-10-01). Content
  is uploaded by Terraform (`azurerm_storage_blob`), same pattern as the API.
- **CI/CD**: a single GitHub Actions job authenticates once via Azure OIDC, runs the API's unit
  tests, then runs one `terraform apply` that provisions infrastructure, deploys the API code,
  and uploads the frontend together. If the tests fail, nothing in that push deploys — including
  unrelated infrastructure changes bundled in the same commit. That's an intentional tradeoff:
  never apply a partially-tested state.

## Repository layout

```
infra/            Terraform — one file per resource layer (rg, cosmos, functions, storage, frontend)
api/               Python Azure Functions app (Todo CRUD against Cosmos)
  tests/           pytest suite, mocked Cosmos client, fixture-driven
web/               Static frontend (vanilla HTML/CSS/JS, no build step)
.github/workflows/ deploy.yaml (push to master) and destroy.yaml (workflow_dispatch only)
.claude/           Subagents (tf-dev/tf-qa, api-dev/api-qa) and skills used to build this repo
docs/rbac.md       How the external identity/state-backend repo grants this repo's CI access
SPEC.md            The project's contract: stack, data model, API routes, constraints
PLAN.md            Phase-by-phase build log — what was built, verified, and why, including
                   every real bug and tradeoff hit along the way
```

## API contract

| Method | Route             | Behavior                         | Success     | Errors          |
| ------ | ----------------- | --------------------------------- | ----------- | --------------- |
| GET    | `/api/todos`      | list all todos                   | 200 + array | —               |
| POST   | `/api/todos`      | create (body `{title}`)          | 201 + item  | 400 if no title |
| GET    | `/api/todos/{id}` | fetch one                        | 200 + item  | 404             |
| PUT    | `/api/todos/{id}` | update (`title`, `is_completed`) | 200 + item  | 400 / 404       |
| DELETE | `/api/todos/{id}` | delete                           | 204         | 404             |

Document shape: `{id, title, is_completed, created_at, updated_at}` — no Cosmos-internal fields
ever leak into responses (a real bug caught during live testing; see PLAN.md Phase 6).

## Deploying

Requires an existing resource group and a canonical identity repo that's granted this repo's CI
principal Contributor access (see [docs/rbac.md](docs/rbac.md)) — this repo never manages its own
permissions. Once that prerequisite exists:

```sh
git push origin master        # deploy.yaml runs: pytest → terraform apply (infra + API + frontend)
gh workflow run destroy.yaml  # tear everything down (workflow_dispatch only, never automatic)
```

Both are OIDC-authenticated only — no stored cloud credentials anywhere in this repo or its CI.

## Local development

```sh
# API unit tests (no Azure needed — Cosmos is fully mocked)
python -m pytest api/tests/ -q

# Terraform (read-only checks; this repo's convention is CI-only apply, no manual applies)
cd infra
terraform init -backend-config=backend.hcl
terraform fmt -check && terraform validate && terraform plan -var-file=def.tfvars -var="function_app_zip_path=<any-file>"
```

## Notable engineering decisions

This project was built and iteratively hardened phase by phase, with every real bug encountered
along the way documented in [PLAN.md](PLAN.md) rather than swept away — including:

- Two Free Trial subscription restrictions that blocked deploys outright (Function App VM quota
  in East US; Azure Front Door forbidden entirely) and how the design adapted around each.
- Consolidating the Function App's code deployment from a separate GitHub Action into Terraform
  itself, closing a real `app_settings` drift bug and a SAS-token-expiry risk in the process.
  See [Microsoft's documentation](https://learn.microsoft.com/en-us/azure/azure-functions/run-functions-from-deployment-package)
  and its [AZFD0006 diagnostic](https://learn.microsoft.com/en-us/azure/azure-functions/errors-diagnostics/diagnostic-events/azfd0006).
- A `terraform-plugin-sdk` limitation ([hashicorp/terraform-plugin-sdk#1210](https://github.com/hashicorp/terraform-plugin-sdk/issues/1210))
  where an unknown value inside a brand-new Terraform Set can silently vanish from a plan diff —
  hit twice (once for the CDN endpoint, once for the storage static-website endpoint) and fixed
  both times with a guarded, idempotent targeted-apply step.
- A Cosmos SDK response leak (internal `_rid`/`_etag`/etc. fields reaching API responses) that
  passed 26 mocked unit tests but failed live — fixed, and the test double hardened so it can't
  regress silently again.

## Non-goals

Authentication/authorization, multi-environment support, and pagination are explicitly out of
scope for now — see [SPEC.md](SPEC.md) for the full constraint list.
