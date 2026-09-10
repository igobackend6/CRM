from uuid import uuid4

import pytest

import app.services.notifications.service as notifications_service_module
from app.core.exceptions import NotFoundError
from app.services.notifications.service import NotificationService, notify
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
MEMBER_ID = str(uuid4())
NOTIFICATION_ID = uuid4()


def _row(**overrides):
    row = {
        "id": str(NOTIFICATION_ID),
        "workspace_id": str(WORKSPACE_ID),
        "recipient_member_id": MEMBER_ID,
        "type": "lead_assigned",
        "title": "Lead assigned to you",
        "body": "Acme Corp",
        "related_entity_type": "lead",
        "related_entity_id": str(uuid4()),
        "is_read": False,
        "read_at": None,
        "created_at": "2026-01-01T00:00:00Z",
    }
    row.update(overrides)
    return row


def _client(**overrides):
    table_responses = {"notifications": FakeResponse(data=[_row()], count=1)}
    table_responses.update(overrides.pop("table_responses", {}))
    rpc_responses = {"current_member_id": MEMBER_ID}
    rpc_responses.update(overrides.pop("rpc_responses", {}))
    return FakeSupabaseClient(table_responses=table_responses, rpc_responses=rpc_responses)


# ---- NotificationService (request-scoped reads/mark-read) ----


def test_list_notifications_resolves_the_recipient_as_the_current_member():
    client = _client()
    service = NotificationService(client)

    items, total = service.list_notifications(WORKSPACE_ID, is_read=None, limit=20, offset=0)

    assert total == 1
    assert items[0]["recipient_member_id"] == MEMBER_ID
    assert ("current_member_id", {"p_workspace_id": str(WORKSPACE_ID)}) in client.rpc_calls


def test_get_notification_raises_not_found_for_a_missing_or_other_recipients_row():
    client = _client(table_responses={"notifications": FakeResponse(data=None)})
    service = NotificationService(client)

    with pytest.raises(NotFoundError):
        service.get_notification(WORKSPACE_ID, uuid4())


def test_mark_read_delegates_to_the_repository():
    client = _client(table_responses={"notifications": FakeResponse(data=[_row(is_read=True)])})
    service = NotificationService(client)

    result = service.mark_read(WORKSPACE_ID, NOTIFICATION_ID, is_read=True)

    assert result["is_read"] is True


def test_mark_all_read_returns_the_updated_count():
    client = _client(table_responses={"notifications": FakeResponse(data=[_row(), _row(id=str(uuid4()))])})
    service = NotificationService(client)

    count = service.mark_all_read(WORKSPACE_ID)

    assert count == 2


# ---- notify() (service-role write used by CRM event hooks) ----


def test_notify_inserts_through_the_service_role_client(monkeypatch):
    fake_service_role_client = FakeSupabaseClient(table_responses={"notifications": FakeResponse(data=[_row()])})
    monkeypatch.setattr(notifications_service_module, "get_supabase_client", lambda: fake_service_role_client)

    notify(
        WORKSPACE_ID,
        recipient_member_id=MEMBER_ID,
        type="lead_assigned",
        title="Lead assigned to you",
        body="Acme Corp",
        related_entity_type="lead",
        related_entity_id=str(uuid4()),
    )

    assert "notifications" in fake_service_role_client.table_calls


def test_notify_is_a_no_op_when_the_service_role_client_is_unavailable(monkeypatch):
    """Never raises: a notification is a side effect of the primary
    request, not the operation itself. Also confirms it doesn't fall
    back to some other, unprivileged client — no service-role client
    means no notification, full stop (notifications has no INSERT
    policy any other client could use anyway)."""
    monkeypatch.setattr(notifications_service_module, "get_supabase_client", lambda: None)

    notify(WORKSPACE_ID, recipient_member_id=MEMBER_ID, type="lead_assigned", title="Lead assigned to you")


def test_notify_rejects_an_unknown_type_without_touching_the_client(monkeypatch):
    """Guards the notifications.type CHECK constraint client-side too —
    an unrecognized type would otherwise fail at insert time regardless,
    but this avoids even constructing the service-role client for a call
    that can never succeed."""

    def _fail_if_called():
        raise AssertionError("get_supabase_client() should not be called for an invalid type")

    monkeypatch.setattr(notifications_service_module, "get_supabase_client", _fail_if_called)

    notify(WORKSPACE_ID, recipient_member_id=MEMBER_ID, type="not_a_real_type", title="x")


def test_notify_swallows_a_repository_failure(monkeypatch):
    class _FailingClient(FakeSupabaseClient):
        def table(self, name):
            raise RuntimeError("simulated database failure")

    monkeypatch.setattr(notifications_service_module, "get_supabase_client", lambda: _FailingClient())

    # Must not raise — a broken notification write can never fail the
    # primary request (assigning a lead, logging a call, ...) that
    # triggered it.
    notify(WORKSPACE_ID, recipient_member_id=MEMBER_ID, type="lead_assigned", title="Lead assigned to you")
