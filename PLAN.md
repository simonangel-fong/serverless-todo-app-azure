# PLAN — Implementation Steps

Derived from [SPEC.md](SPEC.md). Ordered and checkable. Authored/executed with Claude Code.

Phases are organized by architectural layer and ordered by dependency. The Claude Code
authoring assets come first — they author everything after them. CI/CD comes immediately after
the Terraform foundation, so every subsequent layer is deployed by the pipeline, not by hand:
push a phase's changes → workflow deploys → verify live.

**Prerequisite (out of scope, canonical repo):** the OIDC principal (Entra app registration +
federated credential) and its control-plane grant (Contributor scoped to this project's
well-known resource group name, or the subscription) live in the canonical identity repo, so
this repo's pipeline can never modify its own permissions. How to author that in Terraform is
documented in [docs/rbac.md](docs/rbac.md). This repo's `rbac.tf` (Phase 5, only if needed)
is limited to data-plane, resource-to-resource assignments (e.g., Function App managed
identity → Cosmos data role).

Dependency graph:

```
0 hygiene
└─ 1 Claude Code authoring assets      [author every phase below]
   └─ 2 foundation (providers/RG)
      └─ 3 CI/CD (deploy/destroy workflows)   [deploys phases 4+ from here on]
         └─ 4 data (Cosmos)
            └─ 5 compute (Function App)  [needs 4: conn]
               └─ 6 API code          [needs 5: app to deploy into, 4: live Cosmos]
                  └─ 7 hosting (Storage static site)  [adds storage origin to Phase 5's CORS via follow-up apply]
                     └─ 8 frontend    [needs 7: $web, 6: live API]
```

Phase 7's Storage static-site work has no technical dependency on Phase 6 (API) — it's
deliberately sequenced after it so the API is proven working end-to-end before frontend-hosting
work begins. Landing Phase 7 requires one follow-up change to Phase 5's Function App: adding the
new storage static-website origin to its CORS allow-list. Phase 6's code and unit tests may be
written any time after Phase 1; only their pipeline deploy waits on Phase 5.

The CI/CD workflow grows with the stack: Phase 3 ships it as terraform-only; Phase 6 adds the
Functions deploy step; Phase 8 adds the `$web` upload step.

## Phase 0 — Repo hygiene

_Depends on: nothing._

- [x] Add `backend.hcl` to [.gitignore](.gitignore) (`*.tfvars` already ignored).
- [x] `docs/rbac.md` — document how the canonical repo creates the OIDC entity (app
      registration, federated credential, control-plane role assignment) via Terraform.

**Verify**
- [x] `git status` shows no local secrets tracked; `backend.hcl`/`def.tfvars` are ignored
      (`git check-ignore` confirms, at repo root and under `infra/`), and the `*.example`
      names are not caught by the ignore rules so they'll be trackable when Phase 2 adds them.
- [ ] The grant described in `docs/rbac.md` exists (`az role assignment list --assignee <client-id>`)
      before Phase 3 goes live. _(Deferred — needs the canonical repo's client id; this is the
      Phase 3 entry gate.)_

## Phase 1 — Claude Code authoring assets (`.claude/`)

_Depends on: Phase 0. These author and operate everything below — they exist before the work,
not after it. Each is refined as later phases exercise it._

**Model.** A **subagent** is a *role* (`<tech>-<role>`) — a stateless specialist with its own
tools and craft, carrying no workflow or layer specifics. A **skill** is an *instruction /
workflow* (`<verb>-<component>`) — it owns the goal, the steps, which role runs each step, the
spec, and the trigger; multi-role skills orchestrate subagents that hand off through files on
disk (a cold subagent can't see another's context).

Subagents (`.claude/agents/`, `<tech>-<role>`):
- [x] `tf-dev` — Terraform/Azure **author**; writes `.tf` under `infra/`; runs
      fmt/validate/plan; never applies/destroys.
- [x] `tf-qa` — Terraform/Azure **reviewer**; read-only inspection of `.tf` against best
      practices + SPEC/PLAN; reports PASS / CHANGES REQUESTED.
