"""Todo CRUD API — Azure Functions Python programming model v2.

Routes and behavior follow SPEC.md's "API contract" table exactly; see that file for the
authoritative contract and document shape. Do not duplicate the contract here as a comment --
keep this module and SPEC.md from drifting apart.
"""

import json
import logging
import uuid
from datetime import datetime, timezone

import azure.functions as func

from cosmos_repository import get_repository

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)


def _json_response(data, status_code: int) -> func.HttpResponse:
    return func.HttpResponse(
        body=json.dumps(data),
        status_code=status_code,
        mimetype="application/json",
    )


def _error_response(message: str, status_code: int) -> func.HttpResponse:
    return _json_response({"error": message}, status_code)


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _parse_json_body(req: func.HttpRequest):
    try:
        body = req.get_json()
    except ValueError:
        return None, _error_response("Request body must be valid JSON", 400)
    if not isinstance(body, dict):
        return None, _error_response("Request body must be a JSON object", 400)
    return body, None


def _validate_title(title) -> bool:
    return isinstance(title, str) and title.strip() != ""


@app.route(route="todos", methods=["GET"])
def list_todos(req: func.HttpRequest) -> func.HttpResponse:
    repo = get_repository()
    todos = repo.list_all()
    return _json_response(todos, 200)


@app.route(route="todos", methods=["POST"])
def create_todo(req: func.HttpRequest) -> func.HttpResponse:
    body, error = _parse_json_body(req)
    if error:
        return error

    title = body.get("title")
    if not _validate_title(title):
        return _error_response("title is required and must be a non-empty string", 400)

    now = _utc_now_iso()
    item = {
        "id": str(uuid.uuid4()),
        "title": title,
        "is_completed": False,
        "created_at": now,
        "updated_at": now,
    }

    repo = get_repository()
    created = repo.create(item)
    return _json_response(created, 201)


@app.route(route="todos/{id}", methods=["GET"])
def get_todo(req: func.HttpRequest) -> func.HttpResponse:
    todo_id = req.route_params.get("id")
    repo = get_repository()
    item = repo.get(todo_id)
    if item is None:
        return _error_response("todo not found", 404)
    return _json_response(item, 200)


@app.route(route="todos/{id}", methods=["PUT"])
def update_todo(req: func.HttpRequest) -> func.HttpResponse:
    todo_id = req.route_params.get("id")
    body, error = _parse_json_body(req)
    if error:
        return error

    repo = get_repository()
    existing = repo.get(todo_id)
    if existing is None:
        return _error_response("todo not found", 404)

    if "title" in body:
        title = body.get("title")
        if not _validate_title(title):
            return _error_response("title must be a non-empty string", 400)
        existing["title"] = title

    if "is_completed" in body:
        is_completed = body.get("is_completed")
        if not isinstance(is_completed, bool):
            return _error_response("is_completed must be a boolean", 400)
        existing["is_completed"] = is_completed

    existing["updated_at"] = _utc_now_iso()

    updated = repo.upsert(existing)
    return _json_response(updated, 200)


@app.route(route="todos/{id}", methods=["DELETE"])
def delete_todo(req: func.HttpRequest) -> func.HttpResponse:
    todo_id = req.route_params.get("id")
    repo = get_repository()
    deleted = repo.delete(todo_id)
    if not deleted:
        return _error_response("todo not found", 404)
    return func.HttpResponse(status_code=204)
