from uuid import uuid4

import pytest

from app.core.exceptions import NotFoundError
from app.services.customer360 import CustomerService
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
MEMBER_ID = str(uuid4())
STATUS_ID = str(uuid4())
SOURCE_ID = str(uuid4())
CUSTOMER_ID = str(uuid4())


def _lead_row(**overrides):
    row = {
        "id": CUSTOMER_ID,
        "workspace_id": str(WORKSPACE_ID),
        "name": "Acme Corp",
        "phone": None,
        "email": None,
        "priority": "medium",
        "status_id": STATUS_ID,
        "source_id": SOURCE_ID,
        "assigned_member_id": MEMBER_ID,
        "created_by_member_id": MEMBER_ID,
        "is_customer": True,
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }
    row.update(overrides)
    return row


def _client(**overrides):
    table_responses = {
        "lead_statuses": FakeResponse(
            data=[{"id": STATUS_ID, "name": "New", "code": "new", "sort_order": 10, "stage": "in_progress", "is_default": True}]
        ),
        "lead_sources": FakeResponse(data=[{"id": SOURCE_ID, "name": "Website", "code": "website", "is_default": False}]),
        "workspace_members": FakeResponse(data=[{"id": MEMBER_ID, "profile": {"full_name": "Rep One"}}]),
        "lead_tags": FakeResponse(data=[]),
        # A LIST (not a bare dict): get_for_workspace() (.maybe_single())
        # auto-unwraps it to a single row, while list_names() (no
        # maybe_single) needs the list shape — both are exercised in
        # these tests (list_follow_ups goes through FollowUpService,
        # which calls both).
        "leads": FakeResponse(data=[_lead_row()]),
        "interactions": FakeResponse(data=[], count=0),
        "calls": FakeResponse(data=[], count=0),
        "follow_ups": FakeResponse(data=[], count=0),
        "lead_documents": FakeResponse(data=[], count=0),
        "allocations": FakeResponse(data=[], count=0),
    }
    table_responses.update(overrides.pop("table_responses", {}))
    rpc_responses = {"current_member_id": MEMBER_ID}
    rpc_responses.update(overrides.pop("rpc_responses", {}))
    return FakeSupabaseClient(table_responses=table_responses, rpc_responses=rpc_responses)


# ---- get_customer (§2 / is_customer rule) ----


def test_get_customer_returns_the_enriched_lead():
    service = CustomerService(_client())

    result = service.get_customer(WORKSPACE_ID, CUSTOMER_ID)

    assert result["id"] == CUSTOMER_ID
    assert result["is_customer"] is True
    assert result["status"]["name"] == "New"


def test_get_customer_rejects_a_non_customer_lead():
    client = _client(table_responses={"leads": FakeResponse(data=[_lead_row(is_customer=False)])})
    service = CustomerService(client)

    with pytest.raises(NotFoundError):
        service.get_customer(WORKSPACE_ID, CUSTOMER_ID)


def test_get_customer_raises_not_found_for_a_missing_or_invisible_lead():
    """Cross-workspace/nonexistent lead: get_for_workspace's own
    workspace-scoped .maybe_single() 404s before is_customer is even
    checked."""
    client = _client(table_responses={"leads": FakeResponse(data=[])})
    service = CustomerService(client)

    with pytest.raises(NotFoundError):
        service.get_customer(WORKSPACE_ID, uuid4())


# ---- documents (§2 "Documents") ----


def test_list_documents_returns_enriched_items_and_total():
    doc_row = {
        "id": str(uuid4()),
        "workspace_id": str(WORKSPACE_ID),
        "lead_id": CUSTOMER_ID,
        "uploaded_by_member_id": MEMBER_ID,
        "file_name": "contract.pdf",
        "mime_type": "application/pdf",
        "size_bytes": 2048,
        "created_at": "2026-01-05T00:00:00Z",
    }
    client = _client(table_responses={"lead_documents": FakeResponse(data=[doc_row], count=1)})
    service = CustomerService(client)

    items, total = service.list_documents(WORKSPACE_ID, CUSTOMER_ID, limit=20, offset=0)

    assert total == 1
    assert items[0]["file_name"] == "contract.pdf"
    assert items[0]["uploaded_by_member"]["full_name"] == "Rep One"


