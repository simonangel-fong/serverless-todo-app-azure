---
name: test-api
description: >
  Test the Todo API — run the pytest unit suite locally, and exercise every CRUD route against the
  live deployed endpoint per the SPEC contract. Use for PLAN.md Phase 7–8 verify steps.
---

# test-api — verify the Todo API

Two levels. Unit tests need only Python; the live check needs a deployed stack. Run the curl
sequence in **Git Bash** (the syntax is bash, not PowerShell).

## 1. Unit tests (local, no Azure)
```sh
python -m pytest api/tests/ -q
```
All must pass; the pipeline runs the same command, so a failure here blocks any deploy.

## 2. Live CRUD check (deployed API)
Get the base URL from the Terraform outputs, or from Azure if you have no local backend:
```sh
BASE=$(cd infra && terraform output -raw api_url)
# fallback: BASE="https://$(az functionapp show -g <rg> -n <app> --query defaultHostName -o tsv)"
```
Run the lifecycle **in order**, checking status codes and payloads against the SPEC contract table:
```sh
curl -si -X POST "$BASE/api/todos" -H "Content-Type: application/json" -d '{"title":"live check"}'  # 201 + item
ID=<id from the response>
curl -si "$BASE/api/todos"                # 200 + array containing $ID
curl -si "$BASE/api/todos/$ID"           # 200 + item
curl -si -X PUT "$BASE/api/todos/$ID" -H "Content-Type: application/json" -d '{"is_completed":true}'  # 200, updated_at changed
curl -si -X DELETE "$BASE/api/todos/$ID" # 204, empty body
curl -si "$BASE/api/todos/$ID"           # 404 (gone)
```
Error contract (must also hold live):
```sh
curl -si -X POST "$BASE/api/todos" -d '{}'              # 400 (no title)
curl -si -X POST "$BASE/api/todos" -d '{"title":"   "}' # 400 (whitespace)
curl -si -X PUT  "$BASE/api/todos/00000000-0000-0000-0000-000000000000" -d '{"title":"x"}'  # 404
curl -si -X DELETE "$BASE/api/todos/00000000-0000-0000-0000-000000000000"                   # 404
```

## 3. CORS / frontend origin (Phase 8)
```sh
ORIGIN="https://$(cd infra && terraform output -raw cdn_endpoint)"
curl -si "$BASE/api/todos" -H "Origin: $ORIGIN" | grep -i access-control-allow-origin
```
The CDN origin must be echoed back, or the frontend cannot call the API.

## Report
Expected vs. actual status per step (a table is fine), quote any mismatching response body
verbatim, and leave the test todo deleted (clean up anything the run created).
