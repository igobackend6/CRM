from uuid import uuid4

import pytest

import app.services.leads.service as lead_service_module
from app.core.exceptions import ValidationError
from app.services.leads import LeadService
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
LEAD_ID = str(uuid4())
ASSIGNER_ID = str(uuid4())
REP1_ID = str(uuid4())
REP2_ID = str(uuid4())


def _lead_row(assigned_member_id=REP1_ID):
    return {
        "id": LEAD_ID,
        "workspace_id": str(WORKSPACE_ID),
        "name": "Acme Corp",
        "phone": None,
        "email": None,
        "priority": "medium",
        "status_id": str(uuid4()),
        "source_id": None,
        "assigned_member_id": assigned_member_id,
        "created_by_member_id": ASSIGNER_ID,
        "is_customer": False,
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }


def _client(**overrides):
    table_responses = {
        "lead_statuses": FakeResponse(data=[]),
        "lead_sources": FakeResponse(data=[]),
        "lead_tags": FakeResponse(data=[]),
        # List-shaped: assign_lead() hits "leads" both as a single-row
        # maybe_single() visibility check and as a list-returning
        # update() — see fake_supabase.py's auto-unwrap for why one
        # list-shaped fixture correctly serves both.
        "leads": FakeResponse(data=[_lead_row()]),
        "workspace_members": FakeResponse(data=[{"id": REP2_ID, "profile": {"full_name": "Rep Two"}}]),
        "allocations": FakeResponse(data=[{"id": str(uuid4()), "status": "new"}]),
    }
    table_responses.update(overrides.pop("table_responses", {}))
    rpc_responses = {"current_member_id": ASSIGNER_ID}
    rpc_responses.update(overrides.pop("rpc_responses", {}))
    return FakeSupabaseClient(table_responses=table_responses, rpc_responses=rpc_responses)


def test_list_workspace_members_shapes_id_and_full_name_only():
    """Confirms the service delegates to MemberRepository.list_active()
    and returns only id/full_name (never phone/avatar_url). The
    fake client can't verify the real `.eq('status', 'active')` filter
    reached Postgres — that's asserted by reading
    repositories/lead_reference.py's list_active(), not by this mock."""
    client = _client(
        table_responses={
            "workspace_members": FakeResponse(
                data=[{"id": REP1_ID, "profile": {"full_name": "Rep One"}}, {"id": REP2_ID, "profile": {"full_name": "Rep Two"}}]
            )
        }
    )
    service = LeadService(client)

    members = service.list_workspace_members(WORKSPACE_ID)

    assert [m["full_name"] for m in members] == ["Rep One", "Rep Two"]
    assert set(members[0].keys()) == {"id", "full_name"}


def test_assign_lead_updates_the_lead_and_leaves_the_side_effects_to_the_trigger():
    """As of 000027_lead_assignment_side_effects.sql the allocations
    history row and the assignee notification are written by the
    `leads_on_assignment` DB trigger, not here — so the same side effects
    happen whether the assignment comes through this endpoint or the
    Admin panel's direct UPDATE. The service only writes the column."""
    client = _client(table_responses={"leads": FakeResponse(data=[_lead_row(assigned_member_id=REP2_ID)])})
    service = LeadService(client)

    result = service.assign_lead(WORKSPACE_ID, LEAD_ID, REP2_ID)

    assert result["assigned_member"]["id"] == REP2_ID
    # The service must NOT write an allocation row itself any more —
    # doing so alongside the trigger would double every reassignment.
    assert "allocations" not in client.table_calls


def test_assign_lead_rejects_a_member_who_is_not_active_in_this_workspace():
    client = _client(table_responses={"workspace_members": FakeResponse(data=None)})
    service = LeadService(client)

    with pytest.raises(ValidationError):
        service.assign_lead(WORKSPACE_ID, LEAD_ID, REP2_ID)

    # Rejected before the lead is even updated.
    assert "allocations" not in client.table_calls


def test_unassign_lead_clears_the_assignee():
    client = _client(table_responses={"leads": FakeResponse(data=[_lead_row(assigned_member_id=None)])})
    service = LeadService(client)

    result = service.assign_lead(WORKSPACE_ID, LEAD_ID, None)

    assert result["assigned_member"] is None
    assert "allocations" not in client.table_calls


def test_assign_lead_signature_has_no_client_supplied_assigner():
    """The assigner is never a parameter — the FastAPI route cannot pass
    one even by mistake. It is resolved server-side by the trigger via
    current_member_id() (000027), not by this method."""
    import inspect

    params = list(inspect.signature(LeadService.assign_lead).parameters)
    assert params == ["self", "workspace_id", "lead_id", "member_id"]


def test_assign_lead_does_not_send_the_notification_directly(monkeypatch):
    """The 'lead assigned to you' notification (and its lead_assigned vs
    lead_reassigned wording, and the no-self-notify rule) moved into the
    `leads_on_assignment` trigger. The service must not also call notify()
    or every Admin-panel assignment would be silently un-notified while
    every mobile one is double-notified."""
    calls = []
    monkeypatch.setattr(lead_service_module, "notify", lambda workspace_id, **kwargs: calls.append(kwargs))

    client = _client(table_responses={"leads": FakeResponse(data=[_lead_row(assigned_member_id=None)])})
    LeadService(client).assign_lead(WORKSPACE_ID, LEAD_ID, REP2_ID)

    assert calls == []


def test_list_allocations_computes_previous_member_and_orders_most_recent_first():
    older = {
        "id": "alloc-1",
        "assigned_member_id": REP1_ID,
        "assigned_by_member_id": ASSIGNER_ID,
        "status": "new",
        "assigned_at": "2026-01-01T00:00:00Z",
        "created_at": "2026-01-01T00:00:00Z",
    }
    newer = {
        "id": "alloc-2",
        "assigned_member_id": REP2_ID,
        "assigned_by_member_id": ASSIGNER_ID,
        "status": "new",
        "assigned_at": "2026-01-02T00:00:00Z",
        "created_at": "2026-01-02T00:00:00Z",
    }
    client = _client(
        table_responses={
            "allocations": FakeResponse(data=[older, newer]),  # ascending, as list_for_lead returns
            "workspace_members": FakeResponse(
                data=[{"id": REP1_ID, "profile": {"full_name": "Rep One"}}, {"id": REP2_ID, "profile": {"full_name": "Rep Two"}}]
            ),
        }
    )
    service = LeadService(client)

    result = service.list_allocations(WORKSPACE_ID, LEAD_ID)

    # Most recent first.
    assert [r["id"] for r in result] == ["alloc-2", "alloc-1"]
    assert result[0]["assigned_member"]["full_name"] == "Rep Two"
    assert result[0]["previous_member"]["full_name"] == "Rep One"
    # The very first allocation ever made has no previous assignee.
    assert result[1]["previous_member"] is None