def test_list_documents_rejects_a_non_customer_lead():
    client = _client(table_responses={"leads": FakeResponse(data=[_lead_row(is_customer=False)])})
    service = CustomerService(client)

    with pytest.raises(NotFoundError):
        service.list_documents(WORKSPACE_ID, CUSTOMER_ID, limit=20, offset=0)


def test_list_documents_empty_state_when_none_uploaded():
    service = CustomerService(_client())

    items, total = service.list_documents(WORKSPACE_ID, CUSTOMER_ID, limit=20, offset=0)

    assert items == []
    assert total == 0


# ---- follow-ups (§2 "Follow-Ups", reuses Phase 7) ----


def test_list_follow_ups_delegates_to_follow_up_service():
    follow_up_row = {
        "id": str(uuid4()),
        "workspace_id": str(WORKSPACE_ID),
        "lead_id": CUSTOMER_ID,
        "assigned_member_id": MEMBER_ID,
        "created_by_member_id": MEMBER_ID,
        "type": "call",
        "due_at": "2026-02-01T09:00:00Z",
        "status": "pending",
        "notes": None,
        "completed_at": None,
        "cancelled_at": None,
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }
    client = _client(table_responses={"follow_ups": FakeResponse(data=[follow_up_row])})
    service = CustomerService(client)

    items = service.list_follow_ups(WORKSPACE_ID, CUSTOMER_ID)

    assert len(items) == 1
    assert items[0]["lead"]["id"] == CUSTOMER_ID
    assert items[0]["status"] == "pending"


def test_list_follow_ups_rejects_a_non_customer_lead():
    client = _client(table_responses={"leads": FakeResponse(data=[_lead_row(is_customer=False)])})
    service = CustomerService(client)

    with pytest.raises(NotFoundError):
        service.list_follow_ups(WORKSPACE_ID, CUSTOMER_ID)


# ---- notes (§7) ----


def test_create_note_inserts_an_interaction_with_the_current_member_as_actor():
    client = _client(
        table_responses={
            "interactions": FakeResponse(data=[{"id": str(uuid4()), "type": "note", "payload": {"text": "Called back"}}])
        }
    )
    service = CustomerService(client)

    result = service.create_note(WORKSPACE_ID, CUSTOMER_ID, "Called back")

    assert result["type"] == "note"
    assert result["actor_member"]["id"] == MEMBER_ID


def test_create_note_rejects_a_non_customer_lead():
    client = _client(table_responses={"leads": FakeResponse(data=[_lead_row(is_customer=False)])})
    service = CustomerService(client)

    with pytest.raises(NotFoundError):
        service.create_note(WORKSPACE_ID, CUSTOMER_ID, "x")


# ---- unified timeline (§3/§4/§10) ----


def test_timeline_merges_and_sorts_all_sources_chronologically():
    interaction_row = {
        "id": "int-1",
        "type": "note",
        "payload": {"text": "hello"},
        "actor_member_id": MEMBER_ID,
        "created_at": "2026-01-05T00:00:00Z",
    }
    call_row = {
        "id": "call-1",
        "agent_member_id": MEMBER_ID,
        "direction": "outbound",
        "state": "ENDED",
        "started_at": "2026-01-04T00:00:00Z",
        "duration_seconds": 60,
        "notes": None,
    }
    follow_up_row = {
        "id": "fu-1",
        "created_by_member_id": MEMBER_ID,
        "type": "call",
        "due_at": "2026-02-01T00:00:00Z",
        "status": "pending",
        "notes": None,
        "created_at": "2026-01-03T00:00:00Z",
    }
    document_row = {
        "id": "doc-1",
        "uploaded_by_member_id": MEMBER_ID,
        "file_name": "contract.pdf",
        "mime_type": "application/pdf",
        "size_bytes": 100,
        "created_at": "2026-01-02T00:00:00Z",
    }
    allocation_row = {
        "id": "alloc-1",
        "assigned_member_id": MEMBER_ID,
        "assigned_by_member_id": MEMBER_ID,
        "status": "new",
        "assigned_at": "2026-01-01T00:00:00Z",
    }
    client = _client(
        table_responses={
            "interactions": FakeResponse(data=[interaction_row], count=1),
            "calls": FakeResponse(data=[call_row], count=1),
            "follow_ups": FakeResponse(data=[follow_up_row], count=1),
            "lead_documents": FakeResponse(data=[document_row], count=1),
            "allocations": FakeResponse(data=[allocation_row], count=1),
        }
    )
    service = CustomerService(client)

    items, total = service.get_timeline(WORKSPACE_ID, CUSTOMER_ID, limit=20, offset=0)

    assert total == 5
    # Newest first, across every source table (note 01-05 -> ... -> allocation 01-01).
    assert [i["type"] for i in items] == ["note", "call", "follow_up", "document", "allocation"]
    assert items[0]["id"] == "interaction:int-1"
    assert items[0]["actor_member"]["full_name"] == "Rep One"


