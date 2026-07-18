---
name: cicd
description: >
  Instructions for this repo's deploy and destroy pipelines (.github/workflows/deploy.yaml,
  destroy.yaml) — how they authenticate, how to trigger and watch them, and how they grow
  per phase. Use when deploying, destroying, or debugging CI/CD (PLAN.md Phase 3 onward).
---

# CI/CD — deploy & destroy pipelines

From PLAN.md Phase 3 onward, **the pipeline is the only deployment path**: nothing is
`terraform apply`-ed manually. Deploy = push to `master`; destroy = manual workflow dispatch.

## Authentication model (no long-lived secrets)

- **Azure**: `azure/login` with OIDC — repo variables `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
  `AZURE_SUBSCRIPTION_ID`. The principal + its Contributor grant live in the canonical repo
  (`doc/rbac.md`); this repo cannot change its own permissions. Workflow needs
  `permissions: id-token: write, contents: read`.
- **AWS (S3 state backend)**: credentials/role via repo variables/secrets, used only by
  `terraform init/plan/apply`.
- `backend.hcl` and `def.tfvars` are **materialized in the job** from repo variables (echoed
  from the `*.example` templates' shape) — they are never committed.

## deploy.yaml

Trigger: push to `master` touching `infra/**` or app paths (`api/**`, `web/**`) — plus
`workflow_dispatch` for reruns. Steps grow with the phases:

1. (always) checkout → Azure OIDC login → AWS creds → materialize `backend.hcl`/`def.tfvars`
   → `terraform init -backend-config=backend.hcl` → `plan` → `apply -auto-approve` (in `infra/`).
2. (added Phase 7) set up Python → `pip install -r api/requirements.txt` → `pytest api/tests/`
   (fail = stop) → deploy `api/` to the Function App.
3. (added Phase 8) upload `web/` to the storage `$web` container (inject API base URL from the
   `api url` terraform output) → purge the CDN endpoint.

## destroy.yaml

`workflow_dispatch` only. Same auth + materialize steps, then
`terraform destroy -auto-approve -var-file=def.tfvars`. Never triggered automatically.

## Operating the pipelines

```sh
git push                                   # deploy: push to master does it
gh run watch                               # follow the current run
gh run list --workflow=deploy.yaml -L 5    # recent runs
gh workflow run destroy.yaml               # destroy (explicit, manual)
```

After a deploy run, verify per the current phase's **Verify** checklist in PLAN.md; for API
phases use `skills/api-test`.

## Debugging failures

- `gh run view <id> --log-failed` first.
- Azure login fails → check the three `AZURE_*` repo variables and that the federated
  credential subject matches `repo:simonangel-fong/serverless-todo-app-azure:ref:refs/heads/master`.
- `terraform init` fails → S3 backend: AWS creds/region/bucket/key as materialized into
  `backend.hcl`.
- `apply` 403s → the canonical grant's scope doesn't cover the resource — fix in the canonical
  repo (`doc/rbac.md`), never by adding RBAC here.
