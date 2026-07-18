# PLAN — Implementation Steps

Derived from [SPEC.md](SPEC.md). Ordered and checkable. Authored/executed with Claude Code
(subagents in `.claude/agents/`, skills in `.claude/skills/`).

## 0. Repo hygiene
- [ ] Add `backend.hcl` to [.gitignore](.gitignore) (`*.tfvars` already ignored).

## 1. Terraform scaffolding (`infra/`)
- [ ] `providers.tf` — `azurerm` provider + required versions; `s3` backend block.
- [ ] `variables.tf` — inputs (project name, location, tags, OIDC principal object id, etc.).
- [ ] `locals.tf` — naming convention + common tags.
- [ ] `outputs.tf` — api url, static-website/CDN endpoint, cosmos endpoint.
- [ ] `backend.hcl.example` + `def.tfvars.example` — committed templates (bucket/key/region; var values).

## 2. Terraform resources — layer by layer (`infra/`)
- [ ] `rg.tf` — resource group.
- [ ] `storage.tf` — storage account + static website ($web).
- [ ] `cdn.tf` — CDN profile/endpoint fronting the static website.
- [ ] `cosmos.tf` — Cosmos DB account (serverless) + database + `todos` container (PK `/id`).
- [ ] `functions.tf` — Function App (Python), plan, app settings incl. Cosmos connection, CORS.
- [ ] `rbac.tf` — RBAC role assignments for the pre-existing OIDC principal, scoped to the RG.

## 3. Backend API (`api/`)
- [ ] `function_app.py` — Python v2 model, HTTP routes for CRUD per the SPEC contract.
- [ ] Cosmos SDK integration (create/read/update/delete against `todos`).
- [ ] `requirements.txt`, `host.json`, `local.settings.json.example`.
- [ ] Unit tests (`api/tests/`) — pytest, mocked Cosmos client, driven by the fixtures in
      `api/tests/fixtures/` (`todos.json`, `requests.json`). Cover each CRUD route incl. 400/404 cases.

## 4. Frontend (`web/`)
- [ ] `index.html` + `app.js` + styles — list/create/toggle/delete against `/api/todos`.
- [ ] API base URL injected at build/deploy time.

## 5. CI/CD (`.github/workflows/`)
- [ ] `deploy.yaml` — trigger on push to `master` touching `infra/`/app paths; Azure OIDC + AWS creds;
      materialize `backend.hcl`/`def.tfvars` from repo variables; `init` → `plan` → `apply`;
      deploy Functions app; upload `web/` to `$web`; purge CDN.
- [ ] `destroy.yaml` — `workflow_dispatch`; same auth/config; `terraform destroy`.

## 6. Claude Code authoring assets (`.claude/`)
- [ ] `agents/terraform-author` — authors the layer-by-layer `.tf` files.
- [ ] `agents/api-author` — authors the Python Functions CRUD handlers.
- [ ] `skills/deploy` — wraps init/plan/apply + app deploy.
- [ ] `skills/verify-crud` — exercises the API end-to-end.

## Verification
1. `terraform plan` in `infra/` is clean and reviewable.
2. After apply: `curl` each CRUD route (create → list → get → update → delete); confirm codes/payloads.
3. Load the CDN endpoint; confirm the static site does full CRUD against the API.
4. Confirm serverless tiers scale to zero cost when idle.
5. Run `destroy.yaml`; confirm full teardown.
