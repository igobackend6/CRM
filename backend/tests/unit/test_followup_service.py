from uuid import uuid4

import pytest

import app.services.followups.service as followup_service_module
from app.core.exceptions import NotFoundError, ValidationError
from app.services.followups import FollowUpService
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
LEAD_ID = str(uuid4())
FOLLOW_UP_ID = str(uuid4())
CREATOR_ID = str(uuid4())
REP1_ID = str(uuid4())
REP2_ID = str(uuid4())


def _lead_row():
    return {"id": LEAD_ID, "workspace_id": str(WORKSPACE_ID), "name": "Acme Corp"}


def _follow_up_row(**overrides):
    row = {
        "id": FOLLOW_UP_ID,
        "workspace_id": str(WORKSPACE_ID),
        "lead_id": LEAD_ID,
        "assigned_member_id": REP1_ID,
        "created_by_member_id": CREATOR_ID,
        "type": "call",
        "due_at": "2026-02-01T09:00:00Z",
        "status": "pending",
        "notes": None,
        "completed_at": None,
        "cancelled_at": None,
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }
    row.update(overrides)
    return row


def _client(**overrides):
    table_responses = {
        "leads": FakeResponse(data=[_lead_row()]),
        # List-shaped: several service methods hit "follow_ups" both as
        # a maybe_single() visibility check and as a list-returning
        # insert()/update() — see fake_supabase.py's auto-unwrap.
        "follow_ups": FakeResponse(data=[_follow_up_row()]),
        "workspace_members": FakeResponse(data=[{"id": REP2_ID, "profile": {"full_name": "Rep Two"}}]),
    }
    table_responses.update(overrides.pop("table_responses", {}))
    rpc_responses = {"current_member_id": CREATOR_ID}
    rpc_responses.update(overrides.pop("rpc_responses", {}))
    return FakeSupabaseClient(table_responses=table_responses, rpc_responses=rpc_responses)


def test_create_follow_up_defaults_assignment_to_the_creator_when_omitted():
    client = _client(table_responses={"follow_ups": FakeResponse(data=[_follow_up_row(assigned_member_id=CREATOR_ID)])})
    service = FollowUpService(client)

    result = service.create_follow_up(WORKSPACE_ID, {"lead_id": LEAD_ID, "due_at": "2026-02-01T09:00:00Z", "type": "call"})

    assert result["assigned_member"]["id"] == CREATOR_ID
    assert result["lead"]["name"] == "Acme Corp"


def test_create_follow_up_validates_the_requested_assignee():
    client = _client(table_responses={"follow_ups": FakeResponse(data=[_follow_up_row(assigned_member_id=REP2_ID)])})
    service = FollowUpService(client)

    result = service.create_follow_up(
        WORKSPACE_ID, {"lead_id": LEAD_ID, "due_at": "2026-02-01T09:00:00Z", "type": "call", "assigned_member_id": REP2_ID}
    )

    assert result["assigned_member"]["id"] == REP2_ID


def test_create_follow_up_rejects_an_inactive_or_cross_workspace_member():
    client = _client(table_responses={"workspace_members": FakeResponse(data=None)})
    service = FollowUpService(client)

    with pytest.raises(ValidationError):
        service.create_follow_up(
            WORKSPACE_ID, {"lead_id": LEAD_ID, "due_at": "2026-02-01T09:00:00Z", "type": "call", "assigned_member_id": REP2_ID}
        )


def test_create_follow_up_rejects_a_lead_that_does_not_exist_or_is_not_visible():
    client = _client(table_responses={"leads": FakeResponse(data=None)})
    service = FollowUpService(client)

    with pytest.raises(NotFoundError):
        service.create_follow_up(WORKSPACE_ID, {"lead_id": str(uuid4()), "due_at": "2026-02-01T09:00:00Z", "type": "call"})


def test_create_follow_up_never_trusts_a_client_supplied_creator():
    client = _client()
    service = FollowUpService(client)

    service.create_follow_up(WORKSPACE_ID, {"lead_id": LEAD_ID, "due_at": "2026-02-01T09:00:00Z", "type": "call"})

    assert ("current_member_id", {"p_workspace_id": str(WORKSPACE_ID)}) in client.rpc_calls


def _capture_notify(monkeypatch):
    calls = []
    monkeypatch.setattr(followup_service_module, "notify", lambda workspace_id, **kwargs: calls.append(kwargs))
    return calls


def test_create_follow_up_notifies_a_non_self_assignee(monkeypatch):
    calls = _capture_notify(monkeypatch)
    client = _client(table_responses={"follow_ups": FakeResponse(data=[_follow_up_row(assigned_member_id=REP2_ID)])})
    service = FollowUpService(client)

    service.create_follow_up(
        WORKSPACE_ID, {"lead_id": LEAD_ID, "due_at": "2026-02-01T09:00:00Z", "type": "call", "assigned_member_id": REP2_ID}
    )

    assert len(calls) == 1
    assert calls[0]["recipient_member_id"] == REP2_ID
    assert calls[0]["type"] == "system"
    assert calls[0]["related_entity_type"] == "follow_up"
    assert calls[0]["related_entity_id"] == FOLLOW_UP_ID


