from datetime import datetime, timezone
from uuid import uuid4

import pytest

from app.core.exceptions import ValidationError
from app.services.leads import LeadService
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
MEMBER_ID = str(uuid4())
STATUS_ID = str(uuid4())
SOURCE_ID = str(uuid4())
TAG_ID = str(uuid4())
LEAD_ID = str(uuid4())


def _client(**overrides):
    table_responses = {
        "lead_statuses": FakeResponse(
            data=[{"id": STATUS_ID, "name": "New", "code": "new", "sort_order": 10, "stage": "in_progress", "is_default": True}]
        ),
        "lead_sources": FakeResponse(data=[{"id": SOURCE_ID, "name": "Website", "code": "website", "is_default": False}]),
        "workspace_members": FakeResponse(data=[{"id": MEMBER_ID, "profile": {"full_name": "Rep One"}}]),
        "lead_tags": FakeResponse(data=[]),
        "leads": FakeResponse(
            data=[
                {
                    "id": LEAD_ID,
                    "workspace_id": str(WORKSPACE_ID),
                    "name": "Acme Corp",
                    "phone": None,
                    "email": None,
                    "priority": "medium",
                    "status_id": STATUS_ID,
                    "source_id": SOURCE_ID,
                    "assigned_member_id": MEMBER_ID,
                    "created_by_member_id": MEMBER_ID,
                    "is_customer": False,
                    "created_at": "2026-01-01T00:00:00Z",
                    "updated_at": "2026-01-01T00:00:00Z",
                }
            ]
        ),
    }
    table_responses.update(overrides.pop("table_responses", {}))
    rpc_responses = {"current_member_id": MEMBER_ID}
    rpc_responses.update(overrides.pop("rpc_responses", {}))
    return FakeSupabaseClient(table_responses=table_responses, rpc_responses=rpc_responses)


def test_create_lead_assigns_the_creating_member_and_ignores_client_owner_fields():
    client = _client()
    service = LeadService(client)

    result = service.create_lead(WORKSPACE_ID, {"name": "Acme Corp", "assigned_member_id": "someone-else"})

    assert result["assigned_member"]["id"] == MEMBER_ID
    assert result["created_by_member"]["id"] == MEMBER_ID


def test_create_lead_resolves_the_default_status_when_omitted():
    client = _client()
    service = LeadService(client)

    result = service.create_lead(WORKSPACE_ID, {"name": "Acme Corp"})

    assert result["status"]["id"] == STATUS_ID
    assert result["status"]["is_default"] is True


def test_create_lead_raises_validation_error_with_no_default_status_configured():
    client = _client(table_responses={"lead_statuses": FakeResponse(data=[])})
    service = LeadService(client)

    with pytest.raises(ValidationError):
        service.create_lead(WORKSPACE_ID, {"name": "Acme Corp"})


def test_update_lead_with_no_fields_raises_validation_error():
    client = _client()
    service = LeadService(client)

    with pytest.raises(ValidationError):
        service.update_lead(WORKSPACE_ID, LEAD_ID, {})


def test_get_lead_enriches_status_source_assigned_member_and_tags():
    # get_for_workspace() uses .maybe_single(), so its response.data is a
    # single dict — unlike list_for_workspace()'s list of rows.
    lead_row = {
        "id": LEAD_ID,
        "workspace_id": str(WORKSPACE_ID),
        "name": "Acme Corp",
        "phone": None,
        "email": None,
        "priority": "medium",
        "status_id": STATUS_ID,
        "source_id": SOURCE_ID,
        "assigned_member_id": MEMBER_ID,
        "created_by_member_id": MEMBER_ID,
        "is_customer": False,
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }
    client = _client(
        table_responses={
            "leads": FakeResponse(data=lead_row),
            "lead_tags": FakeResponse(data=[{"lead_id": LEAD_ID, "tag": {"id": "t1", "name": "VIP", "color": None}}]),
        }
    )
    service = LeadService(client)

    result = service.get_lead(WORKSPACE_ID, LEAD_ID)

    assert result["status"]["name"] == "New"
    assert result["source"]["name"] == "Website"
    assert result["assigned_member"]["full_name"] == "Rep One"
    assert [t["name"] for t in result["tags"]] == ["VIP"]


