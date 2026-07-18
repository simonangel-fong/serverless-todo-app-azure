"""Unit tests for function_app.py's HTTP handlers.

Cosmos is fully faked (see conftest.py's FakeContainer/repo/client fixtures) -- no network, no
emulator. Seeded from tests/fixtures/todos.json; validation payloads come from
tests/fixtures/requests.json. GUID/clock generation is frozen via the `client` fixture so
created/updated timestamps and ids are deterministic and assertable.
"""

import json

import azure.functions as func
import pytest

from conftest import FROZEN_NEW_ID, FROZEN_NOW

KNOWN_ID = "11111111-1111-1111-1111-111111111111"
OPEN_ID = "22222222-2222-2222-2222-222222222222"
UNKNOWN_ID = "00000000-0000-0000-0000-000000000000"

ALL_FIELDS = {"id", "title", "is_completed", "created_at", "updated_at"}


def _req(method, route="todos", route_params=None, body=None):
    body_bytes = json.dumps(body).encode("utf-8") if body is not None else b""
    return func.HttpRequest(
        method=method,
        url=f"/api/{route}",
        route_params=route_params or {},
        body=body_bytes,
    )


def _json(response: func.HttpResponse):
    return json.loads(response.get_body())


# ---------------------------------------------------------------------------
# GET /api/todos
# ---------------------------------------------------------------------------


def test_list_todos_returns_200_and_all_seed_items(client, todos_data):
    response = client.list_todos(_req("GET"))

    assert response.status_code == 200
    assert response.mimetype == "application/json"
    body = _json(response)
    assert isinstance(body, list)
    assert len(body) == len(todos_data)
    assert {item["id"] for item in body} == {item["id"] for item in todos_data}


def test_list_todos_items_have_all_five_fields(client):
    response = client.list_todos(_req("GET"))

    body = _json(response)
    for item in body:
        assert set(item.keys()) == ALL_FIELDS


# ---------------------------------------------------------------------------
# POST /api/todos
# ---------------------------------------------------------------------------


def test_post_todos_valid_create_returns_201_and_item(client, requests_data):
    response = client.create_todo(_req("POST", body=requests_data["valid_create"]))

    assert response.status_code == 201
    assert response.mimetype == "application/json"
    body = _json(response)
    assert set(body.keys()) == ALL_FIELDS
    assert body["id"] == FROZEN_NEW_ID
    assert body["title"] == "Buy milk"
    assert body["is_completed"] is False
    assert body["created_at"] == FROZEN_NOW
    assert body["updated_at"] == FROZEN_NOW


def test_post_todos_valid_create_persists_to_repo(client, repo, requests_data):
    client.create_todo(_req("POST", body=requests_data["valid_create"]))

    created = repo.get(FROZEN_NEW_ID)
    assert created is not None
    assert created["title"] == "Buy milk"


def test_post_todos_missing_title_returns_400(client, requests_data):
    response = client.create_todo(_req("POST", body=requests_data["invalid_create_missing_title"]))

    assert response.status_code == 400
    assert response.mimetype == "application/json"
    assert "error" in _json(response)


def test_post_todos_empty_title_returns_400(client, requests_data):
    response = client.create_todo(_req("POST", body=requests_data["invalid_create_empty_title"]))

    assert response.status_code == 400


def test_post_todos_whitespace_title_returns_400(client, requests_data):
    response = client.create_todo(_req("POST", body=requests_data["invalid_create_whitespace_title"]))

    assert response.status_code == 400


def test_post_todos_wrong_type_title_returns_400(client, requests_data):
    response = client.create_todo(_req("POST", body=requests_data["invalid_create_wrong_type"]))

    assert response.status_code == 400


def test_post_todos_invalid_json_body_returns_400(client):
    request = func.HttpRequest(method="POST", url="/api/todos", body=b"not json")

    response = client.create_todo(request)

    assert response.status_code == 400


@pytest.mark.parametrize(
    "invalid_key",
    [
        "invalid_create_missing_title",
        "invalid_create_empty_title",
        "invalid_create_whitespace_title",
        "invalid_create_wrong_type",
    ],
)
def test_post_todos_invalid_cases_do_not_persist(client, repo, requests_data, invalid_key, todos_data):
    client.create_todo(_req("POST", body=requests_data[invalid_key]))

    assert len(repo.list_all()) == len(todos_data)


# ---------------------------------------------------------------------------
# GET /api/todos/{id}
# ---------------------------------------------------------------------------


def test_get_todo_known_id_returns_200_and_item(client):
    response = client.get_todo(_req("GET", route="todos/" + KNOWN_ID, route_params={"id": KNOWN_ID}))

    assert response.status_code == 200
    assert response.mimetype == "application/json"
    body = _json(response)
    assert set(body.keys()) == ALL_FIELDS
    assert body["id"] == KNOWN_ID
    assert body["title"] == "Write the SPEC"
    assert body["is_completed"] is True