- [x] `api-dev` — Python Functions (v2) **author**; writes `api/` (excluding tests).
- [x] `api-qa` — Python **QA**; owns the pytest suite (`api/tests/`) and reviews API code read-only.

Skills (`.claude/skills/`, `<verb>-<component>`):
- [x] `create-tf-layer` — author a Terraform layer end to end (tf-dev → tf-qa loop); layer + spec
      from input / SPEC / PLAN (drives Phases 2, 4, 5, 7).
- [x] `create-api` — build the Todo API end to end (api-dev → api-qa loop) (Phase 6).
- [x] `deploy-stack` — deploy via pipeline (Phase 3 onward).
- [x] `destroy-stack` — tear down via the destroy pipeline (`workflow_dispatch`).
- [x] `test-api` — unit + live CRUD verification of the API (Phases 6, 8 verify steps).

**Verify**
- [x] Each agent/skill has well-formed frontmatter and references SPEC.md / this plan so authored
      output can't drift; roles carry no phase specifics, skills carry no craft. (They register on
      session start — first real exercise is Phase 2 via `create-tf-layer`.)

## Phase 2 — Foundation (`infra/`)

_Depends on: Phase 1. Built with `create-tf-layer` (tf-dev → tf-qa). Produces: working
backend/provider setup and a reference to the resource group — the substrate every later
`terraform apply` runs on. The resource group itself is **created and owned by the canonical
identity repo** (along with the CI identity and its subscription-scoped Contributor grant — see
[docs/rbac.md](docs/rbac.md)); this repo only reads it via a `data "azurerm_resource_group"` block,
so there's no create-before-grant ordering dependency between the two repos and no manual RG
bootstrap here. No `rbac.tf` in this repo — the CI principal's permissions are owned by the
canonical repo._

