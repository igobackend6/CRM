from uuid import uuid4

import pytest
from postgrest.exceptions import APIError

from app.core.exceptions import ConflictError, NotFoundError
from app.repositories.message_templates import MessageTemplateRepository
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()


def _row(**overrides):
    row = {
        "id": str(uuid4()),
        "workspace_id": str(WORKSPACE_ID),
        "name": "Follow-up",
        "body": "Hello {{name}}, checking in.",
        "created_by_member_id": str(uuid4()),
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }
    row.update(overrides)
    return row


class _ConflictClient(FakeSupabaseClient):
    """Raises APIError(23505) from the query builder's own .execute() —
    the shape a real unique_violation surfaces as through postgrest-py."""

    def table(self, name: str):
        builder = super().table(name)
        original_execute = builder.execute

        def _execute():
            raise APIError({"code": "23505", "message": "duplicate key"})

        builder.execute = _execute
        return builder


def test_list_for_workspace_returns_rows():
    client = FakeSupabaseClient(table_responses={"message_templates": FakeResponse(data=[_row(), _row()])})
    repo = MessageTemplateRepository(client)
    assert len(repo.list_for_workspace(WORKSPACE_ID)) == 2


def test_create_inserts_a_row():
    client = FakeSupabaseClient(table_responses={"message_templates": FakeResponse(data=[_row()])})
    repo = MessageTemplateRepository(client)
    row = repo.create(WORKSPACE_ID, name="Follow-up", body="Hi {{name}}", created_by_member_id=uuid4())
    assert row["name"] == "Follow-up"


def test_create_raises_conflict_on_duplicate_name():
    repo = MessageTemplateRepository(_ConflictClient())
    with pytest.raises(ConflictError):
        repo.create(WORKSPACE_ID, name="Follow-up", body="Hi", created_by_member_id=uuid4())


def test_update_returns_the_updated_row():
    client = FakeSupabaseClient(table_responses={"message_templates": FakeResponse(data=[_row(name="Renamed")])})
    repo = MessageTemplateRepository(client)
    row = repo.update(WORKSPACE_ID, uuid4(), {"name": "Renamed"})
    assert row["name"] == "Renamed"


def test_update_raises_not_found_when_no_row_matched():
    client = FakeSupabaseClient(table_responses={"message_templates": FakeResponse(data=[])})
    repo = MessageTemplateRepository(client)
    with pytest.raises(NotFoundError):
        repo.update(WORKSPACE_ID, uuid4(), {"name": "Renamed"})


def test_update_raises_conflict_on_duplicate_name():
    repo = MessageTemplateRepository(_ConflictClient())
    with pytest.raises(ConflictError):
        repo.update(WORKSPACE_ID, uuid4(), {"name": "Existing"})


def test_delete_raises_not_found_when_no_row_matched():
    client = FakeSupabaseClient(table_responses={"message_templates": FakeResponse(data=[])})
    repo = MessageTemplateRepository(client)
    with pytest.raises(NotFoundError):
        repo.delete(WORKSPACE_ID, uuid4())


def test_delete_succeeds_when_a_row_matched():
    client = FakeSupabaseClient(table_responses={"message_templates": FakeResponse(data=[_row()])})
    repo = MessageTemplateRepository(client)
    repo.delete(WORKSPACE_ID, uuid4())  # must not raise
