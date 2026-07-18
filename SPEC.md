# SPEC — Serverless Todo App on Azure

## Goal

A serverless Todo application on Azure, provisioned entirely with Terraform (IaC) and
deployed via GitHub Actions using OIDC (no long-lived secrets). Implementation is authored
with Claude Code (see [PLAN.md](PLAN.md) and `.claude/`).

## Stack (decided)

| Area          | Choice                                                                          |
| ------------- | ------------------------------------------------------------------------------- |
| API compute   | Azure Functions — serverless (Consumption/Flex plan)                            |
| API runtime   | Python (Azure Functions Python programming model v2)                            |
| Database      | Azure Cosmos DB — serverless capacity mode, NoSQL API                           |
| Frontend      | Static HTML/JS hosted on a Storage account static website, fronted by Azure CDN |
| Auth          | Out of scope for now; schema designed so it can be added later                  |
| IaC           | Terraform (`azurerm` provider)                                                  |
| State backend | Existing S3 bucket (managed outside this repo)                                  |
| CI/CD         | GitHub Actions with OIDC                                                        |

## Data model — Cosmos DB container `todos`

Partition key: `/id` for now. If per-user auth is added later, introduce `owner_id` and
repartition on `/owner_id` (new container / migration — acceptable pre-launch).

```json
{
  "id": "<guid>", // item_id — also the document id
  "title": "string", // item_title
  "is_completed": false,
  "created_at": "ISO-8601",
  "updated_at": "ISO-8601"
}
```

## API contract — HTTP-triggered Functions

| Method | Route             | Behavior                         | Success     | Errors          |
| ------ | ----------------- | -------------------------------- | ----------- | --------------- |
| GET    | `/api/todos`      | list all todos                   | 200 + array | —               |
| POST   | `/api/todos`      | create (body `{title}`)          | 201 + item  | 400 if no title |
| GET    | `/api/todos/{id}` | fetch one                        | 200 + item  | 404             |
| PUT    | `/api/todos/{id}` | update (`title`, `is_completed`) | 200 + item  | 400 / 404       |
| DELETE | `/api/todos/{id}` | delete                           | 204         | 404             |

CORS must allow the Storage/CDN frontend origin.

## Sample data / test fixtures

Fixtures for unit tests live in `api/tests/fixtures/`:

- **`todos.json`** — a seed set of four valid `todos` documents (one completed, three open;
  fixed GUIDs and timestamps for deterministic assertions). Used to seed a fake/in-memory Cosmos
  repository so GET/list/update/delete handlers can be tested without a live database.
- **`requests.json`** — request-body payloads for validation tests: valid create/update, a
  status-only partial update, and invalid cases (missing/empty/whitespace/wrong-type title) that
  must yield `400`.

Unit tests mock the Cosmos client and assert handler behavior against these fixtures per the
API contract above. Determinism (fixed ids/timestamps) is intentional so tests don't depend on
clock or random GUID generation — production code generates real GUIDs and timestamps.

## Constraints & non-goals

- **Serverless / scale-to-zero**: Cosmos serverless + Functions consumption must incur ~no cost when idle.
- **No secrets in CI**: Azure access via OIDC; S3 backend via AWS OIDC role or repo variables.
- **Cross-cloud state**: Terraform state lives in AWS S3 while resources live in Azure — backend and
  provider are independent, but CI must provide both credentials.
- **Sensitive config not committed**: `backend.hcl` and `def.tfvars` are gitignored; `*.example`
  templates are committed.
- **OIDC identity and its permissions are external**: the Entra app registration, federated
  credential, **and the CI principal's control-plane role assignment** (Contributor scoped to this
  project's well-known resource-group name, or the subscription) live in a separate canonical repo
  (out of scope) — the pipeline must never manage its own permissions. [docs/rbac.md](docs/rbac.md)
  documents how to author that entity in Terraform. This repo consumes client/tenant/subscription
  ids as inputs; its own `rbac.tf` is limited to data-plane, resource-to-resource assignments
  (e.g., Function App managed identity → Cosmos data role), and only if AAD auth is adopted.
- Non-goals: authentication/authorization, multi-environment (single environment to start), pagination.
