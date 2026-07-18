```sh
terraform -chdir=infra init -backend-config=backend.hcl -migrate-state
terraform -chdir=infra fmt && terraform -chdir=infra validate

terraform -chdir=infra apply -auto-approve
```
