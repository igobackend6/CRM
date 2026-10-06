import re
from typing import Any
from uuid import UUID

from postgrest.exceptions import APIError

from app.core.exceptions import ConflictError, NotFoundError
from app.repositories.base import BaseRepository

# Postgres unique_violation — raised by custom_fields' unique
# (workspace_id, code) (supabase/migrations/000025_custom_fields.sql).
_UNIQUE_VIOLATION = "23505"


def _option_code(label: str, taken: set[str]) -> str:
    """A lowercase slug for [label] (the contract's option code shape), unique among [taken]."""
    slug = re.sub(r"[^a-z0-9]+", "_", label.lower()).strip("_")
    if not slug or not slug[0].isalpha():
        slug = f"opt_{slug}".rstrip("_")
    slug = slug[:90]
    code, n = slug, 2
    while code in taken:
        code = f"{slug}_{n}"
        n += 1
    taken.add(code)
    return code


def normalize_options(row: dict[str, Any]) -> dict[str, Any]:
    """Return [row] with every entry of `options` in the `{code, label, sort_order}` shape.

    The admin panel can save a choice as a plain string (`["Polyhouse", "Drip Irrigation"]`), while
    the contract (`CustomFieldOption`) is an object per choice with a lowercase-slug `code`. Left as
    is, one such field made `GET /custom-fields` fail validation (HTTP 500), which broke the mobile
    lead form for everyone. A plain string becomes `{code: <slug of it>, label: <the string>,
    sort_order: <position>}` (`"Drip Irrigation"` -> `drip_irrigation`). Objects pass through
    untouched. Codes are derived the same way on every read, so they are stable.
    """
    options = row.get("options")
    if not isinstance(options, list) or all(isinstance(o, dict) for o in options):
        return row
    taken = {o["code"] for o in options if isinstance(o, dict) and isinstance(o.get("code"), str)}
    fixed: list[Any] = []
    for position, option in enumerate(options):
        if isinstance(option, str):
            text = option.strip()
            if text:
                fixed.append({"code": _option_code(text, taken), "label": text, "sort_order": position})
        else:
            fixed.append(option)
    return {**row, "options": fixed}


class CustomFieldRepository(BaseRepository):
    """`custom_fields` (000025_custom_fields.sql) — workspace-defined
    extra fields on a lead. Same flat, workspace-scoped CRUD shape as
    MessageTemplateRepository; write access is gated by RLS
    (workspace.manage), not here."""

    table_name = "custom_fields"

    def list_for_workspace(self, workspace_id: UUID) -> list[dict[str, Any]]:
        rows = (
            self._client.table("custom_fields")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .order("sort_order")
            .order("created_at")
            .execute()
            .data
            or []
        )
        return [normalize_options(row) for row in rows]

    def get_for_workspace(self, workspace_id: UUID, field_id: UUID) -> dict[str, Any]:
        response = (
            self._client.table("custom_fields")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .eq("id", str(field_id))
            .maybe_single()
            .execute()
        )
        if response is None or response.data is None:
            raise NotFoundError(f"Custom field {field_id} not found.")
        return normalize_options(response.data)

    def create(self, workspace_id: UUID, data: dict[str, Any]) -> dict[str, Any]:
        row = {**data, "workspace_id": str(workspace_id)}
        try:
            response = self._client.table("custom_fields").insert(row).execute()
        except APIError as exc:
            if getattr(exc, "code", None) == _UNIQUE_VIOLATION:
                raise ConflictError(
                    f"A custom field with code '{data.get('code')}' already exists in this workspace."
                ) from exc
            raise
        return response.data[0]

    def update(self, workspace_id: UUID, field_id: UUID, data: dict[str, Any]) -> dict[str, Any]:
        response = (
            self._client.table("custom_fields")
            .update(data)
            .eq("workspace_id", str(workspace_id))
            .eq("id", str(field_id))
            .execute()
        )
        if not response.data:
            raise NotFoundError(f"Custom field {field_id} not found.")
        return response.data[0]

    def delete(self, workspace_id: UUID, field_id: UUID) -> None:
        # ON DELETE CASCADE on custom_field_values (000025) removes every
        # stored value for this field.
        response = (
            self._client.table("custom_fields")
            .delete()
            .eq("workspace_id", str(workspace_id))
            .eq("id", str(field_id))
            .execute()
        )
        if not response.data:
            raise NotFoundError(f"Custom field {field_id} not found.")


class CustomFieldValueRepository:
    """`custom_field_values` — per-lead values, primary-keyed on
    (lead_id, custom_field_id). A pure junction-ish table with no
    surrogate id, so a standalone repository rather than a
    BaseRepository subclass (same call as LeadTagRepository)."""

    def __init__(self, client):
        self._client = client

    def list_for_lead(self, workspace_id: UUID, lead_id: UUID) -> list[dict[str, Any]]:
        return (
            self._client.table("custom_field_values")
            .select("custom_field_id, value")
            .eq("workspace_id", str(workspace_id))
            .eq("lead_id", str(lead_id))
            .execute()
            .data
            or []
        )

    def map_for_leads(self, workspace_id: UUID, lead_ids: list[str]) -> dict[str, dict[str, Any]]:
        """lead_id -> {custom_field_id: value} for a batch of leads —
        avoids an N+1 when enriching a page of leads (same shape as
        LeadTagRepository.map_tags_for_leads)."""
        ids = [i for i in lead_ids if i]
        if not ids:
            return {}
        rows = (
            self._client.table("custom_field_values")
            .select("lead_id, custom_field_id, value")
            .eq("workspace_id", str(workspace_id))
            .in_("lead_id", ids)
            .execute()
            .data
            or []
        )
        result: dict[str, dict[str, Any]] = {}
        for row in rows:
            result.setdefault(row["lead_id"], {})[row["custom_field_id"]] = row["value"]
        return result

    def upsert(self, workspace_id: UUID, lead_id: UUID, values: dict[str, Any]) -> None:
        """values is {custom_field_id: json_value}. A null value clears
        the field (delete the row) rather than storing json null, so
        "unset" and "explicitly null" read the same downstream."""
        to_set = [
            {
                "workspace_id": str(workspace_id),
                "lead_id": str(lead_id),
                "custom_field_id": field_id,
                "value": value,
            }
            for field_id, value in values.items()
            if value is not None
        ]
        to_clear = [field_id for field_id, value in values.items() if value is None]

        if to_set:
            try:
                self._client.table("custom_field_values").upsert(
                    to_set, on_conflict="lead_id,custom_field_id"
                ).execute()
            except APIError as exc:
                raise ConflictError(f"Could not save custom field values: {exc.message}") from exc
        for field_id in to_clear:
            self._client.table("custom_field_values").delete().eq("workspace_id", str(workspace_id)).eq(
                "lead_id", str(lead_id)
            ).eq("custom_field_id", field_id).execute()
