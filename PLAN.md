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
documented in [docs/rbac.md](docs/rbac.md). This repo's `rbac.tf` (Phases 4–6, only if needed)
is limited to data-plane, resource-to-resource assignments (e.g., Function App managed
identity → Cosmos data role).

Dependency graph:

```
0 hygiene
└─ 1 Claude Code authoring assets      [author every phase below]
   └─ 2 foundation (providers/RG)
      └─ 3 CI/CD (deploy/destroy workflows)   [deploys phases 4+ from here on]
         ├─ 4 data (Cosmos) ──────────┐
         ├─ 5 hosting (Storage+CDN) ──┤
         │                            └─ 6 compute (Function App)  [needs 4: conn, 5: CORS origin]
         │                                  └─ 7 API code          [unit tests have no infra deps]
         │                                        └─ 8 frontend    [needs 5: $web/CDN, 7: live API]
```

Phases 4 and 5 are independent of each other and may be done in parallel. Phase 7's code and
unit tests may be written any time after Phase 1; only their pipeline deploy waits on Phase 6.

The CI/CD workflow grows with the stack: Phase 3 ships it as terraform-only; Phase 7 adds the
Functions deploy step; Phase 8 adds the `$web` upload + CDN purge step.

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
      from input / SPEC / PLAN (drives Phases 2, 4–6).
- [x] `create-api` — build the Todo API end to end (api-dev → api-qa loop) (Phase 7).
- [x] `deploy-stack` — deploy via pipeline (Phase 3 onward).
- [x] `destroy-stack` — tear down via the destroy pipeline (`workflow_dispatch`).
- [x] `test-api` — unit + live CRUD verification of the API (Phases 7–8 verify steps).

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

- [x] `providers.tf` — `azurerm` provider + required versions; `s3` backend block.
- [x] `variables.tf` — inputs (project name, environment, tags).
- [x] `locals.tf` — naming convention + common tags; `resource_group_name` is the literal
      well-known name (`serverless-todoapp-dev`) created by the canonical repo — kept in sync
      with that repo's value, not derived here.
- [x] `outputs.tf` — stub now; each later phase adds its outputs (cosmos endpoint, CDN endpoint,
      api url) as the real resources land.
- [x] `backend.hcl.example` + `def.tfvars.example` — committed templates (bucket/key/region; var values).
- [x] `rg.tf` — `data "azurerm_resource_group"` reference (not a resource — RG is canonical-repo-owned).

**Verify**
- [ ] `terraform init -backend-config=backend.hcl` succeeds against the S3 backend.
- [ ] `terraform validate` and `terraform plan` are clean; plan shows no changes (data source
      only, nothing to create).
- [ ] Confirm the referenced RG exists (`az group show -n serverless-todoapp-dev`) and the CI
      principal has Contributor at the subscription scope
      (`az role assignment list --assignee <client-id> -o table`, per `docs/rbac.md`).

## Phase 3 — CI/CD (`.github/workflows/`)

_Depends on: Phase 2 (backend/tfvars templates exist to materialize; the RG data source resolves)
and the canonical-repo prerequisite (RG + OIDC principal + subscription-scoped Contributor grant,
per [docs/rbac.md](docs/rbac.md)). From this phase on, every layer is deployed by pushing to
`master` — no manual applies at all, including Phase 2._

- [ ] `deploy.yaml` — trigger on push to `master` touching `infra/`/app paths; Azure OIDC + AWS
      creds; materialize `backend.hcl`/`def.tfvars` from repo variables; `init` → `plan` →
      `apply`. (Functions deploy and `$web` upload steps are added in Phases 7–8.)
- [ ] `destroy.yaml` — `workflow_dispatch`; same auth/config; `terraform destroy`.

**Verify**
- [ ] Push to `master`; `deploy.yaml` runs green via OIDC only (no long-lived secrets), applies
      cleanly against the Phase 2 state (no-op plan proves state/backend wiring).
- [ ] Run `destroy.yaml` and re-run `deploy.yaml`; confirm teardown and clean re-creation of
      the Phase 2 resources — the pipeline is now the deployment path for all later phases.

## Phase 4 — Data layer: Cosmos DB (`infra/cosmos.tf`)

_Depends on: Phase 3 (deployed via pipeline), Phase 2 (RG, naming). Produces: Cosmos endpoint +
connection consumed by Phase 6 app settings. Independent of Phase 5 — parallelizable._

- [ ] Cosmos DB account (serverless capacity mode, NoSQL API).
- [ ] Database + `todos` container (partition key `/id`).
- [ ] Output the account endpoint (connection consumed via resource attributes in Phase 6).

