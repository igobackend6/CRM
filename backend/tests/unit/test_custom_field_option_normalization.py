from uuid import uuid4

from app.repositories.custom_fields import CustomFieldRepository, normalize_options
from app.schemas.custom_fields import CustomFieldOut
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient


def _row(options):
    return {
        "id": str(uuid4()),
        "workspace_id": str(uuid4()),
        "name": "Interest",
        "code": "interest",
        "field_type": "options",
        "options": options,
        "auto_fill": True,
        "is_filterable": False,
        "is_readonly": False,
        "is_mandatory": False,
        "sort_order": 0,
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }


def test_plain_string_options_become_option_objects():
    row = normalize_options(_row(["Polyhouse", "Drip Irrigation"]))

    assert row["options"] == [
        {"code": "polyhouse", "label": "Polyhouse", "sort_order": 0},
        {"code": "drip_irrigation", "label": "Drip Irrigation", "sort_order": 1},
    ]


def test_the_normalized_row_passes_the_response_schema_that_used_to_fail():
    row = normalize_options(_row(["Interested", "Not Interested"]))

    out = CustomFieldOut(**row)

    assert [o.label for o in out.options] == ["Interested", "Not Interested"]


def test_option_objects_are_left_exactly_as_they_were():
    options = [{"code": "a", "label": "A", "sort_order": 3}]
    row = _row(options)

    assert normalize_options(row) is row
    assert row["options"] == options


def test_a_mixed_list_is_normalized_per_entry():
    row = normalize_options(_row(["Plain", {"code": "b", "label": "B", "sort_order": 5}]))

    assert row["options"] == [
        {"code": "plain", "label": "Plain", "sort_order": 0},
        {"code": "b", "label": "B", "sort_order": 5},
    ]


def test_blank_strings_are_dropped_and_surrounding_spaces_trimmed():
    row = normalize_options(_row(["  Hydroponics ", "", "   "]))

    assert row["options"] == [{"code": "hydroponics", "label": "Hydroponics", "sort_order": 0}]


def test_rows_without_options_are_untouched():
    assert normalize_options({"id": "x"}) == {"id": "x"}
    assert normalize_options(_row([]))["options"] == []


def test_the_repository_returns_normalized_rows_for_list_and_get():
    workspace_id = uuid4()
    stored = _row(["Polyhouse"])
    client = FakeSupabaseClient({"custom_fields": FakeResponse(data=[stored])})
    repo = CustomFieldRepository(client)

    listed = repo.list_for_workspace(workspace_id)

    assert listed[0]["options"] == [{"code": "polyhouse", "label": "Polyhouse", "sort_order": 0}]


def test_codes_are_valid_slugs_and_unique_even_for_awkward_labels():
    row = normalize_options(_row(["Organic Farming Consult", "organic farming consult", "3 Acres+", "!!!"]))

    codes = [o["code"] for o in row["options"]]
    assert codes == ["organic_farming_consult", "organic_farming_consult_2", "opt_3_acres", "opt"]
    assert len(set(codes)) == len(codes)
    CustomFieldOut(**row)  # every code satisfies the schema's slug rule


def test_a_new_code_never_collides_with_an_existing_object_option():
    row = normalize_options(_row([{"code": "polyhouse", "label": "Old", "sort_order": 0}, "Polyhouse"]))

    assert [o["code"] for o in row["options"]] == ["polyhouse", "polyhouse_2"]


def test_codes_are_stable_across_reads():
    first = normalize_options(_row(["Drip Irrigation"]))["options"]
    second = normalize_options(_row(["Drip Irrigation"]))["options"]

    assert first == second
