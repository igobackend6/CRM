from uuid import uuid4

import pytest

from app.core.exceptions import ConflictError
from app.repositories.allocations import AllocationRepository
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient


def test_list_for_lead_returns_rows():
    client = FakeSupabaseClient(table_responses={"allocations": FakeResponse(data=[{"id": "a1"}, {"id": "a2"}])})
    repo = AllocationRepository(client)

    rows = repo.list_for_lead(uuid4(), uuid4())

    assert len(rows) == 2
    assert client.table_calls == ["allocations"]


def test_create_returns_the_inserted_row():
    client = FakeSupabaseClient(table_responses={"allocations": FakeResponse(data=[{"id": "a1", "status": "new"}])})
    repo = AllocationRepository(client)

    row = repo.create(uuid4(), uuid4(), assigned_member_id=str(uuid4()), assigned_by_member_id=str(uuid4()))

    assert row["status"] == "new"


def test_create_raises_conflict_when_insert_returns_no_rows():
    client = FakeSupabaseClient(table_responses={"allocations": FakeResponse(data=[])})
    repo = AllocationRepository(client)

    with pytest.raises(ConflictError):
        repo.create(uuid4(), uuid4(), assigned_member_id=str(uuid4()), assigned_by_member_id=str(uuid4()))


def test_list_recent_for_lead_returns_rows():
    """Added in Phase 8 for the unified timeline."""
    client = FakeSupabaseClient(table_responses={"allocations": FakeResponse(data=[{"id": "a1"}])})
    repo = AllocationRepository(client)

    rows = repo.list_recent_for_lead(uuid4(), uuid4(), limit=5)

    assert len(rows) == 1


def test_count_for_lead_returns_the_configured_count():
    client = FakeSupabaseClient(table_responses={"allocations": FakeResponse(data=[{"id": "a1"}], count=4)})
    repo = AllocationRepository(client)

    assert repo.count_for_lead(uuid4(), uuid4()) == 4