**Verify**
- [ ] Push; `deploy.yaml` applies it. Confirm via `az cosmosdb show` /
      `az cosmosdb sql container show` that the account is serverless and the container's
      partition key is `/id`.
- [ ] Confirm the account has no provisioned throughput (scale-to-zero when idle).

## Phase 5 — Hosting layer: Storage static site + CDN (`infra/storage.tf`, `cdn.tf`)

_Depends on: Phase 3 (deployed via pipeline), Phase 2 (RG, naming). Produces: the frontend
origin (CDN endpoint hostname) that Phase 6 needs for CORS, and the `$web` container Phase 8
deploys into. Independent of Phase 4 — parallelizable. Deliberately before the Function App so
the CORS origin exists when compute is configured._

- [ ] Storage account + static website (`$web`).
- [ ] CDN profile/endpoint fronting the static website.
- [ ] Output the CDN endpoint hostname (frontend origin).

**Verify**
- [ ] Push; `deploy.yaml` applies it. Upload a placeholder `index.html` to `$web` and confirm
      it's served from both the storage static-website URL and the CDN endpoint.

## Phase 6 — Compute layer: Function App (`infra/functions.tf`)

_Depends on: Phase 4 (Cosmos connection for app settings) and Phase 5 (CDN origin for CORS);
deployed via the Phase 3 pipeline._

- [ ] Function App (Python), Consumption/Flex plan.
- [ ] App settings: Cosmos connection string/endpoint referenced from the Phase 4 resources.
- [ ] CORS: allow the Phase 5 CDN endpoint origin.
- [ ] Output the api url (Function App default hostname).
- [ ] (only if AAD auth replaces connection strings) `rbac.tf` — data-plane,
      resource-to-resource assignments, e.g. Function App managed identity → Cosmos DB data
      role. Never assignments for the CI principal itself (canonical repo owns those).

**Verify**
- [ ] Push; `deploy.yaml` applies it. Confirm the Function App exists and is reachable
      (default host ping / `az functionapp show` state `Running`) even with no functions
      deployed yet.
- [ ] Confirm the plan is Consumption/Flex (no idle cost); app settings show the Cosmos
      connection; CORS lists the CDN origin.

## Phase 7 — API application layer (`api/`)

_Code + unit tests depend only on Phase 1 (fixtures already in `api/tests/fixtures/`) — can be
written in parallel with Phases 2–6. Built with `create-api` (api-dev → api-qa). Pipeline deploy
depends on Phase 6 (app to deploy into) and Phase 4 (live Cosmos). Extends `deploy.yaml` with the
Functions deploy step._

- [ ] `function_app.py` — Python v2 model, HTTP routes for CRUD per the SPEC contract
      (authored by `api-dev`).
- [ ] Cosmos SDK integration (create/read/update/delete against `todos`).
- [ ] `requirements.txt`, `host.json`, `local.settings.json.example`.
- [ ] Unit tests (`api/tests/`) — authored by `api-qa`; pytest, mocked Cosmos client, driven by
      the fixtures in `api/tests/fixtures/` (`todos.json`, `requests.json`). Cover each CRUD
      route incl. 400/404 cases.
- [ ] Extend `deploy.yaml`: run pytest, then deploy `api/` to the Function App.

**Verify**
- [ ] `pytest` passes locally against the mocked Cosmos client and fixtures (no infra needed).
- [ ] Push; `deploy.yaml` tests and deploys the app. Run `test-api`: each CRUD route against the
      live endpoint (create → list → get → update → delete) matches the SPEC contract, including
      the 400/404 error cases.

## Phase 8 — Frontend application layer (`web/`)

_Depends on: Phase 5 (`$web` + CDN to host it) and Phase 7 (live, verified API to call — the
API base URL injected at deploy time is the Phase 6 output). Extends `deploy.yaml` with the
`$web` upload + CDN purge step._

- [ ] `index.html` + `app.js` + styles — list/create/toggle/delete against `/api/todos`.
- [ ] API base URL injected at build/deploy time from the Phase 6 `api url` output.
- [ ] Extend `deploy.yaml`: upload `web/` to `$web`, purge the CDN.

**Verify**
- [ ] Push; `deploy.yaml` deploys the frontend.
- [ ] Load the CDN endpoint in a browser; confirm full CRUD works end-to-end against the live
      API (create, toggle, edit, delete all reflected without errors).

## Final acceptance

- [ ] `deploy.yaml` runs green end-to-end on push: terraform → pytest → Functions deploy →
      `$web` upload → CDN purge, with no manual steps and no long-lived secrets (OIDC only).
- [ ] Confirm serverless tiers scale to zero cost when idle.
- [ ] Run `destroy.yaml`; confirm full teardown. Re-run `deploy.yaml`; confirm the entire stack
      is reproducible from scratch.
