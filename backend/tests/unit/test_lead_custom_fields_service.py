"""LeadService <-> custom fields wiring (000025_custom_fields.sql).

The value validation/coercion itself is covered by
test_custom_field_service.py — these tests only confirm LeadService
routes the `custom_fields` block through it on create/update and echoes
values back on LeadOut.
"""

from uuid import uuid4

import pytest

from app.core.exceptions import ValidationError
from app.services.leads import LeadService
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
MEMBER_ID = str(uuid4())
STATUS_ID = str(uuid4())
LEAD_ID = str(uuid4())
NICK_ID = str(uuid4())
REGION_ID = str(uuid4())


def _lead_row(**o):
    row = {
        "id": LEAD_ID,
        "workspace_id": str(WORKSPACE_ID),
        "name": "Acme Corp",
        "phone": None,
        "email": None,
        "priority": "medium",
        "status_id": STATUS_ID,
        "source_id": None,
        "assigned_member_id": MEMBER_ID,
        "created_by_member_id": MEMBER_ID,
        "is_customer": False,
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }
    row.update(o)
    return row


def _field(id_, code, ftype, **o):
    f = {
        "id": id_, "workspace_id": str(WORKSPACE_ID), "name": code.title(), "code": code,
        "field_type": ftype, "options": [], "is_mandatory": False, "is_filterable": False,
        "is_readonly": False, "sort_order": 0,
        "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z",
    }
    f.update(o)
    return f


def _client(*, fields, values=None):
    return FakeSupabaseClient(
        table_responses={
            "lead_statuses": FakeResponse(data=[{"id": STATUS_ID, "name": "New", "code": "new", "sort_order": 10, "stage": "in_progress", "is_default": True}]),
            "lead_sources": FakeResponse(data=[]),
            "workspace_members": FakeResponse(data=[{"id": MEMBER_ID, "profile": {"full_name": "Rep One"}}]),
            "lead_tags": FakeResponse(data=[]),
            "leads": FakeResponse(data=[_lead_row()]),
            "custom_fields": FakeResponse(data=fields),
            "custom_field_values": FakeResponse(data=values or []),
        },
        rpc_responses={"current_member_id": MEMBER_ID},
    )


def test_create_lead_writes_custom_values_and_they_come_back_on_lead_out():
    client = _client(
        fields=[_field(NICK_ID, "nickname", "text")],
        values=[{"lead_id": LEAD_ID, "custom_field_id": NICK_ID, "value": "Ace"}],
    )
    service = LeadService(client)

    result = service.create_lead(WORKSPACE_ID, {"name": "Acme Corp", "custom_fields": {"nickname": "Ace"}})

    assert "custom_field_values" in client.table_calls  # a value write happened
    assert result["custom_fields"] == {"nickname": "Ace"}


def test_create_lead_rejects_a_bad_custom_value_before_inserting_the_lead():
    client = _client(fields=[_field(NICK_ID, "nickname", "number")])
    service = LeadService(client)

    with pytest.raises(ValidationError, match="expects a number"):
        service.create_lead(WORKSPACE_ID, {"name": "Acme Corp", "custom_fields": {"nickname": "not a number"}})

    assert "leads" not in [c for c in client.table_calls if c == "leads"][1:]  # no insert reached


def test_create_lead_enforces_a_mandatory_custom_field_even_when_block_is_omitted():
    client = _client(fields=[_field(REGION_ID, "region", "text", is_mandatory=True)])
    service = LeadService(client)

    with pytest.raises(ValidationError, match="'region' is required"):
        service.create_lead(WORKSPACE_ID, {"name": "Acme Corp"})


def test_update_lead_with_only_custom_fields_is_allowed():
    client = _client(
        fields=[_field(NICK_ID, "nickname", "text")],
        values=[{"lead_id": LEAD_ID, "custom_field_id": NICK_ID, "value": "Renamed"}],
    )
    service = LeadService(client)

    result = service.update_lead(WORKSPACE_ID, LEAD_ID, {"custom_fields": {"nickname": "Renamed"}})

    assert result["custom_fields"] == {"nickname": "Renamed"}


def test_update_lead_with_nothing_at_all_still_rejects():
    client = _client(fields=[])
    service = LeadService(client)

    with pytest.raises(ValidationError, match="No fields to update"):
        service.update_lead(WORKSPACE_ID, LEAD_ID, {})
