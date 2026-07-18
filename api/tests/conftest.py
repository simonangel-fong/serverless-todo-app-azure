"""Shared pytest fixtures for the Todo API test suite.

Puts `api/` on `sys.path` so `import function_app` and `import cosmos_repository` work the same
way they do at runtime (Azure Functions loads them from the `api/` root), without a live Cosmos
connection or network access anywhere in the suite.
"""

import json
import sys
import uuid
from pathlib import Path

import pytest
from azure.cosmos.exceptions import CosmosResourceNotFoundError

API_ROOT = Path(__file__).resolve().parent.parent
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

FIXTURES_DIR = Path(__file__).resolve().parent / "fixtures"

# Deterministic values used to freeze GUID/clock generation in tests that exercise create/update.
FROZEN_NEW_ID = "99999999-9999-9999-9999-999999999999"
FROZEN_NOW = "2026-07-18T12:00:00Z"


def _load_fixture(name: str):
    with open(FIXTURES_DIR / name, encoding="utf-8") as f:
        return json.load(f)


@pytest.fixture
def todos_data():
    """Fresh copy of the four seed todos, per test."""
    return _load_fixture("todos.json")


@pytest.fixture
def requests_data():
    return _load_fixture("requests.json")


class FakeContainer:
    """In-memory stand-in for a Cosmos container client.

    Implements just the surface `TodoRepository` calls: query_items, read_item, create_item,
    upsert_item, delete_item. Raises `CosmosResourceNotFoundError` to mirror real Cosmos SDK
    behavior on missing ids.
    """

    def __init__(self, seed_items=None):
        self._items = {item["id"]: dict(item) for item in (seed_items or [])}

    def query_items(self, query, enable_cross_partition_query=True):
        return list(dict(v) for v in self._items.values())

    def read_item(self, item, partition_key):
        if item not in self._items:
            raise CosmosResourceNotFoundError()
        return dict(self._items[item])

    def create_item(self, body):
        self._items[body["id"]] = dict(body)
        return dict(body)

    def upsert_item(self, body):
        self._items[body["id"]] = dict(body)
        return dict(body)

    def delete_item(self, item, partition_key):
        if item not in self._items:
            raise CosmosResourceNotFoundError()
        del self._items[item]


@pytest.fixture
def fake_container(todos_data):
    return FakeContainer(seed_items=todos_data)


@pytest.fixture
def repo(fake_container):
    import cosmos_repository

    return cosmos_repository.TodoRepository(fake_container)


@pytest.fixture
def client(repo, monkeypatch):
    """Import function_app with its `get_repository()` factory patched to always return the
    fake-backed repository, and its GUID/clock generation frozen for determinism."""
    import function_app

    monkeypatch.setattr(function_app, "get_repository", lambda: repo)
    monkeypatch.setattr(function_app.uuid, "uuid4", lambda: uuid.UUID(FROZEN_NEW_ID))
    monkeypatch.setattr(function_app, "_utc_now_iso", lambda: FROZEN_NOW)
    return function_app