def test_timeline_paginates_the_merged_result():
    rows = [
        {
            "id": f"int-{i}",
            "type": "note",
            "payload": {"text": f"note {i}"},
            "actor_member_id": MEMBER_ID,
            "created_at": f"2026-01-{i + 1:02d}T00:00:00Z",
        }
        for i in range(5)
    ]
    client = _client(table_responses={"interactions": FakeResponse(data=rows, count=5)})
    service = CustomerService(client)

    page1, total1 = service.get_timeline(WORKSPACE_ID, CUSTOMER_ID, limit=2, offset=0)
    page2, total2 = service.get_timeline(WORKSPACE_ID, CUSTOMER_ID, limit=2, offset=2)

    assert total1 == total2 == 5
    assert [i["id"] for i in page1] == ["interaction:int-4", "interaction:int-3"]
    assert [i["id"] for i in page2] == ["interaction:int-2", "interaction:int-1"]


def test_timeline_empty_state_when_no_activity_exists():
    service = CustomerService(_client())

    items, total = service.get_timeline(WORKSPACE_ID, CUSTOMER_ID, limit=20, offset=0)

    assert items == []
    assert total == 0


def test_timeline_rejects_a_non_customer_lead():
    client = _client(table_responses={"leads": FakeResponse(data=[_lead_row(is_customer=False)])})
    service = CustomerService(client)

    with pytest.raises(NotFoundError):
        service.get_timeline(WORKSPACE_ID, CUSTOMER_ID, limit=20, offset=0)


def test_timeline_rejects_a_missing_customer_id():
    client = _client(table_responses={"leads": FakeResponse(data=[])})
    service = CustomerService(client)

    with pytest.raises(NotFoundError):
        service.get_timeline(WORKSPACE_ID, uuid4(), limit=20, offset=0)


# ---- Phase 15: lead-level activity feed (generalizes the timeline above) ----


def test_get_lead_activity_works_for_a_lead_that_is_not_a_customer():
    """The whole point of Phase 15's generalization — a plain lead
    (is_customer=False) gets the same merged activity feed Customer 360
    already had, without needing to become a customer first."""
    client = _client(table_responses={"leads": FakeResponse(data=[_lead_row(is_customer=False)])})
    service = CustomerService(client)

    items, total = service.get_lead_activity(WORKSPACE_ID, CUSTOMER_ID, limit=20, offset=0)

    assert items == []
    assert total == 0


def test_get_lead_activity_merges_every_source_like_the_customer_timeline_does():
    interaction_row = {
        "id": "int-1",
        "type": "note",
        "payload": {"text": "hello"},
        "actor_member_id": MEMBER_ID,
        "created_at": "2026-01-05T00:00:00Z",
    }
    call_row = {
        "id": "call-1",
        "agent_member_id": MEMBER_ID,
        "direction": "outbound",
        "state": "ENDED",
        "started_at": "2026-01-04T00:00:00Z",
        "duration_seconds": 60,
        "notes": None,
    }
    client = _client(
        table_responses={
            "leads": FakeResponse(data=[_lead_row(is_customer=False)]),
            "interactions": FakeResponse(data=[interaction_row], count=1),
            "calls": FakeResponse(data=[call_row], count=1),
        }
    )
    service = CustomerService(client)

    items, total = service.get_lead_activity(WORKSPACE_ID, CUSTOMER_ID, limit=20, offset=0)

    assert total == 2
    assert [i["type"] for i in items] == ["note", "call"]