def test_create_follow_up_does_not_notify_on_self_assignment(monkeypatch):
    calls = _capture_notify(monkeypatch)
    client = _client(table_responses={"follow_ups": FakeResponse(data=[_follow_up_row(assigned_member_id=CREATOR_ID)])})
    service = FollowUpService(client)

    service.create_follow_up(WORKSPACE_ID, {"lead_id": LEAD_ID, "due_at": "2026-02-01T09:00:00Z", "type": "call"})

    assert calls == []


def test_update_follow_up_reschedules_due_at():
    client = _client(table_responses={"follow_ups": FakeResponse(data=[_follow_up_row(due_at="2026-03-01T10:00:00Z")])})
    service = FollowUpService(client)

    result = service.update_follow_up(WORKSPACE_ID, FOLLOW_UP_ID, {"due_at": "2026-03-01T10:00:00Z"})

    assert result["due_at"].startswith("2026-03-01")


def test_update_follow_up_marks_completed_and_stamps_completed_at():
    client = _client(
        table_responses={"follow_ups": FakeResponse(data=[_follow_up_row(status="completed", completed_at="2026-01-05T00:00:00Z")])}
    )
    service = FollowUpService(client)

    result = service.update_follow_up(WORKSPACE_ID, FOLLOW_UP_ID, {"status": "completed"})

    assert result["status"] == "completed"
    assert result["completed_at"] is not None


def test_update_follow_up_marks_cancelled_and_stamps_cancelled_at():
    client = _client(
        table_responses={"follow_ups": FakeResponse(data=[_follow_up_row(status="cancelled", cancelled_at="2026-01-05T00:00:00Z")])}
    )
    service = FollowUpService(client)

    result = service.update_follow_up(WORKSPACE_ID, FOLLOW_UP_ID, {"status": "cancelled"})

    assert result["status"] == "cancelled"
    assert result["cancelled_at"] is not None


def test_update_follow_up_rejects_reassignment_to_an_inactive_member():
    client = _client(table_responses={"workspace_members": FakeResponse(data=None)})
    service = FollowUpService(client)

    with pytest.raises(ValidationError):
        service.update_follow_up(WORKSPACE_ID, FOLLOW_UP_ID, {"assigned_member_id": REP2_ID})


def test_update_follow_up_notifies_on_reassignment_to_someone_else(monkeypatch):
    # Default fixture's follow_ups row is assigned_member_id=REP1_ID —
    # left unmodified here so the pre-update fetch ("previous") actually
    # differs from the REP2_ID being requested (the fake client returns
    # the same static row for both the pre-fetch and the update, so
    # "previous" must come from an untouched fixture, not one overridden
    # to already show the new value).
    calls = _capture_notify(monkeypatch)
    client = _client()
    service = FollowUpService(client)

    service.update_follow_up(WORKSPACE_ID, FOLLOW_UP_ID, {"assigned_member_id": REP2_ID})

    assert len(calls) == 1
    assert calls[0]["recipient_member_id"] == REP2_ID
    assert calls[0]["type"] == "system"
    assert calls[0]["related_entity_type"] == "follow_up"


def test_update_follow_up_does_not_notify_when_reassigned_to_the_current_actor(monkeypatch):
    """The default fixture's current_member_id() is CREATOR_ID — assigning
    a follow-up to yourself should never notify yourself."""
    calls = _capture_notify(monkeypatch)
    client = _client()
    service = FollowUpService(client)

    service.update_follow_up(WORKSPACE_ID, FOLLOW_UP_ID, {"assigned_member_id": CREATOR_ID})

    assert calls == []


def test_update_follow_up_does_not_notify_when_a_non_reassignment_field_changes(monkeypatch):
    calls = _capture_notify(monkeypatch)
    client = _client()
    service = FollowUpService(client)

    service.update_follow_up(WORKSPACE_ID, FOLLOW_UP_ID, {"status": "completed"})

    assert calls == []


def test_update_follow_up_rejects_an_id_that_does_not_exist():
    client = _client(table_responses={"follow_ups": FakeResponse(data=None)})
    service = FollowUpService(client)

    with pytest.raises(NotFoundError):
        service.update_follow_up(WORKSPACE_ID, str(uuid4()), {"status": "completed"})


def test_update_follow_up_with_no_fields_raises_validation_error():
    client = _client()
    service = FollowUpService(client)

    with pytest.raises(ValidationError):
        service.update_follow_up(WORKSPACE_ID, FOLLOW_UP_ID, {})


def test_list_lead_follow_ups_is_scoped_to_the_lead_and_requires_a_visible_lead():
    client = _client(table_responses={"follow_ups": FakeResponse(data=[_follow_up_row()])})
    service = FollowUpService(client)

    results = service.list_lead_follow_ups(WORKSPACE_ID, LEAD_ID)

    assert len(results) == 1
    assert results[0]["lead"]["id"] == LEAD_ID


def test_list_lead_follow_ups_404s_for_a_lead_that_is_not_visible():
    client = _client(table_responses={"leads": FakeResponse(data=None)})
    service = FollowUpService(client)

    with pytest.raises(NotFoundError):
        service.list_lead_follow_ups(WORKSPACE_ID, str(uuid4()))