def test_list_leads_returns_total_alongside_enriched_items():
    client = _client(table_responses={"leads": FakeResponse(data=[{"id": LEAD_ID, "workspace_id": str(WORKSPACE_ID), "name": "Acme Corp", "phone": None, "email": None, "priority": "medium", "status_id": STATUS_ID, "source_id": SOURCE_ID, "assigned_member_id": MEMBER_ID, "created_by_member_id": MEMBER_ID, "is_customer": False, "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z"}], count=1)})
    service = LeadService(client)

    items, total = service.list_leads(WORKSPACE_ID, search=None, status_id=None, limit=20, offset=0)

    assert total == 1
    assert items[0]["name"] == "Acme Corp"


# ---- Phase 14: advanced search & filters ----


def test_list_leads_rejects_a_status_id_that_does_not_belong_to_the_workspace():
    client = _client(table_responses={"lead_statuses": FakeResponse(data=[])})
    service = LeadService(client)

    with pytest.raises(ValidationError):
        service.list_leads(WORKSPACE_ID, search=None, status_id=uuid4(), limit=20, offset=0)


def test_list_leads_rejects_a_source_id_that_does_not_belong_to_the_workspace():
    client = _client(table_responses={"lead_sources": FakeResponse(data=[])})
    service = LeadService(client)

    with pytest.raises(ValidationError):
        service.list_leads(WORKSPACE_ID, search=None, status_id=None, source_id=uuid4(), limit=20, offset=0)


def test_list_leads_rejects_an_assigned_member_id_that_does_not_belong_to_the_workspace():
    client = _client(table_responses={"workspace_members": FakeResponse(data=[])})
    service = LeadService(client)

    with pytest.raises(ValidationError):
        service.list_leads(WORKSPACE_ID, search=None, status_id=None, assigned_member_id=uuid4(), limit=20, offset=0)


def test_list_leads_rejects_a_tag_id_that_does_not_belong_to_the_workspace():
    client = _client(table_responses={"tags": FakeResponse(data=[])})
    service = LeadService(client)

    with pytest.raises(ValidationError):
        service.list_leads(WORKSPACE_ID, search=None, status_id=None, tag_id=uuid4(), limit=20, offset=0)


def test_list_leads_rejects_an_invalid_priority():
    client = _client()
    service = LeadService(client)

    with pytest.raises(ValidationError):
        service.list_leads(WORKSPACE_ID, search=None, status_id=None, priority="urgent-ish", limit=20, offset=0)


def test_list_leads_accepts_a_valid_priority():
    client = _client()
    service = LeadService(client)

    items, total = service.list_leads(WORKSPACE_ID, search=None, status_id=None, priority="urgent", limit=20, offset=0)

    assert len(items) == 1


def test_list_leads_with_a_tag_matching_no_leads_short_circuits_to_an_empty_result():
    """The tag itself is valid (belongs to the workspace) but no
    `lead_tags` row references it — `list_for_workspace`'s `lead_id_in=[]`
    short-circuit should return an empty page without even needing the
    `leads` table fixture to reflect that (it still has the default
    single-row fixture, which would otherwise make this test a false
    positive if the short-circuit didn't fire)."""
    client = _client(
        table_responses={"tags": FakeResponse(data=[{"id": TAG_ID, "name": "VIP", "color": None}]), "lead_tags": FakeResponse(data=[])}
    )
    service = LeadService(client)

    items, total = service.list_leads(WORKSPACE_ID, search=None, status_id=None, tag_id=TAG_ID, limit=20, offset=0)

    assert items == []
    assert total == 0


def test_list_leads_with_a_tag_matching_a_lead_returns_results():
    client = _client(
        table_responses={
            "tags": FakeResponse(data=[{"id": TAG_ID, "name": "VIP", "color": None}]),
            "lead_tags": FakeResponse(data=[{"lead_id": LEAD_ID, "tag_id": TAG_ID}]),
        }
    )
    service = LeadService(client)

    items, total = service.list_leads(WORKSPACE_ID, search=None, status_id=None, tag_id=TAG_ID, limit=20, offset=0)

    assert len(items) == 1


def test_list_leads_combines_every_filter_without_error():
    client = _client(
        table_responses={"tags": FakeResponse(data=[{"id": TAG_ID, "name": "VIP", "color": None}]), "lead_tags": FakeResponse(data=[{"lead_id": LEAD_ID, "tag_id": TAG_ID}])}
    )
    service = LeadService(client)

    items, total = service.list_leads(
        WORKSPACE_ID,
        search="acme",
        status_id=STATUS_ID,
        source_id=SOURCE_ID,
        assigned_member_id=MEMBER_ID,
        priority="medium",
        is_customer=False,
        created_from=datetime(2026, 1, 1, tzinfo=timezone.utc),
        created_to=datetime(2026, 12, 31, tzinfo=timezone.utc),
        tag_id=TAG_ID,
        limit=20,
        offset=0,
    )

    assert len(items) == 1
    assert items[0]["name"] == "Acme Corp"


