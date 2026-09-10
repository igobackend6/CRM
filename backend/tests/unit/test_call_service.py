from uuid import uuid4

import pytest

import app.services.calls.service as call_service_module
from app.core.exceptions import NotFoundError, ValidationError
from app.services.calls.service import CallService
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
LEAD_ID = uuid4()
AGENT_ID = uuid4()
OWNER_ID = uuid4()
OUTCOME_ID = uuid4()
CALL_ID = uuid4()


def _lead_row(assigned_member_id=None):
    return {
        "id": str(LEAD_ID),
        "workspace_id": str(WORKSPACE_ID),
        "name": "Acme Corp",
        "assigned_member_id": str(assigned_member_id) if assigned_member_id else None,
    }


def _call_row(**overrides):
    row = {
        "id": str(CALL_ID),
        "workspace_id": str(WORKSPACE_ID),
        "lead_id": str(LEAD_ID),
        "agent_member_id": str(AGENT_ID),
        "direction": "outbound",
        "state": "ENDED",
        "outcome_id": None,
        "started_at": "2026-01-01T00:00:00Z",
        "connected_at": None,
        "ended_at": None,
        "duration_seconds": None,
        "notes": None,
        "created_at": "2026-01-01T00:00:00Z",
    }
    row.update(overrides)
    return row


def _client(**table_responses):
    return FakeSupabaseClient(
        table_responses={
            "leads": FakeResponse(data=[_lead_row()]),
            "calls": FakeResponse(data=[_call_row()], count=1),
            "workspace_members": FakeResponse(data=[{"id": str(AGENT_ID), "profile": {"full_name": "Agent Smith"}}]),
            "call_outcomes": FakeResponse(data=[{"id": str(OUTCOME_ID), "name": "Connected", "code": "connected", "is_positive": True, "is_default": False}]),
            **table_responses,
        },
        rpc_responses={"current_member_id": str(AGENT_ID)},
    )


def test_list_calls_enriches_lead_and_agent():
    client = _client()
    service = CallService(client)

    items, total = service.list_calls(WORKSPACE_ID, lead_id=None, direction=None, limit=20, offset=0)

    assert total == 1
    assert items[0]["lead"]["name"] == "Acme Corp"
    assert items[0]["agent_member"]["full_name"] == "Agent Smith"


def test_get_call_returns_enriched_row():
    client = _client()
    service = CallService(client)

    item = service.get_call(WORKSPACE_ID, CALL_ID)

    assert item["id"] == str(CALL_ID)
    assert item["lead"]["id"] == str(LEAD_ID)


def test_get_call_raises_not_found_for_missing_call():
    client = _client(calls=FakeResponse(data=None))
    service = CallService(client)

    with pytest.raises(NotFoundError):
        service.get_call(WORKSPACE_ID, uuid4())


def test_list_lead_calls_validates_the_lead_belongs_to_the_workspace():
    """Cross-workspace/invalid lead: get_for_workspace 404s before any
    calls query runs (§9 'validate lead belongs to the requested
    workspace')."""
    client = _client(leads=FakeResponse(data=None))
    service = CallService(client)

    with pytest.raises(NotFoundError):
        service.list_lead_calls(WORKSPACE_ID, uuid4())


def test_list_lead_calls_returns_enriched_rows():
    client = _client()
    service = CallService(client)

    items = service.list_lead_calls(WORKSPACE_ID, LEAD_ID)

    assert len(items) == 1
    assert items[0]["lead"]["id"] == str(LEAD_ID)


def test_create_call_never_trusts_a_client_supplied_agent():
    """§4/§9: agent_member_id always comes from current_member_id(), never
    from the request body (CallCreate doesn't even expose the field, but
    this proves the service itself derives it server-side)."""
    client = _client()
    service = CallService(client)

    service.create_call(WORKSPACE_ID, {"lead_id": LEAD_ID, "direction": "outbound"})

    assert ("current_member_id", {"p_workspace_id": str(WORKSPACE_ID)}) in client.rpc_calls


