from typing import Any
from uuid import UUID

from supabase import Client

from app.core.exceptions import NotFoundError


class BaseRepository:
    """Generic Supabase-table data access. Deliberately table-agnostic
    and CRUD-only — it knows nothing about leads/calls/any CRM entity;
    feature phases subclass this (setting `table_name`) rather than
    calling `client.table(...)` directly from a service, so every data
    access goes through one narrow, consistent surface (per
    docs/architecture/03-python-backend-architecture.md §3: "services
    never call Supabase directly").

    Always constructed with a request-scoped, user-authenticated client
    (see core/supabase_client.get_user_scoped_client) unless a subclass
    has a specific, documented reason to use the privileged service-role
    client instead — RLS is what actually enforces access either way,
    this class does not.
    """

    table_name: str

    def __init__(self, client: Client):
        self._client = client

    def get_by_id(self, id: UUID) -> dict[str, Any]:
        response = self._client.table(self.table_name).select("*").eq("id", str(id)).maybe_single().execute()
        if response is None or response.data is None:
            raise NotFoundError(f"{self.table_name} {id} not found.")
        return response.data

    def list(self, *, filters: dict[str, Any] | None = None, limit: int = 100, offset: int = 0) -> list[dict[str, Any]]:
        query = self._client.table(self.table_name).select("*")
        for column, value in (filters or {}).items():
            query = query.eq(column, value)
        response = query.range(offset, offset + limit - 1).execute()
        return response.data or []

    def insert(self, data: dict[str, Any]) -> dict[str, Any]:
        response = self._client.table(self.table_name).insert(data).execute()
        return response.data[0]

    def update(self, id: UUID, data: dict[str, Any]) -> dict[str, Any]:
        response = self._client.table(self.table_name).update(data).eq("id", str(id)).execute()
        if not response.data:
            raise NotFoundError(f"{self.table_name} {id} not found (or not permitted to update).")
        return response.data[0]