# ---- Phase 12: pipeline / status change ----


def test_change_lead_status_rejects_a_status_id_that_does_not_belong_to_the_workspace():
    client = _client(table_responses={"lead_statuses": FakeResponse(data=[])})
    service = LeadService(client)

    with pytest.raises(ValidationError):
        service.change_lead_status(WORKSPACE_ID, LEAD_ID, uuid4())


def test_change_lead_status_delegates_to_update_lead_for_a_valid_status():
    client = _client()
    service = LeadService(client)

    result = service.change_lead_status(WORKSPACE_ID, LEAD_ID, STATUS_ID)

    assert result["status"]["id"] == STATUS_ID
    # Reuses the same leads table update as update_lead() — no second
    # write path for status changes.
    assert "leads" in client.table_calls


def test_list_pipeline_groups_leads_by_status_preserving_sort_order():
    other_status_id = str(uuid4())
    client = _client(
        table_responses={
            "lead_statuses": FakeResponse(
                data=[
                    {"id": STATUS_ID, "name": "New", "code": "new", "sort_order": 10, "stage": "in_progress", "is_default": True},
                    {"id": other_status_id, "name": "Won", "code": "won", "sort_order": 20, "stage": "closed_won", "is_default": False},
                ]
            ),
            "leads": FakeResponse(
                data=[
                    {
                        "id": LEAD_ID,
                        "workspace_id": str(WORKSPACE_ID),
                        "name": "Acme Corp",
                        "phone": None,
                        "email": None,
                        "priority": "medium",
                        "status_id": STATUS_ID,
                        "source_id": SOURCE_ID,
                        "assigned_member_id": MEMBER_ID,
                        "created_by_member_id": MEMBER_ID,
                        "is_customer": False,
                        "created_at": "2026-01-01T00:00:00Z",
                        "updated_at": "2026-01-01T00:00:00Z",
                    }
                ],
                count=1,
            ),
        }
    )
    service = LeadService(client)

    columns = service.list_pipeline(WORKSPACE_ID, search=None, assigned_member_id=None, source_id=None, limit=20, offset=0)

    # Both statuses appear as columns, in the workspace's sort_order —
    # even the one with no matching leads (the fake returns the same
    # "leads" fixture for every status_id filter, but grouping itself
    # must not drop an empty column).
    assert [c["status"]["id"] for c in columns] == [STATUS_ID, other_status_id]
    first_column = columns[0]
    assert first_column["leads"][0]["name"] == "Acme Corp"
    assert first_column["leads"][0]["assigned_member"]["full_name"] == "Rep One"
    assert first_column["total"] == 1


def test_list_pipeline_card_omits_fields_not_needed_by_the_board():
    client = _client()
    service = LeadService(client)

    columns = service.list_pipeline(WORKSPACE_ID, search=None, assigned_member_id=None, source_id=None, limit=20, offset=0)

    card = columns[0]["leads"][0]
    assert set(card.keys()) == {"id", "name", "phone", "email", "priority", "status", "assigned_member", "updated_at"}


# ---- Phase 13: bulk actions ----


def test_bulk_assign_requires_member_id():
    client = _client()
    service = LeadService(client)

    with pytest.raises(ValidationError):
        service.bulk_update_leads(WORKSPACE_ID, [LEAD_ID], "assign", member_id=None, status_id=None)


def test_bulk_assign_rejects_an_inactive_or_cross_workspace_member_up_front():
    client = _client(table_responses={"workspace_members": FakeResponse(data=[])})
    service = LeadService(client)

    with pytest.raises(ValidationError):
        service.bulk_update_leads(WORKSPACE_ID, [LEAD_ID, str(uuid4())], "assign", member_id=uuid4(), status_id=None)
    # Never touched any lead — the target itself was rejected first.
    assert "leads" not in client.table_calls


def test_bulk_assign_delegates_to_assign_lead_for_every_id():
    client = _client(table_responses={"allocations": FakeResponse(data=[{"id": str(uuid4()), "status": "new"}])})
    service = LeadService(client)
    lead_ids = [LEAD_ID, str(uuid4()), str(uuid4())]

    results = service.bulk_update_leads(WORKSPACE_ID, lead_ids, "assign", member_id=MEMBER_ID, status_id=None)

    assert len(results) == 3
    assert all(r["success"] for r in results)
    assert [r["lead_id"] for r in results] == lead_ids