def test_get_lead_activity_raises_not_found_for_a_missing_or_invisible_lead():
    client = _client(table_responses={"leads": FakeResponse(data=[])})
    service = CustomerService(client)

    with pytest.raises(NotFoundError):
        service.get_lead_activity(WORKSPACE_ID, uuid4(), limit=20, offset=0)


def test_create_lead_note_works_for_a_lead_that_is_not_a_customer():
    client = _client(
        table_responses={
            "leads": FakeResponse(data=[_lead_row(is_customer=False)]),
            "interactions": FakeResponse(data=[{"id": str(uuid4()), "type": "note", "payload": {"text": "Called back"}}]),
        }
    )
    service = CustomerService(client)

    result = service.create_lead_note(WORKSPACE_ID, CUSTOMER_ID, "Called back")

    assert result["type"] == "note"
    assert result["actor_member"]["id"] == MEMBER_ID


def test_create_lead_note_rejects_a_missing_or_invisible_lead():
    client = _client(table_responses={"leads": FakeResponse(data=[])})
    service = CustomerService(client)

    with pytest.raises(NotFoundError):
        service.create_lead_note(WORKSPACE_ID, uuid4(), "x")


def test_activity_includes_messages_from_the_leads_conversation():
    """Phase 16 §"Activity integration": a sent message shows up in the
    unified timeline by reading `messages` directly (via the lead's
    `conversations` row) — no `interactions` row is written for it."""
    conversation_row = {"id": "conv-1", "workspace_id": str(WORKSPACE_ID), "lead_id": CUSTOMER_ID}
    message_row = {
        "id": "msg-1",
        "conversation_id": "conv-1",
        "sender_member_id": MEMBER_ID,
        "body": "Following up on pricing",
        "created_at": "2026-01-06T00:00:00Z",
        "read_at": None,
    }
    client = _client(
        table_responses={
            "conversations": FakeResponse(data=[conversation_row]),
            "messages": FakeResponse(data=[message_row], count=1),
        }
    )
    service = CustomerService(client)

    items, total = service.get_lead_activity(WORKSPACE_ID, CUSTOMER_ID, limit=20, offset=0)

    assert total == 1
    assert items[0]["id"] == "message:msg-1"
    assert items[0]["type"] == "message"
    assert items[0]["summary"] == "Following up on pricing"
    assert items[0]["actor_member"]["full_name"] == "Rep One"


def test_activity_has_no_message_items_when_the_lead_has_no_conversation_yet():
    service = CustomerService(_client())  # default "conversations" table is empty -> get_for_lead() is None

    items, total = service.get_lead_activity(WORKSPACE_ID, CUSTOMER_ID, limit=20, offset=0)

    assert items == []
    assert total == 0


def test_activity_allocation_items_resolve_the_assignee_name():
    """Phase 15 §"Flutter Activity UI" needs a display name, not just the
    raw assigned_member_id the allocation row itself carries."""
    allocation_row = {
        "id": "alloc-1",
        "assigned_member_id": MEMBER_ID,
        "assigned_by_member_id": MEMBER_ID,
        "status": "new",
        "assigned_at": "2026-01-01T00:00:00Z",
    }
    client = _client(
        table_responses={
            "leads": FakeResponse(data=[_lead_row(is_customer=False)]),
            "allocations": FakeResponse(data=[allocation_row], count=1),
        }
    )
    service = CustomerService(client)

    items, _ = service.get_lead_activity(WORKSPACE_ID, CUSTOMER_ID, limit=20, offset=0)

    assert items[0]["details"]["assigned_member"] == {"id": MEMBER_ID, "full_name": "Rep One"}
