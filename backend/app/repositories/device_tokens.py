from typing import Any
from uuid import UUID

from postgrest.exceptions import APIError

from app.core.exceptions import ConflictError
from app.repositories.base import BaseRepository


class DeviceTokenRepository(BaseRepository):
    """`device_tokens` (000030_device_tokens.sql) — FCM registration
    tokens per profile. The mobile app upserts its own token via the
    user-scoped client (RLS: profile_id = auth.uid()); the backend reads
    across profiles via the service-role client to dispatch a push."""

    table_name = "device_tokens"

    def upsert_for_profile(self, profile_id: UUID, *, token: str, platform: str) -> dict[str, Any]:
        """Register (or re-register) one device. Keyed on `token` — the
        same token re-registering just bumps updated_at; a token that
        moved to a new profile (shared device) gets re-owned."""
        row = {"profile_id": str(profile_id), "token": token, "platform": platform}
        try:
            response = self._client.table("device_tokens").upsert(row, on_conflict="token").execute()
        except APIError as exc:
            raise ConflictError(f"Could not register device token: {exc.message}") from exc
        return response.data[0] if response.data else row

    def delete_for_profile(self, profile_id: UUID, token: str) -> None:
        self._client.table("device_tokens").delete().eq("profile_id", str(profile_id)).eq("token", token).execute()

    def list_for_member(self, workspace_id: UUID, member_id: str) -> list[dict[str, Any]]:
        """Every device token for the profile behind a workspace member.
        Two hops: member -> workspace_members.profile_id -> device_tokens.
        Service-role only (crosses profiles)."""
        member = (
            self._client.table("workspace_members")
            .select("profile_id")
            .eq("workspace_id", str(workspace_id))
            .eq("id", member_id)
            .maybe_single()
            .execute()
        )
        if member is None or not member.data:
            return []
        profile_id = member.data["profile_id"]
        rows = self._client.table("device_tokens").select("id, token, platform").eq("profile_id", profile_id).execute()
        return rows.data or []

    def delete_tokens(self, tokens: list[str]) -> None:
        if tokens:
            self._client.table("device_tokens").delete().in_("token", tokens).execute()