def test_bulk_unassign_happy_path():
    client = _client()
    service = LeadService(client)

    results = service.bulk_update_leads(WORKSPACE_ID, [LEAD_ID], "unassign", member_id=None, status_id=None)

    assert results == [{"lead_id": LEAD_ID, "success": True, "error": None}]


def test_bulk_change_status_requires_status_id():
    client = _client()
    service = LeadService(client)

    with pytest.raises(ValidationError):
        service.bulk_update_leads(WORKSPACE_ID, [LEAD_ID], "change_status", member_id=None, status_id=None)


def test_bulk_change_status_rejects_a_status_id_not_in_this_workspace():
    client = _client(table_responses={"lead_statuses": FakeResponse(data=[])})
    service = LeadService(client)

    with pytest.raises(ValidationError):
        service.bulk_update_leads(WORKSPACE_ID, [LEAD_ID], "change_status", member_id=None, status_id=uuid4())


def test_bulk_change_status_happy_path():
    client = _client()
    service = LeadService(client)

    results = service.bulk_update_leads(WORKSPACE_ID, [LEAD_ID], "change_status", member_id=None, status_id=STATUS_ID)

    assert results == [{"lead_id": LEAD_ID, "success": True, "error": None}]


def test_bulk_delete_happy_path():
    client = _client()
    service = LeadService(client)

    results = service.bulk_update_leads(WORKSPACE_ID, [LEAD_ID], "delete", member_id=None, status_id=None)

    assert results == [{"lead_id": LEAD_ID, "success": True, "error": None}]


def test_bulk_delete_reports_a_missing_or_not_visible_lead_as_a_per_lead_failure_not_an_exception():
    """Workspace isolation: a lead not in this workspace (or hidden by
    RLS) doesn't abort the whole batch — it's reported back per lead,
    same "same response whether missing or hidden" NotFoundError
    philosophy as the single-lead routes."""
    client = _client(table_responses={"leads": FakeResponse(data=[])})
    service = LeadService(client)

    results = service.bulk_update_leads(WORKSPACE_ID, [LEAD_ID, str(uuid4())], "delete", member_id=None, status_id=None)

    assert len(results) == 2
    assert all(not r["success"] for r in results)
    assert all(r["error"] for r in results)


# ---- Phase 13: CSV import ----


def _import_client(**overrides):
    return _client(**overrides)


def test_import_leads_csv_creates_valid_rows_and_resolves_status_source_by_name():
    client = _import_client()
    service = LeadService(client)
    csv_content = "name,phone,email,status,source,priority\nAcme Corp,+15551234567,acme@example.com,New,Website,high\n"

    result = service.import_leads_csv(WORKSPACE_ID, csv_content)

    assert result == {"total": 1, "created": 1, "failed": 0, "errors": []}


def test_import_leads_csv_omitted_status_falls_back_to_the_workspace_default():
    client = _import_client()
    service = LeadService(client)
    csv_content = "name\nAcme Corp\n"

    result = service.import_leads_csv(WORKSPACE_ID, csv_content)

    assert result["created"] == 1
    assert result["failed"] == 0


def test_import_leads_csv_rejects_a_missing_name_column():
    client = _import_client()
    service = LeadService(client)

    with pytest.raises(ValidationError):
        service.import_leads_csv(WORKSPACE_ID, "phone,email\n+15551234567,acme@example.com\n")


def test_import_leads_csv_reports_row_level_errors_without_aborting_the_import():
    """Mixed success/failure in one import: row 2 is missing a name, row
    3 has an unknown status, row 4 has an invalid priority — none of
    these should stop row 5 (valid) from being created."""
    client = _import_client()
    service = LeadService(client)
    csv_content = (
        "name,status,priority\n"
        ",New,medium\n"
        "Bad Status Co,Nonexistent,medium\n"
        "Bad Priority Co,New,not-a-priority\n"
        "Acme Corp,New,high\n"
    )

    result = service.import_leads_csv(WORKSPACE_ID, csv_content)

    assert result["total"] == 4
    assert result["created"] == 1
    assert result["failed"] == 3
    assert [e["row"] for e in result["errors"]] == [2, 3, 4]


def test_import_leads_csv_never_trusts_an_imported_owner_and_resolves_the_importing_member():
    client = _import_client()
    service = LeadService(client)

    service.import_leads_csv(WORKSPACE_ID, "name\nAcme Corp\n")

    assert ("current_member_id", {"p_workspace_id": str(WORKSPACE_ID)}) in client.rpc_calls
