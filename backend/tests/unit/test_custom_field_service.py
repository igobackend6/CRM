from uuid import uuid4

import pytest

from app.core.exceptions import ValidationError
from app.services.custom_fields import CustomFieldService
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
LEAD_ID = uuid4()

TEXT_ID = str(uuid4())
NUM_ID = str(uuid4())
DATE_ID = str(uuid4())
SEL_ID = str(uuid4())
MULTI_ID = str(uuid4())
RO_ID = str(uuid4())
REQ_ID = str(uuid4())


def _field(id_, code, ftype, *, options=None, is_mandatory=False, is_readonly=False):
    return {
        "id": id_,
        "workspace_id": str(WORKSPACE_ID),
        "name": code.replace("_", " ").title(),
        "code": code,
        "field_type": ftype,
        "options": options or [],
        "auto_fill": True,
        "is_filterable": False,
        "is_readonly": is_readonly,
        "is_mandatory": is_mandatory,
        "sort_order": 0,
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }


_DEFS = [
    _field(TEXT_ID, "nickname", "text"),
    _field(NUM_ID, "deal_size", "number"),
    _field(DATE_ID, "renewal_date", "date"),
    _field(SEL_ID, "segment", "options", options=[{"code": "smb", "label": "SMB"}, {"code": "ent", "label": "Enterprise"}]),
    _field(MULTI_ID, "interests", "multi_options", options=[{"code": "a", "label": "A"}, {"code": "b", "label": "B"}]),
    _field(RO_ID, "score", "number", is_readonly=True),
    _field(REQ_ID, "region", "text", is_mandatory=True),
]


def _service(defs=None):
    client = FakeSupabaseClient(table_responses={"custom_fields": FakeResponse(data=defs if defs is not None else _DEFS)})
    return CustomFieldService(client)


def test_resolve_maps_codes_to_field_ids_and_coerces_each_type():
    svc = _service()
    resolved = svc.resolve_values_for_write(
        WORKSPACE_ID,
        {
            "nickname": "Ace",
            "deal_size": 5000,
            "renewal_date": "2026-12-01",
            "segment": "ent",
            "interests": ["a", "b"],
            "region": "APAC",
        },
        require_mandatory=True,
    )
    assert resolved[TEXT_ID] == "Ace"
    assert resolved[NUM_ID] == 5000
    assert resolved[SEL_ID] == "ent"
    assert resolved[MULTI_ID] == ["a", "b"]


def test_unknown_field_code_is_rejected():
    svc = _service()
    with pytest.raises(ValidationError, match="Unknown custom field"):
        svc.resolve_values_for_write(WORKSPACE_ID, {"not_a_field": "x"}, require_mandatory=False)


def test_wrong_type_is_rejected_per_field():
    svc = _service()
    with pytest.raises(ValidationError, match="expects a number"):
        svc.resolve_values_for_write(WORKSPACE_ID, {"deal_size": "lots"}, require_mandatory=False)
    with pytest.raises(ValidationError, match="not a valid ISO date"):
        svc.resolve_values_for_write(WORKSPACE_ID, {"renewal_date": "next tuesday"}, require_mandatory=False)


def test_options_value_must_be_a_declared_option():
    svc = _service()
    with pytest.raises(ValidationError, match="not one of its options"):
        svc.resolve_values_for_write(WORKSPACE_ID, {"segment": "gov"}, require_mandatory=False)
    with pytest.raises(ValidationError, match="not among its options"):
        svc.resolve_values_for_write(WORKSPACE_ID, {"interests": ["a", "z"]}, require_mandatory=False)


def test_multi_options_expects_a_list():
    svc = _service()
    with pytest.raises(ValidationError, match="expects a list of option codes"):
        svc.resolve_values_for_write(WORKSPACE_ID, {"interests": "a"}, require_mandatory=False)


def test_readonly_field_cannot_be_written():
    svc = _service()
    with pytest.raises(ValidationError, match="read-only"):
        svc.resolve_values_for_write(WORKSPACE_ID, {"score": 90}, require_mandatory=False)
    assert svc.resolve_values_for_write(WORKSPACE_ID, {"score": None}, require_mandatory=False) == {RO_ID: None}


def test_mandatory_fields_enforced_only_when_required():
    svc = _service()
    with pytest.raises(ValidationError, match="'region' is required"):
        svc.resolve_values_for_write(WORKSPACE_ID, {"nickname": "Ace"}, require_mandatory=True)
    assert svc.resolve_values_for_write(WORKSPACE_ID, {"nickname": "Ace"}, require_mandatory=False) == {TEXT_ID: "Ace"}


def test_null_value_is_kept_as_a_clear_instruction():
    svc = _service()
    assert svc.resolve_values_for_write(WORKSPACE_ID, {"nickname": None}, require_mandatory=False) == {TEXT_ID: None}


def test_values_by_code_joins_stored_values_back_to_their_field_code():
    client = FakeSupabaseClient(
        table_responses={
            "custom_fields": FakeResponse(data=_DEFS),
            "custom_field_values": FakeResponse(
                data=[{"custom_field_id": TEXT_ID, "value": "Ace"}, {"custom_field_id": SEL_ID, "value": "smb"}]
            ),
        }
    )
    out = CustomFieldService(client).values_by_code(WORKSPACE_ID, LEAD_ID)
    assert out == {"nickname": "Ace", "segment": "smb"}
