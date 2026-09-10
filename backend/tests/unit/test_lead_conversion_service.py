from uuid import uuid4

import pytest

import app.services.leads.service as lead_service_module
from app.core.exceptions import ConflictError, NotFoundError
from app.services.leads import LeadService
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
LEAD_ID = str(uuid4())
ACTOR_ID = str(uuid4())
ASSIGNEE_ID = str(uuid4())


def _lead_row(*, is_customer=False, assigned_member_id=ASSIGNEE_ID):
    return {
        "id": LEAD_ID,
        "workspace_id": str(WORKSPACE_ID),
        "name": "Acme Corp",
        "phone": "+15551234567",
        "email": "acme@example.com",
        "priority": "medium",
        "status_id": str(uuid4()),
        "source_id": None,
        "assigned_member_id": assigned_member_id,
        "created_by_member_id": ACTOR_ID,
        "is_customer": is_customer,
        "converted_at": None,
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }


def _client(**overrides):
    # NOTE on the "leads" fixture: convert_to_customer() reads the lead
    # (get_for_workspace) BEFORE writing it (update_for_workspace), and
    # both calls hit the "leads" table — per fake_supabase.py's own
    # docstring, one configured FakeResponse is shared across every call
    # to the same table name, so it cannot represent a genuinely
    # different "before" vs "after" row within a single test (unlike a
    # real Postgres UPDATE). Every test here therefore configures the
    # lead's *starting* is_customer value and asserts on side effects
    # (which table/RPC calls happened, notify() arguments, the
    # unconditionally-preserved fields like id/name/phone) rather than on
    # the returned row's is_customer/converted_at, which this fake cannot
    # honestly simulate flipping mid-call. The ConflictError guard itself
    # IS exercised faithfully, since it only depends on the (single,
    # consistent) "before" value.
    table_responses = {
        "lead_statuses": FakeResponse(data=[]),
        "lead_sources": FakeResponse(data=[]),
        "lead_tags": FakeResponse(data=[]),
        "leads": FakeResponse(data=[_lead_row()]),
        "workspace_members": FakeResponse(data=[{"id": ASSIGNEE_ID, "profile": {"full_name": "Rep One"}}]),
        "interactions": FakeResponse(data=[{"id": str(uuid4()), "type": "status_change", "payload": {}}]),
    }
    table_responses.update(overrides.pop("table_responses", {}))
    rpc_responses = {"current_member_id": ACTOR_ID}
    rpc_responses.update(overrides.pop("rpc_responses", {}))
    return FakeSupabaseClient(table_responses=table_responses, rpc_responses=rpc_responses)


def _capture_notify(monkeypatch):
    calls = []
    monkeypatch.setattr(lead_service_module, "notify", lambda workspace_id, **kwargs: calls.append(kwargs))
    return calls


def test_convert_to_customer_succeeds_for_a_not_yet_converted_lead():
    client = _client()
    service = LeadService(client)

    result = service.convert_to_customer(WORKSPACE_ID, LEAD_ID)

    assert "leads" in client.table_calls


def test_convert_to_customer_preserves_the_lead_id_and_its_existing_data():
    client = _client()
    service = LeadService(client)

    result = service.convert_to_customer(WORKSPACE_ID, LEAD_ID)

    # Same id, same name/phone/email — a conversion never creates a new
    # record or copies data elsewhere (Phase 18 §"No new customer record").
    assert result["id"] == LEAD_ID
    assert result["name"] == "Acme Corp"
    assert result["phone"] == "+15551234567"


def test_convert_to_customer_rejects_a_lead_that_is_already_a_customer(monkeypatch):
    """Idempotent-safe: repeated conversion is a clear 409 conflict, not
    a silent re-write or a duplicate side effect."""
    calls = _capture_notify(monkeypatch)
    client = _client(table_responses={"leads": FakeResponse(data=[_lead_row(is_customer=True)])})
    service = LeadService(client)

    with pytest.raises(ConflictError):
        service.convert_to_customer(WORKSPACE_ID, LEAD_ID)

    # Never reaches the point of writing a second conversion interaction
    # or notification for an already-converted lead.
    assert calls == []
    assert "interactions" not in client.table_calls


def test_convert_to_customer_raises_not_found_for_a_missing_or_invisible_lead():
    client = _client(table_responses={"leads": FakeResponse(data=None)})
    service = LeadService(client)

    with pytest.raises(NotFoundError):
        service.convert_to_customer(WORKSPACE_ID, LEAD_ID)


def test_convert_to_customer_records_a_status_change_interaction():
    client = _client()
    service = LeadService(client)

    service.convert_to_customer(WORKSPACE_ID, LEAD_ID)

    assert "interactions" in client.table_calls


def test_convert_to_customer_never_trusts_a_client_supplied_actor():
    """convert_to_customer()'s signature takes no actor parameter at all —
    the acting member always comes from current_member_id()."""
    client = _client()
    service = LeadService(client)

    service.convert_to_customer(WORKSPACE_ID, LEAD_ID)

    assert ("current_member_id", {"p_workspace_id": str(WORKSPACE_ID)}) in client.rpc_calls


def test_convert_to_customer_notifies_the_assigned_member(monkeypatch):
    calls = _capture_notify(monkeypatch)
    client = _client(table_responses={"leads": FakeResponse(data=[_lead_row(assigned_member_id=ASSIGNEE_ID)])})
    service = LeadService(client)

    service.convert_to_customer(WORKSPACE_ID, LEAD_ID)

    assert len(calls) == 1
    assert calls[0]["recipient_member_id"] == ASSIGNEE_ID
    assert calls[0]["related_entity_type"] == "lead"
    assert calls[0]["related_entity_id"] == LEAD_ID


def test_convert_to_customer_does_not_notify_when_the_actor_is_the_assignee(monkeypatch):
    calls = _capture_notify(monkeypatch)
    client = _client(table_responses={"leads": FakeResponse(data=[_lead_row(assigned_member_id=ACTOR_ID)])})
    service = LeadService(client)

    service.convert_to_customer(WORKSPACE_ID, LEAD_ID)

    assert calls == []


def test_convert_to_customer_does_not_notify_an_unassigned_lead(monkeypatch):
    calls = _capture_notify(monkeypatch)
    client = _client(table_responses={"leads": FakeResponse(data=[_lead_row(assigned_member_id=None)])})
    service = LeadService(client)

    service.convert_to_customer(WORKSPACE_ID, LEAD_ID)

    assert calls == []
