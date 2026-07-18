---
name: create-api
description: >
  Build or change the Python Todo API end to end — api-dev writes the handlers, api-qa writes tests
  and reviews, loop until green. Use for work under api/ (PLAN.md Phase 6).
---

# create-api — build the Todo API (api-dev → api-qa)

A multi-role workflow. **You (the orchestrator)** run the steps and invoke the subagents; they are
cold specialists and hand off through the files on disk.

## Input
The feature / route set to build (default: the full CRUD contract in `SPEC.md`) and any specifics.

## Workflow
1. **api-dev** — author `function_app.py` (v2), Cosmos integration, `requirements.txt`,
   `host.json`, `local.settings.json.example`, per the SPEC contract; make the Cosmos client
   injectable. Handoff = the code on disk.
2. **api-qa** — author/extend the pytest suite in `api/tests/` (mocked Cosmos, fixture-driven,
   full contract coverage) and review the production code. Run `python -m pytest api/tests/ -q`.
   Return **PASS** or **CHANGES REQUESTED**.
3. If failing tests or CHANGES REQUESTED → **api-dev** fixes production code (only) → back to 2.
4. **Exit** when the suite is green and api-qa PASSes.

## Boundary
api-dev owns `api/` (not tests); api-qa owns `api/tests/` and reviews the rest read-only. Neither
touches `infra/` — if an app setting is missing, report it for a `create-tf-layer` run on the
functions layer.

## Done when
Green suite + api-qa PASS. For live verification after deploy, use `test-api`.
