---
name: deploy-stack
description: >
  Deploy the stack via the CI/CD pipeline (.github/workflows/deploy.yaml) — how it authenticates
  (Azure OIDC + AWS for S3 state), how to trigger and watch it, and the one-time Phase 2 manual
  bootstrap. Use to deploy or to debug a deploy (PLAN.md Phase 3 onward).
---

# deploy-stack — ship via the pipeline

From PLAN.md Phase 3 on, **the pipeline is the only deploy path**: push to `master` → deploy.
Nothing is `terraform apply`-ed by hand except the one-time bootstrap below.

## Auth (no long-lived secrets)
- **Azure**: `azure/login` OIDC — repo variables `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` /
  `AZURE_SUBSCRIPTION_ID`. Principal + grant live in the canonical repo (`doc/rbac.md`); the
  pipeline cannot change its own permissions. Job needs
  `permissions: { id-token: write, contents: read }`.
- **AWS (S3 state)**: creds/role via repo vars/secrets, used only by terraform init/plan/apply.
- `backend.hcl` / `def.tfvars` are materialized in-job from repo variables — never committed.

## Phase 2 bootstrap (one-time, manual — before the pipeline exists)
```sh
cd infra
cp backend.hcl.example backend.hcl && cp def.tfvars.example def.tfvars   # fill in real values
terraform init -backend-config=backend.hcl
terraform plan  -var-file=def.tfvars      # expect only the resource group
terraform apply -var-file=def.tfvars      # creates the RG the canonical grant is scoped to
```
After this, every later layer deploys via the pipeline — do not apply manually again.

## deploy.yaml (grows per phase)
Trigger: push to `master` touching `infra/**`, `api/**`, `web/**` (+ `workflow_dispatch`).
1. checkout → Azure OIDC → AWS creds → materialize backend/tfvars → `init` → `plan` →
   `apply -auto-approve` (in `infra/`).
2. (Phase 7) setup Python → `pip install -r api/requirements.txt` → `pytest api/tests/`
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
- `apply` 403 → grant scope doesn't cover the resource; fix in the canonical repo (`doc/rbac.md`),
  never by adding RBAC here.
