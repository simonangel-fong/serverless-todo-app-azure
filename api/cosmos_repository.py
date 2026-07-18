"""Cosmos DB repository for the `todos` container.

Keeps the real `azure.cosmos.CosmosClient` out of the import-time path so tests can inject a
fake/mock container without a live Cosmos connection or network access. `function_app.py` calls
`get_container()` lazily (per invocation), and tests monkeypatch/override `get_container` (or
call `TodoRepository` directly with a fake container) to avoid ever constructing a real client.
"""

import os
from typing import Optional

from azure.cosmos import CosmosClient
from azure.cosmos.exceptions import CosmosResourceNotFoundError

_client: Optional[CosmosClient] = None
_container = None


def _build_client() -> CosmosClient:
    endpoint = os.environ["COSMOS_DB_ENDPOINT"]
    key = os.environ["COSMOS_DB_KEY"]
    return CosmosClient(endpoint, credential=key)


def get_container():
    """Lazily create (and cache) the Cosmos container client.

    Not called at module import time, so importing this module (or `function_app`) never
    requires Cosmos env vars / network access -- only actually handling a request does. Tests
    should bypass this entirely by constructing `TodoRepository` with a fake container.
    """
    global _client, _container
    if _container is None:
        if _client is None:
            _client = _build_client()
        database_name = os.environ["COSMOS_DB_DATABASE"]
        container_name = os.environ["COSMOS_DB_CONTAINER"]
        database = _client.get_database_client(database_name)
        _container = database.get_container_client(container_name)
    return _container


class TodoRepository:
    """Thin CRUD wrapper around a Cosmos container client.

    The container is injected (constructor param), never constructed internally -- this is
    what makes the repository unit-testable with a fake/in-memory container.
    """

    def __init__(self, container=None):
        self._container = container

    @property
    def container(self):
        if self._container is None:
            self._container = get_container()
        return self._container

    def list_all(self):
        query = "SELECT * FROM c"
        return list(self.container.query_items(query=query, enable_cross_partition_query=True))

    def get(self, todo_id: str):
        try:
            return self.container.read_item(item=todo_id, partition_key=todo_id)
        except CosmosResourceNotFoundError:
            return None

    def create(self, item: dict):
        return self.container.create_item(body=item)

    def upsert(self, item: dict):
        return self.container.upsert_item(body=item)

    def delete(self, todo_id: str) -> bool:
        try:
            self.container.delete_item(item=todo_id, partition_key=todo_id)
            return True
        except CosmosResourceNotFoundError:
            return False


def get_repository() -> TodoRepository:
    """Factory used by function_app.py handlers; tests construct TodoRepository(fake_container)
    directly instead of calling this."""
    return TodoRepository()
