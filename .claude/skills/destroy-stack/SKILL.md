---
name: destroy-stack
description: >
  Tear down the stack via the destroy pipeline (.github/workflows/destroy.yaml) —
  workflow_dispatch only, same OIDC auth as deploy-stack. Use to destroy the environment.
---

# destroy-stack — tear down via the pipeline

`destroy.yaml` runs on **`workflow_dispatch` only** — never automatically. Same auth and
backend/tfvars materialization as `deploy-stack` (see `doc/rbac.md`), then:

```sh
terraform destroy -auto-approve -var-file=def.tfvars
```

## Operate
```sh
gh workflow run destroy.yaml
gh run watch
```

## After
Confirm full teardown: `terraform show` is empty and no resources remain in the RG
(`az resource list -g <rg>`). The resource group itself, plus the canonical-repo identity and its
grant, persist by design (owned elsewhere). To rebuild, re-run `deploy-stack` from clean.
