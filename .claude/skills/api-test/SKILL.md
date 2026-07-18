---
name: api-test
description: >
  Instructions to test the Todo API: run the pytest unit suite locally, and exercise every
  CRUD route against the live deployed endpoint per the SPEC contract (used by PLAN.md
  Phases 7–8 verify steps).
---

# api-test — verifying the Todo API

Two levels. Unit tests need nothing but Python; the live check needs a deployed stack.

## 1. Unit tests (local, no Azure)

```sh
python -m pytest api/tests/ -q
```

All tests must pass; they mock Cosmos and are driven by `api/tests/fixtures/`. A failure here
blocks any deploy (the pipeline runs the same command).

## 2. Live CRUD check (deployed API)

Get the base URL from the infra outputs (or the Function App default hostname):

```sh
BASE=$(cd infra && terraform output -raw api_url)   # e.g. https://<app>.azurewebsites.net
```

Run the full lifecycle **in this order**, checking status codes and payloads against the
SPEC.md contract table:

```sh
# create → 201, body echoes the item with id/created_at/updated_at
curl -si -X POST "$BASE/api/todos" -H "Content-Type: application/json" -d '{"title":"live check"}'
ID=<id from the response>

# list → 200, array containing $ID
curl -si "$BASE/api/todos"

# get one → 200 + item
curl -si "$BASE/api/todos/$ID"

# update → 200, is_completed=true, updated_at changed
curl -si -X PUT "$BASE/api/todos/$ID" -H "Content-Type: application/json" -d '{"is_completed":true}'

# delete → 204, empty body
curl -si -X DELETE "$BASE/api/todos/$ID"

# verify gone → 404
curl -si "$BASE/api/todos/$ID"
```

Error contract (must also hold live):

```sh
curl -si -X POST "$BASE/api/todos" -d '{}'                        # 400 (no title)
curl -si -X POST "$BASE/api/todos" -d '{"title":"   "}'           # 400 (whitespace)
curl -si -X PUT  "$BASE/api/todos/00000000-0000-0000-0000-000000000000" -d '{"title":"x"}'  # 404
curl -si -X DELETE "$BASE/api/todos/00000000-0000-0000-0000-000000000000"                   # 404
```

## 3. CORS / frontend origin (Phase 8)

```sh
ORIGIN=https://$(cd infra && terraform output -raw cdn_endpoint)
curl -si "$BASE/api/todos" -H "Origin: $ORIGIN" | grep -i access-control-allow-origin
```

The CDN origin must be echoed back, or the frontend cannot call the API.

## Reporting

Report each step's expected vs. actual status code (a table is fine), quote any mismatching
response body verbatim, and leave the test todo deleted (clean up anything the run created).
