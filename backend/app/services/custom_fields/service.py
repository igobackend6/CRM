from datetime import date
from typing import Any
from uuid import UUID

from supabase import Client

from app.core.exceptions import ValidationError
from app.repositories.custom_fields import CustomFieldRepository, CustomFieldValueRepository


class CustomFieldService:
    """Phase 0 (Admin/App alignment) — Custom Lead Fields.

    Two jobs: CRUD on the field *definitions* (admin config, thin
    passthrough over the repository like MessageTemplateService), and —
    the part with real logic — validating and coercing per-lead
    *values* against their definitions before they're written. That
    second half is called by LeadService on lead create/update, so a
    custom value is validated the same way whether it arrives through
    the mobile app or the Admin panel.
    """

    def __init__(self, client: Client):
        self._client = client
        self._fields = CustomFieldRepository(client)
        self._values = CustomFieldValueRepository(client)

    # ---- definitions ----

    def list_fields(self, workspace_id: UUID) -> list[dict[str, Any]]:
        return self._fields.list_for_workspace(workspace_id)

    def create_field(self, workspace_id: UUID, data: dict[str, Any]) -> dict[str, Any]:
        return self._fields.create(workspace_id, data)

    def update_field(self, workspace_id: UUID, field_id: UUID, data: dict[str, Any]) -> dict[str, Any]:
        return self._fields.update(workspace_id, field_id, data)

    def delete_field(self, workspace_id: UUID, field_id: UUID) -> None:
        self._fields.delete(workspace_id, field_id)

    # ---- values (used by LeadService) ----

    def resolve_values_for_write(
        self, workspace_id: UUID, raw: dict[str, Any], *, require_mandatory: bool
    ) -> dict[str, Any]:
        """Turn a client-supplied `{field_code: value}` map into a
        `{custom_field_id: coerced_value}` map ready for
        CustomFieldValueRepository.upsert. Validates:
          - the code names a real, non-archived field in this workspace
          - the value matches the field's type (coerced where safe)
          - select values are among the field's declared options
          - read-only fields are not being written
          - on create (require_mandatory), every mandatory field is present
        Raises ValidationError with a specific message on any failure.
        """
        defs = {f["code"]: f for f in self._fields.list_for_workspace(workspace_id)}

        unknown = set(raw) - set(defs)
        if unknown:
            raise ValidationError(f"Unknown custom field(s): {', '.join(sorted(unknown))}")

        resolved: dict[str, Any] = {}
        for code, value in raw.items():
            field = defs[code]
            if field["is_readonly"] and value is not None:
                raise ValidationError(f"Custom field '{code}' is read-only")
            resolved[field["id"]] = None if value is None else _coerce(field, value)

        if require_mandatory:
            for code, field in defs.items():
                if field["is_mandatory"] and not field["is_readonly"] and raw.get(code) in (None, "", []):
                    raise ValidationError(f"Custom field '{code}' is required")

        return resolved

    def values_by_code(self, workspace_id: UUID, lead_id: UUID) -> dict[str, Any]:
        """`{field_code: value}` for one lead — for LeadOut / the lead's
        custom-fields endpoint."""
        defs_by_id = {f["id"]: f for f in self._fields.list_for_workspace(workspace_id)}
        out: dict[str, Any] = {}
        for row in self._values.list_for_lead(workspace_id, lead_id):
            field = defs_by_id.get(row["custom_field_id"])
            if field is not None:
                out[field["code"]] = row["value"]
        return out

    def write_values(self, workspace_id: UUID, lead_id: UUID, resolved: dict[str, Any]) -> None:
        if resolved:
            self._values.upsert(workspace_id, lead_id, resolved)


def _coerce(field: dict[str, Any], value: Any) -> Any:
    ftype = field["field_type"]
    code = field["code"]

    if ftype == "text":
        if not isinstance(value, str):
            raise ValidationError(f"Custom field '{code}' expects text")
        return value

    if ftype == "number":
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ValidationError(f"Custom field '{code}' expects a number")
        return value

    if ftype == "date":
        if not isinstance(value, str):
            raise ValidationError(f"Custom field '{code}' expects an ISO date string")
        try:
            date.fromisoformat(value[:10])
        except ValueError as exc:
            raise ValidationError(f"Custom field '{code}' is not a valid ISO date") from exc
        return value

    allowed = {o["code"] for o in field.get("options", [])}
    if ftype == "options":
        if value not in allowed:
            raise ValidationError(f"Custom field '{code}': '{value}' is not one of its options")
        return value

    if ftype == "multi_options":
        if not isinstance(value, list):
            raise ValidationError(f"Custom field '{code}' expects a list of option codes")
        bad = [v for v in value if v not in allowed]
        if bad:
            raise ValidationError(f"Custom field '{code}': {', '.join(map(str, bad))} not among its options")
        return value

    raise ValidationError(f"Custom field '{code}' has an unknown type '{ftype}'")
