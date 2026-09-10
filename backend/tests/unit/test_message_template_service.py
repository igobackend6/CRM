from uuid import uuid4

from app.services.message_templates.service import MessageTemplateService
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
MEMBER_ID = uuid4()


def _row(**overrides):
    row = {
        "id": str(uuid4()),
        "workspace_id": str(WORKSPACE_ID),
        "name": "Follow-up",
        "body": "Hello {{name}}",
        "created_by_member_id": str(MEMBER_ID),
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }
    row.update(overrides)
    return row


def test_create_template_resolves_the_actor_server_side_not_from_the_caller():
    """MessageTemplateCreate (schemas) has no created_by field at all —
    this test documents, at the service layer, that the actor always
    comes from the `current_member_id` RPC."""
    client = FakeSupabaseClient(
        table_responses={"message_templates": FakeResponse(data=[_row()])},
        rpc_responses={"current_member_id": str(MEMBER_ID)},
    )
    service = MessageTemplateService(client)
    service.create_template(WORKSPACE_ID, name="Follow-up", body="Hello {{name}}")
    assert ("current_member_id", {"p_workspace_id": str(WORKSPACE_ID)}) in client.rpc_calls


def test_list_templates_returns_rows():
    client = FakeSupabaseClient(table_responses={"message_templates": FakeResponse(data=[_row(), _row()])})
    service = MessageTemplateService(client)
    assert len(service.list_templates(WORKSPACE_ID)) == 2


def test_update_template_delegates_to_the_repository():
    client = FakeSupabaseClient(table_responses={"message_templates": FakeResponse(data=[_row(name="Renamed")])})
    service = MessageTemplateService(client)
    row = service.update_template(WORKSPACE_ID, uuid4(), {"name": "Renamed"})
    assert row["name"] == "Renamed"


def test_delete_template_delegates_to_the_repository():
    client = FakeSupabaseClient(table_responses={"message_templates": FakeResponse(data=[_row()])})
    service = MessageTemplateService(client)
    service.delete_template(WORKSPACE_ID, uuid4())  # must not raise