- [x] `providers.tf` — `azurerm` provider + required versions; `azurerm` backend block (switched
      from `s3` — state now lives in the canonical repo's Azure Storage account, see `docs/rbac.md`).
- [x] `variables.tf` — inputs (project name, environment, tags).
- [x] `locals.tf` — naming convention + common tags; `resource_group_name` is the literal
      well-known name (`serverless-todoapp-dev`) created by the canonical repo — kept in sync
      with that repo's value, not derived here.
- [x] `outputs.tf` — stub now; each later phase adds its outputs (cosmos endpoint, frontend URL,
      api url) as the real resources land.
- [x] `backend.hcl.example` + `def.tfvars.example` — committed templates (resource group/storage
      account/container name for the azurerm backend; var values).
- [x] `rg.tf` — `data "azurerm_resource_group"` reference (not a resource — RG is canonical-repo-owned).

**Verify**
- [x] `terraform init -backend-config=backend.hcl` succeeds against the Azure Storage backend.
- [x] `terraform validate` and `terraform plan` are clean; plan shows no changes (data source
      only, nothing to create).
- [x] Confirmed the referenced RG exists (`az group show -n serverless-todoapp-dev`) and the CI
      principal (`f925c7f6-435d-4289-a64a-2aca79339412`) has Contributor at the subscription
      scope (`az role assignment list --assignee <client-id> -o table`, per `docs/rbac.md`).

## Phase 3 — CI/CD (`.github/workflows/`)

_Depends on: Phase 2 (backend/tfvars templates exist to materialize; the RG data source resolves)
and the canonical-repo prerequisite (RG + OIDC principal + subscription-scoped Contributor grant,
per [docs/rbac.md](docs/rbac.md)). From this phase on, every layer is deployed by pushing to
`master` — no manual applies at all, including Phase 2._

- [x] `deploy.yaml` — trigger on push to `master` touching `infra/`/app paths; single Azure OIDC
      login (provider + `azurerm` backend); materialize `backend.hcl`/`def.tfvars` from repo
      variables; `init` → `plan` → `apply`. (Functions deploy and `$web` upload steps are added
      in Phases 7–8.)
- [x] `destroy.yaml` — `workflow_dispatch`; same auth/config; `terraform destroy`.

**Verify**
- [x] Push to `master`; `deploy.yaml` runs green via OIDC only (no long-lived secrets), applies
      cleanly against the Phase 2 state (no-op plan proves state/backend wiring).
- [x] Run `destroy.yaml` and re-run `deploy.yaml`; confirm teardown and clean re-creation of
      the Phase 2 resources — the pipeline is now the deployment path for all later phases.

## Phase 4 — Data layer: Cosmos DB (`infra/cosmos.tf`)

_Depends on: Phase 3 (deployed via pipeline), Phase 2 (RG, naming). Produces: Cosmos endpoint +
connection consumed by Phase 5 (compute) app settings._

- [x] Cosmos DB account (serverless capacity mode, NoSQL API).
- [x] Database + `todos` container (partition key `/id`).
- [x] Output the account endpoint (connection consumed via resource attributes in Phase 5).

**Verify**
- [x] Push; `deploy.yaml` applies it. Confirmed via `az cosmosdb show` (`capabilities:
      EnableServerless`, `provisioningState: Succeeded`, deployed in East US 2) and
      `az cosmosdb sql container show` (partition key `/id`) that the account is serverless
      and the container is correctly configured.
- [x] Confirmed no provisioned throughput: `az cosmosdb sql container throughput show`
      returns `BadRequest — Reading or replacing offers is not supported for serverless
      accounts`, proving no RU/s offer exists (scale-to-zero when idle).

## Phase 5 — Compute layer: Function App (`infra/functions.tf`)

_Depends on: Phase 4 (Cosmos connection for app settings); deployed via the Phase 3 pipeline.
CORS is **not** wired here — Phase 7 (hosting) comes later and adds the storage static-website
origin to this Function App's CORS allow-list in a follow-up change once it exists._

- [x] Function App (Python), Consumption/Flex plan.
- [x] App settings: Cosmos connection string/endpoint referenced from the Phase 4 resources.
- [x] Output the api url (Function App default hostname).
- [x] (only if AAD auth replaces connection strings) `rbac.tf` — data-plane,
      resource-to-resource assignments, e.g. Function App managed identity → Cosmos DB data
      role. Never assignments for the CI principal itself (canonical repo owns those).
      _(Not applicable — key-based connection used instead; see functions.tf comments and
      docs/rbac.md, since the CI principal can't grant role assignments anyway.)_

**Verify**
- [x] Push; `deploy.yaml` applies it. Confirmed the Function App exists and is reachable:
      `az functionapp show` → `state: Running`, `kind: functionapp,linux`, deployed in
      Central US (East US/East US 2 hit a 0-quota Free Trial restriction on Microsoft.Web
      "Total VMs" — confirmed via live test creates and moved the layer to Central US).
- [x] Confirmed the plan is Consumption (no idle cost): `az functionapp plan show` →
      `sku.tier: Dynamic`, `sku.name: Y1`, `capacity: 0`. App settings show the Cosmos
      connection: `COSMOS_DB_ENDPOINT`/`COSMOS_DB_DATABASE`/`COSMOS_DB_CONTAINER` present
      via `az functionapp config appsettings list`.

## Phase 6 — API application layer (`api/`)

_Code + unit tests depend only on Phase 1 (fixtures already in `api/tests/fixtures/`) — can be
written in parallel with Phases 2–5. Built with `create-api` (api-dev → api-qa). Pipeline deploy
depends on Phase 5 (app to deploy into) and Phase 4 (live Cosmos). Extends `deploy.yaml` with the
Functions deploy step._

- [x] `function_app.py` — Python v2 model, HTTP routes for CRUD per the SPEC contract
      (authored by `api-dev`).
- [x] Cosmos SDK integration (create/read/update/delete against `todos`).
- [x] `requirements.txt`, `host.json`, `local.settings.json.example`.
- [x] Unit tests (`api/tests/`) — authored by `api-qa`; pytest, mocked Cosmos client, driven by
      the fixtures in `api/tests/fixtures/` (`todos.json`, `requests.json`). Cover each CRUD
      route incl. 400/404 cases.
- [x] Extend `deploy.yaml`: run pytest, then deploy `api/` to the Function App.

**Verify**
- [x] `pytest` passes locally against the mocked Cosmos client and fixtures (no infra needed):
      26 passed (`python -m pytest api/tests/ -q`).
- [x] Push; `deploy.yaml` tests and deploys the app. Ran `test-api` against the live endpoint:
      create (201) → list (200) → get (200) → update (200) → delete (204) → get-after-delete
      (404), plus the error contract (400 on missing/whitespace title, 404 on PUT/DELETE for an
      unknown id). Live testing also caught a real bug not visible from mocked unit tests: Cosmos
      system properties (`_rid`/`_self`/`_etag`/`_attachments`/`_ts`) were leaking into response
      bodies; fixed in `cosmos_repository.py` (allow-list projection) and hardened the
      `FakeContainer` test double to simulate that leakage so it can't regress silently.

## Phase 7 — Hosting layer: Storage static site (`infra/storage.tf`)

_Depends on: Phase 3 (deployed via pipeline), Phase 2 (RG, naming). Produces: the frontend
origin (storage static-website endpoint) that Phase 8 needs, and the `$web` container Phase 8
deploys into. No technical dependency on Phase 6 (API) — sequenced after it deliberately, so the
API is proven working end-to-end before frontend-hosting work begins._

_No CDN in front of this endpoint: Azure Front Door is forbidden on this Free Trial/Student
subscription ("BadRequest: Free Trial and Student account is forbidden for Azure Frontdoor
resources", confirmed by a live pipeline failure), and "classic" Azure CDN
(`azurerm_cdn_profile`/`azurerm_cdn_endpoint`) can no longer be created for new resources as of
2025-10-01. With neither option available, the frontend is served directly from the storage
account's static-website endpoint instead — no flat recurring base fee, consistent with this
project's scale-to-zero constraint._

- [x] Storage account + static website (`$web`).
- [x] Output the storage static-website endpoint (frontend origin).
- [x] Update `infra/functions.tf` (Phase 5): add the storage static-website origin to the
      Function App's CORS allow-list.

**Verify**
- [x] Push; `deploy.yaml` applies it. Uploaded a placeholder `index.html` to `$web` and
      confirmed it's served from the storage static-website URL (`curl` → `200 OK`, body
      matches).
- [x] Confirmed the Function App's CORS allow-list now includes the storage static-website
      origin (`az functionapp cors show` → `allowedOrigins: ["https://serverlesstodoappdevweb.z13.web.core.windows.net"]`)
      — converged on the first deploy, confirming `deploy.yaml`'s targeted-apply mitigation
      (storage account applied before the full plan) worked as intended.

## Phase 8 — Frontend application layer (`web/`)

_Depends on: Phase 7 (`$web` to host it) and Phase 6 (live, verified API to call — the API base
URL injected at deploy time is the Phase 5 output). No separate `deploy.yaml` upload step is
needed: `infra/frontend.tf`'s `azurerm_storage_blob` resources upload `web/` as part of the
existing Terraform apply, the same "Terraform owns the deployment artifact" pattern as Phase 6's
`zip_deploy_file` — one tool, no new CI step._

- [x] `index.html` + `app.js` + `styles.css` — list/create/toggle/edit/delete against `/api/todos`.
- [x] API base URL injected via Terraform (`infra/frontend.tf` replaces the `__API_BASE_URL__`
      placeholder in `web/app.js` with the Phase 5 Function App's default hostname output) —
      not a separate build/deploy-time CI step.
- [x] `infra/frontend.tf`: `azurerm_storage_blob` resources upload `web/` into `$web`, keyed by
      `content_md5`/`filemd5()` for change detection (no CI upload step needed).

**Verify**
- [ ] Push; `deploy.yaml` deploys the frontend.
- [ ] Load the storage static-website endpoint in a browser; confirm full CRUD works end-to-end
      against the live API (create, toggle, edit, delete all reflected without errors).

## Final acceptance

- [ ] `deploy.yaml` runs green end-to-end on push: terraform → pytest → Functions deploy →
      `$web` upload, with no manual steps and no long-lived secrets (OIDC only).
- [ ] Confirm serverless tiers scale to zero cost when idle.
- [ ] Run `destroy.yaml`; confirm full teardown. Re-run `deploy.yaml`; confirm the entire stack
      is reproducible from scratch.