def test_get_todo_unknown_id_returns_404(client):
    response = client.get_todo(
        _req("GET", route="todos/" + UNKNOWN_ID, route_params={"id": UNKNOWN_ID})
    )

    assert response.status_code == 404
    assert response.mimetype == "application/json"
    assert "error" in _json(response)


# ---------------------------------------------------------------------------
# PUT /api/todos/{id}
# ---------------------------------------------------------------------------


def test_put_todo_valid_update_returns_200_and_updated_item(client, requests_data):
    response = client.update_todo(
        _req("PUT", route="todos/" + OPEN_ID, route_params={"id": OPEN_ID}, body=requests_data["valid_update"])
    )

    assert response.status_code == 200
    assert response.mimetype == "application/json"
    body = _json(response)
    assert set(body.keys()) == ALL_FIELDS
    assert body["id"] == OPEN_ID
    assert body["title"] == "Buy oat milk"
    assert body["is_completed"] is True
    assert body["updated_at"] == FROZEN_NOW


def test_put_todo_valid_update_bumps_updated_at_in_repo(client, repo, requests_data, todos_data):
    original = next(t for t in todos_data if t["id"] == OPEN_ID)

    client.update_todo(
        _req("PUT", route="todos/" + OPEN_ID, route_params={"id": OPEN_ID}, body=requests_data["valid_update"])
    )

    stored = repo.get(OPEN_ID)
    assert stored["updated_at"] == FROZEN_NOW
    assert stored["updated_at"] != original["updated_at"]


def test_put_todo_partial_update_status_only_returns_200_and_preserves_title(client, requests_data, todos_data):
    original = next(t for t in todos_data if t["id"] == OPEN_ID)

    response = client.update_todo(
        _req(
            "PUT",
            route="todos/" + OPEN_ID,
            route_params={"id": OPEN_ID},
            body=requests_data["partial_update_status_only"],
        )
    )

    assert response.status_code == 200
    body = _json(response)
    assert body["title"] == original["title"]
    assert body["is_completed"] is True
    assert body["updated_at"] == FROZEN_NOW


def test_put_todo_empty_title_returns_400(client, requests_data):
    response = client.update_todo(
        _req(
            "PUT",
            route="todos/" + OPEN_ID,
            route_params={"id": OPEN_ID},
            body=requests_data["invalid_create_empty_title"],
        )
    )

    assert response.status_code == 400


def test_put_todo_whitespace_title_returns_400(client, requests_data):
    response = client.update_todo(
        _req(
            "PUT",
            route="todos/" + OPEN_ID,
            route_params={"id": OPEN_ID},
            body=requests_data["invalid_create_whitespace_title"],
        )
    )

    assert response.status_code == 400


def test_put_todo_wrong_type_title_returns_400(client, requests_data):
    response = client.update_todo(
        _req(
            "PUT",
            route="todos/" + OPEN_ID,
            route_params={"id": OPEN_ID},
            body=requests_data["invalid_create_wrong_type"],
        )
    )

    assert response.status_code == 400


def test_put_todo_invalid_title_does_not_mutate_repo(client, repo, requests_data, todos_data):
    original = next(dict(t) for t in todos_data if t["id"] == OPEN_ID)

    client.update_todo(
        _req(
            "PUT",
            route="todos/" + OPEN_ID,
            route_params={"id": OPEN_ID},
            body=requests_data["invalid_create_empty_title"],
        )
    )

    assert repo.get(OPEN_ID) == original


def test_put_todo_unknown_id_returns_404(client, requests_data):
    response = client.update_todo(
        _req(
            "PUT",
            route="todos/" + UNKNOWN_ID,
            route_params={"id": UNKNOWN_ID},
            body=requests_data["valid_update"],
        )
    )

    assert response.status_code == 404
    assert "error" in _json(response)


# ---------------------------------------------------------------------------
# DELETE /api/todos/{id}
# ---------------------------------------------------------------------------


def test_delete_todo_known_id_returns_204_and_empty_body(client):
    response = client.delete_todo(
        _req("DELETE", route="todos/" + KNOWN_ID, route_params={"id": KNOWN_ID})
    )

    assert response.status_code == 204
    assert response.get_body() in (b"", None)


def test_delete_todo_known_id_removes_item_from_repo(client, repo):
    client.delete_todo(_req("DELETE", route="todos/" + KNOWN_ID, route_params={"id": KNOWN_ID}))

    assert repo.get(KNOWN_ID) is None


def test_delete_todo_unknown_id_returns_404(client):
    response = client.delete_todo(
        _req("DELETE", route="todos/" + UNKNOWN_ID, route_params={"id": UNKNOWN_ID})
    )

    assert response.status_code == 404
    assert response.mimetype == "application/json"
    assert "error" in _json(response)
