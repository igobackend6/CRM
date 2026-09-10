from datetime import datetime, timezone
from uuid import uuid4

import pytest

from app.core.exceptions import NotFoundError
from app.repositories.leads import LeadRepository
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient


def test_list_for_workspace_returns_rows_and_total():
    workspace_id = uuid4()
    client = FakeSupabaseClient(
        table_responses={"leads": FakeResponse(data=[{"id": "1"}, {"id": "2"}], count=2)}
    )
    repo = LeadRepository(client)

    rows, total = repo.list_for_workspace(workspace_id, limit=20, offset=0)

    assert len(rows) == 2
    assert total == 2
    assert client.table_calls == ["leads"]


def test_get_for_workspace_raises_not_found_when_row_is_missing():
    client = FakeSupabaseClient(table_responses={"leads": FakeResponse(data=None)})
    repo = LeadRepository(client)

    with pytest.raises(NotFoundError):
        repo.get_for_workspace(uuid4(), uuid4())


def test_get_for_workspace_returns_the_row():
    lead_id = uuid4()
    client = FakeSupabaseClient(table_responses={"leads": FakeResponse(data={"id": str(lead_id), "name": "Acme"})})
    repo = LeadRepository(client)

    row = repo.get_for_workspace(uuid4(), lead_id)

    assert row["name"] == "Acme"


def test_create_for_workspace_returns_the_created_row():
    client = FakeSupabaseClient(table_responses={"leads": FakeResponse(data=[{"id": "1", "name": "New Lead"}])})
    repo = LeadRepository(client)

    row = repo.create_for_workspace(uuid4(), {"name": "New Lead"})

    assert row["name"] == "New Lead"


def test_update_for_workspace_raises_not_found_when_rls_filters_out_the_row():
    client = FakeSupabaseClient(table_responses={"leads": FakeResponse(data=[])})
    repo = LeadRepository(client)

    with pytest.raises(NotFoundError):
        repo.update_for_workspace(uuid4(), uuid4(), {"name": "Renamed"})


def test_soft_delete_sets_deleted_at_via_update():
    client = FakeSupabaseClient(table_responses={"leads": FakeResponse(data=[{"id": "1", "deleted_at": "now"}])})
    repo = LeadRepository(client)

    row = repo.soft_delete_for_workspace(uuid4(), uuid4())

    assert row["deleted_at"] is not None


# ---- Phase 17: count_converted ----


def test_count_converted_returns_the_configured_count():
    client = FakeSupabaseClient(table_responses={"leads": FakeResponse(data=[], count=5)})
    repo = LeadRepository(client)

    assert repo.count_converted(uuid4()) == 5


def test_count_converted_accepts_a_converted_at_window():
    client = FakeSupabaseClient(table_responses={"leads": FakeResponse(data=[], count=2)})
    repo = LeadRepository(client)

    count = repo.count_converted(uuid4(), since="2026-01-01T00:00:00+00:00", until="2026-02-01T00:00:00+00:00")

    assert count == 2
    assert client.table_calls == ["leads"]


def test_count_converted_defaults_to_zero_when_nothing_matches():
    client = FakeSupabaseClient(table_responses={"leads": FakeResponse(data=[], count=None)})
    repo = LeadRepository(client)

    assert repo.count_converted(uuid4()) == 0


# ---- Phase 19: list_rechurn_candidates ----


def test_list_rechurn_candidates_returns_rows_and_total():
    client = FakeSupabaseClient(table_responses={"leads": FakeResponse(data=[{"id": "1"}], count=1)})
    repo = LeadRepository(client)

    rows, total = repo.list_rechurn_candidates(uuid4(), updated_before=datetime.now(timezone.utc))

    assert len(rows) == 1
    assert total == 1
    assert client.table_calls == ["leads"]


def test_list_rechurn_candidates_lost_segment_short_circuits_when_no_lost_status_configured():
    """§"If 'lost' cannot safely be determined ... document the
    limitation and use the smallest safe workspace-scoped approach" —
    never guesses a fallback status; returns empty without even
    querying `leads`."""
    client = FakeSupabaseClient(table_responses={"leads": FakeResponse(data=[{"id": "1"}], count=1)})
    repo = LeadRepository(client)

    rows, total = repo.list_rechurn_candidates(uuid4(), segment="lost", lost_status_ids=[])

    assert rows == []
    assert total == 0
    assert client.table_calls == []


def test_list_rechurn_candidates_lost_segment_queries_leads_when_lost_statuses_exist():
    client = FakeSupabaseClient(table_responses={"leads": FakeResponse(data=[{"id": "1"}], count=1)})
    repo = LeadRepository(client)

    rows, total = repo.list_rechurn_candidates(uuid4(), segment="lost", lost_status_ids=[str(uuid4())])

    assert len(rows) == 1
    assert client.table_calls == ["leads"]


def test_list_rechurn_candidates_inactive_segment_queries_leads():
    client = FakeSupabaseClient(table_responses={"leads": FakeResponse(data=[{"id": "1"}], count=1)})
    repo = LeadRepository(client)

    rows, total = repo.list_rechurn_candidates(uuid4(), segment="inactive", updated_before=datetime.now(timezone.utc))

    assert len(rows) == 1
    assert client.table_calls == ["leads"]


def test_list_rechurn_candidates_default_segment_unions_inactive_and_lost():
    """`segment=None` (the default queue view) still issues exactly one
    `leads` query — the OR is expressed inside the query, not as two
    separate round trips."""
    client = FakeSupabaseClient(table_responses={"leads": FakeResponse(data=[{"id": "1"}, {"id": "2"}], count=2)})
    repo = LeadRepository(client)

    rows, total = repo.list_rechurn_candidates(
        uuid4(), updated_before=datetime.now(timezone.utc), lost_status_ids=[str(uuid4())]
    )

    assert len(rows) == 2
    assert total == 2
    assert client.table_calls == ["leads"]


def test_list_rechurn_candidates_accepts_every_optional_filter_without_error():
    client = FakeSupabaseClient(table_responses={"leads": FakeResponse(data=[], count=0)})
    repo = LeadRepository(client)

    rows, total = repo.list_rechurn_candidates(
        uuid4(),
        updated_before=datetime.now(timezone.utc),
        status_id=uuid4(),
        source_id=uuid4(),
        assigned_member_id=uuid4(),
        priority="high",
        search="acme",
        limit=10,
        offset=5,
    )

    assert rows == []
    assert total == 0