def test_create_call_rejects_a_lead_from_another_workspace():
    client = _client(leads=FakeResponse(data=None))
    service = CallService(client)

    with pytest.raises(NotFoundError):
        service.create_call(WORKSPACE_ID, {"lead_id": uuid4(), "direction": "outbound"})


def test_create_call_rejects_an_invalid_outcome():
    client = _client(call_outcomes=FakeResponse(data=None))
    service = CallService(client)

    with pytest.raises(ValidationError):
        service.create_call(WORKSPACE_ID, {"lead_id": LEAD_ID, "direction": "outbound", "outcome_id": uuid4()})


def test_create_call_derives_connected_and_ended_at_from_duration():
    """duration_seconds is never inserted directly (it's a Postgres
    GENERATED column) — the service instead derives connected_at/
    ended_at from started_at + duration, letting the database compute
    the authoritative duration itself."""
    captured: dict = {}

    class _CapturingCalls:
        def create_for_workspace(self, workspace_id, data):
            captured.update(data)
            return _call_row(**data)

    client = _client()
    service = CallService(client)
    service._calls = _CapturingCalls()

    service.create_call(
        WORKSPACE_ID,
        {"lead_id": LEAD_ID, "direction": "outbound", "started_at": "2026-01-01T10:00:00+00:00", "duration_seconds": 90},
    )

    assert captured["connected_at"] == "2026-01-01T10:00:00+00:00"
    assert captured["ended_at"] == "2026-01-01T10:01:30+00:00"
    assert captured["state"] == "ENDED"
    assert "duration_seconds" not in captured


def test_create_call_leaves_connected_and_ended_at_null_without_duration():
    captured: dict = {}

    class _CapturingCalls:
        def create_for_workspace(self, workspace_id, data):
            captured.update(data)
            return _call_row(**data)

    client = _client()
    service = CallService(client)
    service._calls = _CapturingCalls()

    service.create_call(WORKSPACE_ID, {"lead_id": LEAD_ID, "direction": "inbound"})

    assert "connected_at" not in captured
    assert "ended_at" not in captured


def test_create_call_notifies_the_lead_owner_when_a_teammate_logs_it(monkeypatch):
    calls: list[dict] = []
    monkeypatch.setattr(call_service_module, "notify", lambda workspace_id, **kwargs: calls.append(kwargs))
    client = _client(leads=FakeResponse(data=[_lead_row(assigned_member_id=OWNER_ID)]))
    service = CallService(client)

    # rpc "current_member_id" defaults to AGENT_ID — different from the
    # lead's owner (OWNER_ID), so this call was logged by a teammate.
    service.create_call(WORKSPACE_ID, {"lead_id": LEAD_ID, "direction": "outbound"})

    assert len(calls) == 1
    assert calls[0]["recipient_member_id"] == str(OWNER_ID)
    assert calls[0]["type"] == "system"
    assert calls[0]["related_entity_type"] == "call"


def test_create_call_does_not_notify_when_the_owner_logs_their_own_call(monkeypatch):
    calls: list[dict] = []
    monkeypatch.setattr(call_service_module, "notify", lambda workspace_id, **kwargs: calls.append(kwargs))
    client = _client(leads=FakeResponse(data=[_lead_row(assigned_member_id=AGENT_ID)]))
    service = CallService(client)

    service.create_call(WORKSPACE_ID, {"lead_id": LEAD_ID, "direction": "outbound"})

    assert calls == []


def test_create_call_does_not_notify_when_the_lead_has_no_owner(monkeypatch):
    calls: list[dict] = []
    monkeypatch.setattr(call_service_module, "notify", lambda workspace_id, **kwargs: calls.append(kwargs))
    client = _client(leads=FakeResponse(data=[_lead_row(assigned_member_id=None)]))
    service = CallService(client)

    service.create_call(WORKSPACE_ID, {"lead_id": LEAD_ID, "direction": "outbound"})

    assert calls == []


def test_list_outcomes_returns_workspace_outcomes():
    client = _client()
    service = CallService(client)

    outcomes = service.list_outcomes(WORKSPACE_ID)

    assert outcomes[0]["code"] == "connected"
