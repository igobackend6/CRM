from uuid import uuid4

import pytest

from app.core.exceptions import ValidationError
from app.services.rechurn.service import RechurnService
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
MEMBER_ID = str(uuid4())
STATUS_ID = str(uuid4())
LOST_STATUS_ID = str(uuid4())


def _lead_row(**overrides):
    row = {
        "id": str(uuid4()),
        "workspace_id": str(WORKSPACE_ID),
        "name": "Acme Corp",
        "phone": "+15551234567",
        "email": "acme@example.com",
        "priority": "medium",
        "status_id": STATUS_ID,
        "source_id": None,
        "assigned_member_id": MEMBER_ID,
        "is_customer": False,
        "updated_at": "2026-01-01T00:00:00Z",
    }
    row.update(overrides)
    return row


def _client(**overrides):
    """One `leads` fixture is shared by every differently-filtered query
    this service issues (the segment/inactive-days/priority/etc. filters
    themselves) — same documented `FakeSupabaseClient` limitation every
    other service test file in this codebase already relies on (see
    test_dashboard_service.py's `_client` docstring): this proves the
    service builds and wires the right queries, not that Postgres itself
    would return different rows for different filters."""
    table_responses = {
        "lead_statuses": FakeResponse(
            data=[
                {"id": STATUS_ID, "name": "New", "code": "new", "sort_order": 10, "stage": "in_progress", "is_default": True},
                {"id": LOST_STATUS_ID, "name": "Lost", "code": "lost", "sort_order": 90, "stage": "closed_lost", "is_default": False},
            ]
        ),
        "lead_sources": FakeResponse(data=[]),
        "leads": FakeResponse(data=[_lead_row()], count=1),
        "follow_ups": FakeResponse(data=[]),
        "workspace_members": FakeResponse(data=[{"id": MEMBER_ID, "profile": {"full_name": "Jamie Rep"}}]),
    }
    table_responses.update(overrides.pop("table_responses", {}))
    return FakeSupabaseClient(table_responses=table_responses, **overrides)


# ---- validation ----


def test_list_queue_rejects_an_unknown_segment():
    with pytest.raises(ValidationError):
        RechurnService(_client()).list_queue(WORKSPACE_ID, segment="won")


def test_list_queue_rejects_a_non_positive_inactive_days():
    with pytest.raises(ValidationError):
        RechurnService(_client()).list_queue(WORKSPACE_ID, inactive_days=0)


def test_list_queue_rejects_an_invalid_priority():
    with pytest.raises(ValidationError):
        RechurnService(_client()).list_queue(WORKSPACE_ID, priority="urgentish")


def test_list_queue_rejects_a_status_id_outside_this_workspace():
    client = _client(table_responses={"lead_statuses": FakeResponse(data=[])})
    with pytest.raises(ValidationError):
        RechurnService(client).list_queue(WORKSPACE_ID, status_id=uuid4())


def test_list_queue_rejects_a_source_id_outside_this_workspace():
    client = _client(table_responses={"lead_sources": FakeResponse(data=None)})
    with pytest.raises(ValidationError):
        RechurnService(client).list_queue(WORKSPACE_ID, source_id=uuid4())


def test_list_queue_rejects_an_assigned_member_outside_this_workspace():
    client = _client(table_responses={"workspace_members": FakeResponse(data=None)})
    with pytest.raises(ValidationError):
        RechurnService(client).list_queue(WORKSPACE_ID, assigned_member_id=uuid4())


# ---- shape / enrichment ----


def test_list_queue_returns_enriched_cards():
    client = _client()
    items, total = RechurnService(client).list_queue(WORKSPACE_ID)

    assert total == 1
    card = items[0]
    assert card["name"] == "Acme Corp"
    assert card["status"]["code"] == "new"
    assert card["assigned_member"] == {"id": MEMBER_ID, "full_name": "Jamie Rep"}
    assert card["is_customer"] is False
    assert card["last_activity_at"] == "2026-01-01T00:00:00Z"
    assert card["next_follow_up"] is None


def test_list_queue_attaches_the_next_pending_follow_up():
    lead = _lead_row()
    client = _client(
        table_responses={
            "leads": FakeResponse(data=[lead], count=1),
            "follow_ups": FakeResponse(data=[{"id": "f1", "lead_id": lead["id"], "type": "call", "due_at": "2026-02-01T09:00:00Z"}]),
        }
    )

    items, _ = RechurnService(client).list_queue(WORKSPACE_ID)

    assert items[0]["next_follow_up"] == {"id": "f1", "lead_id": lead["id"], "type": "call", "due_at": "2026-02-01T09:00:00Z"}


def test_list_queue_on_an_empty_workspace_returns_no_items_and_skips_the_follow_up_lookup():
    client = _client(table_responses={"leads": FakeResponse(data=[], count=0)})

    items, total = RechurnService(client).list_queue(WORKSPACE_ID)

    assert items == []
    assert total == 0
    assert "follow_ups" not in client.table_calls


def test_list_queue_accepts_the_inactive_and_lost_segments():
    client = _client()
    service = RechurnService(client)

    inactive_items, _ = service.list_queue(WORKSPACE_ID, segment="inactive")
    lost_items, _ = service.list_queue(WORKSPACE_ID, segment="lost")

    assert len(inactive_items) == 1
    assert len(lost_items) == 1


def test_list_queue_lost_segment_returns_nothing_when_workspace_has_no_lost_status():
    """No status configured with `is_lost = true` — the service resolves
    an empty `lost_status_ids` list, and the repository short-circuits
    rather than guessing a fallback status (§"document the limitation
    and use the smallest safe workspace-scoped approach")."""
    client = _client(
        table_responses={
            "lead_statuses": FakeResponse(
                data=[{"id": STATUS_ID, "name": "New", "code": "new", "sort_order": 10, "stage": "in_progress", "is_default": True}]
            )
        }
    )

    items, total = RechurnService(client).list_queue(WORKSPACE_ID, segment="lost")

    assert items == []
    assert total == 0


def test_list_queue_accepts_a_custom_inactive_days_threshold():
    client = _client()
    items, total = RechurnService(client).list_queue(WORKSPACE_ID, inactive_days=90)

    assert total == 1
