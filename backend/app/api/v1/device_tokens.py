from typing import Annotated

from fastapi import APIRouter, Depends
from supabase import Client

from app.api.dependencies import get_current_user, get_user_client
from app.repositories.device_tokens import DeviceTokenRepository
from app.schemas.auth import AuthenticatedUser
from app.schemas.device_tokens import DeviceTokenRegister

# Phase 4 — FCM device token registry. Not workspace-scoped: a device
# token belongs to the person, not a membership (000030_device_tokens.sql).
# Every route runs as the caller's own user (no permission gate beyond
# being authenticated); device_tokens RLS pins every write to
# `profile_id = auth.uid()`.
router = APIRouter(tags=["device-tokens"])


@router.put("/device-tokens", status_code=204)
async def register_device_token(
    body: DeviceTokenRegister,
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    client: Annotated[Client, Depends(get_user_client)],
) -> None:
    """Called by the mobile app on login and on every FCM token refresh.
    Idempotent — re-registering the same token just bumps its
    updated_at."""
    DeviceTokenRepository(client).upsert_for_profile(user.id, token=body.token, platform=body.platform)


@router.delete("/device-tokens/{token}", status_code=204)
async def deregister_device_token(
    token: str,
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    client: Annotated[Client, Depends(get_user_client)],
) -> None:
    """Called on logout. A missing token is a no-op (still 204) — the
    end state is what matters."""
    DeviceTokenRepository(client).delete_for_profile(user.id, token)
