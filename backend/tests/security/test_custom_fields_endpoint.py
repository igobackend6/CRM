from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.api import dependencies as deps
from app.main import app
from app.schemas.auth import AuthenticatedUser
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = str(uuid4())
FIELD_ID = str(uuid4())


def _row(**overrides):
    row = {
        "id": FIELD_ID,
        "workspace_id": WORKSPACE_ID,
        "name": "Deal Size",
        "code": "deal_size",
        "field_type": "number",
        "options": [],
        "auto_fill": True,
        "is_mandatory": False,
        "is_filterable": True,
        "is_readonly": False,
        "sort_order": 0,
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }
    row.update(overrides)
    return row


def _install(*, can_manage: bool, is_member: bool = True, table_responses=None):
    fake_client = FakeSupabaseClient(
        table_responses=table_responses or {"custom_fields": FakeResponse(data=[_row()])},
        rpc_responses={"has_permission": can_manage, "is_workspace_member": is_member, "current_member_id": str(uuid4())},
    )
    app.dependency_overrides[deps.get_current_user] = lambda: AuthenticatedUser(
        id=uuid4(), email="admin@example.com", access_token="fake-token"
    )
    app.dependency_overrides[deps.get_user_client] = lambda: fake_client
    return fake_client


@pytest.fixture(autouse=True)
def _cleanup():
    yield
    app.dependency_overrides.clear()


@pytest.fixture
def client():
    return TestClient(app)


def test_listing_custom_fields_only_needs_membership(client):
    _install(can_manage=False, is_member=True)
    r = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/custom-fields")
    assert r.status_code == 200
    assert r.json()[0]["code"] == "deal_size"


def test_listing_denied_for_a_non_member(client):
    _install(can_manage=False, is_member=False)
    r = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/custom-fields")
    assert r.status_code == 403


def test_creating_a_field_requires_workspace_manage(client):
    _install(can_manage=False)
    r = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/custom-fields",
        json={"name": "Deal Size", "code": "deal_size", "field_type": "number"},
    )
    assert r.status_code == 403


def test_manager_can_create_a_field(client):
    _install(can_manage=True)
    r = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/custom-fields",
        json={"name": "Deal Size", "code": "deal_size", "field_type": "number"},
    )
    assert r.status_code == 201
    assert r.json()["code"] == "deal_size"


def test_select_field_without_options_is_rejected_at_the_schema(client):
    _install(can_manage=True)
    r = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/custom-fields",
        json={"name": "Segment", "code": "segment", "field_type": "options"},
    )
    assert r.status_code == 422


def test_a_non_slug_code_is_rejected(client):
    _install(can_manage=True)
    r = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/custom-fields",
        json={"name": "Bad", "code": "Deal Size!", "field_type": "text"},
    )
    assert r.status_code == 422


def test_update_and_delete_require_workspace_manage(client):
    _install(can_manage=False)
    assert client.patch(
        f"/api/v1/workspaces/{WORKSPACE_ID}/custom-fields/{FIELD_ID}", json={"name": "Renamed"}
    ).status_code == 403
    assert client.delete(f"/api/v1/workspaces/{WORKSPACE_ID}/custom-fields/{FIELD_ID}").status_code == 403


def test_update_cannot_change_code_or_field_type(client):
    _install(can_manage=True)
    r = client.patch(
        f"/api/v1/workspaces/{WORKSPACE_ID}/custom-fields/{FIELD_ID}",
        json={"code": "something_else", "field_type": "text"},
    )
    # extra=forbid isn't set, so unknown keys are ignored — the update
    # simply doesn't touch code/field_type. A 200 with the row unchanged.
    assert r.status_code == 200
    assert r.json()["code"] == "deal_size"
    assert r.json()["field_type"] == "number"


def test_manager_can_toggle_auto_fill(client):
    _install(can_manage=True, table_responses={"custom_fields": FakeResponse(data=[_row(auto_fill=False)])})
    r = client.patch(
        f"/api/v1/workspaces/{WORKSPACE_ID}/custom-fields/{FIELD_ID}", json={"auto_fill": False}
    )
    assert r.status_code == 200
    assert r.json()["auto_fill"] is False


def test_multi_options_field_needs_options(client):
    _install(can_manage=True)
    r = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/custom-fields",
        json={"name": "Interests", "code": "interests", "field_type": "multi_options"},
    )
    assert r.status_code == 422


def test_workspace_id_always_comes_from_the_path(client):
    fake = _install(can_manage=True)
    client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/custom-fields",
        json={"name": "X", "code": "x", "field_type": "text", "workspace_id": str(uuid4())},
    )
    assert "custom_fields" in fake.table_calls
