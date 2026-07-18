---
name: deploy-stack
description: >
  Deploy the stack via the CI/CD pipeline (.github/workflows/deploy.yaml) — how it authenticates
  (Azure OIDC + AWS for S3 state) and how to trigger and watch it. Use to deploy or to debug a
  deploy (PLAN.md Phase 3 onward).
---

# deploy-stack — ship via the pipeline

From PLAN.md Phase 3 on, **the pipeline is the only deploy path**: push to `master` → deploy.
Nothing in this repo is ever `terraform apply`-ed by hand — the resource group is created and
owned by the canonical identity repo (`docs/rbac.md`), so even Phase 2 has no manual bootstrap;
it's a `data "azurerm_resource_group"` reference that resolves once the canonical repo's RG
exists.

## Auth (no long-lived secrets)
- **Azure**: `azure/login` OIDC — repo variables `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` /
  `AZURE_SUBSCRIPTION_ID`. Principal + grant live in the canonical repo (`docs/rbac.md`); the
  pipeline cannot change its own permissions. Job needs
  `permissions: { id-token: write, contents: read }`.
- **AWS (S3 state)**: creds/role via repo vars/secrets, used only by terraform init/plan/apply.
- `backend.hcl` / `def.tfvars` are materialized in-job from repo variables — never committed.

## Verifying Phase 2 locally (optional, read-only)
```sh
cd infra
cp backend.hcl.example backend.hcl && cp def.tfvars.example def.tfvars   # fill in real values
terraform init -backend-config=backend.hcl
terraform plan -var-file=def.tfvars       # expect no changes — data source only
```
This is a sanity check, not a deploy step — `apply` is unnecessary here since there's nothing to
create; the pipeline handles every real apply from Phase 3 on.

## deploy.yaml (grows per phase)
Trigger: push to `master` touching `infra/**`, `api/**`, `web/**` (+ `workflow_dispatch`).
1. checkout → Azure OIDC → AWS creds → materialize backend/tfvars → `init` → `plan` →
   `apply -auto-approve` (in `infra/`).
2. (Phase 6) setup Python → `pip install -r api/requirements.txt` → `pytest api/tests/`
   (fail = stop) → deploy `api/` to the Function App.
3. (Phase 8) upload `web/` to `$web` (inject API base URL from the `api_url` output) → purge CDN.

Add `concurrency: { group: deploy, cancel-in-progress: false }` so two pushes can't race the S3
state; use the S3 native lockfile (`use_lockfile`, Terraform ≥ 1.10) for state locking.

## Operate
```sh
git push                                   # deploy
gh run watch                               # follow the current run
gh run list --workflow=deploy.yaml -L 5
gh run view <id> --log-failed              # debug a failure
```
After a run, verify per the phase's PLAN.md checklist; for the API use `test-api`. To tear down,
use `destroy-stack`.

## Debug
- Azure login fails → check the three `AZURE_*` vars and that the federated subject matches
  `repo:simonangel-fong/serverless-todo-app-azure:ref:refs/heads/master`.
- `init` fails → S3 backend creds/region/bucket/key in the materialized `backend.hcl`.
- `apply` 403 → grant scope doesn't cover the resource; fix in the canonical repo (`docs/rbac.md`),
  never by adding RBAC here.
