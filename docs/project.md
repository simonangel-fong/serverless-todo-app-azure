
goal
- create a serverless todo app using
    - azure service
    - terraform as iac
    - claude code for implementation

todo app features
- backend:
    - restful api + database
- frontend:
    - html host by storage cdn
- auth (optional):
    - entra id

Database:
- serverless 
- nosql
- design:
    - item_id
    - item_title


API design
- todo items CRUD

terraform
- scaffolding
    - variables.tf: input paramters
    - locals.tf: internal variables
    - providers.tf: versions and providers
    - outputs.tf: output
    - backend.hcl: backend configure
    - def.tfvars: variables
- layer by layer for main resouces
    - e.g., rg.tf, storage.tf, etc.
- ci/cd github actions:
    - deploy.yaml: 
        - master; infra/
        - deploy worklow
        - oidc
    - destroy
        - master; infra/
        - destroy workflow
        - oidc






