---
name: create-tf-layer
description: >
  Author one Terraform layer under infra/ end to end — tf-dev writes it, tf-qa reviews, loop until
  clean. Use when an infra/ layer (rg, cosmos, storage/cdn, functions, ...) must be created or
  changed. The specific layer and its spec come from user input / SPEC / PLAN.
---

# create-tf-layer — author a Terraform layer (tf-dev → tf-qa)

A multi-role workflow. **You (the orchestrator)** run the steps and invoke the subagents; the
subagents are cold specialists and hand off through the files on disk, not shared memory.

## Input
- **Which layer** and its file (`rg.tf`, `cosmos.tf`, `storage.tf`, `cdn.tf`, `functions.tf`, ...).
- **The spec** — resources, tiers/SKUs, names, CIDRs, subnets. Take it from the user; fall back to
  the layer's definition in `SPEC.md` / `PLAN.md`.

## Workflow
1. **tf-dev** — author the layer per the spec; add its `outputs.tf` entries; run fmt/validate/plan.
   Handoff = the written `.tf` files.
2. **tf-qa** — review those files on disk against best practices + SPEC/PLAN; return **PASS** or
   **CHANGES REQUESTED** with findings.
3. If CHANGES REQUESTED → **tf-dev** fixes the specific findings → back to step 2.
4. **Exit** when tf-qa PASSes and `terraform plan` shows only this layer's intended changes.

## Guardrails (the roles enforce these; restated so the workflow honors them)
Serverless tiers only; names/tags from `locals.tf`; no secrets committed; no CI-principal RBAC
(canonical repo owns it). Never `apply` / `destroy` in this skill — that is `deploy-stack`.

## Done when
Plan is clean and tf-qa passes. Report the layer, the plan summary, and the review verdict. Do not
apply — the pipeline (or the one-time Phase-2 bootstrap in `deploy-stack`) does that.
