import time
from uuid import UUID

from supabase import Client

from app.core.exceptions import PermissionDeniedError
from app.security.permissions import Permission

# Deliberately thin: both functions delegate the actual decision to the
# database functions defined in supabase/migrations/000012_security_functions.sql
# (is_workspace_member, has_permission), called via RPC through a client
# already scoped to the caller's own access token (see
# core/supabase_client.get_user_scoped_client). This is a conscious
# choice not to reimplement role/permission resolution logic here —
# RLS/the database remains the single source of truth (per
# docs/architecture/rls.md), and this module is just the FastAPI-side
# enforcement point that turns "false" into a 403 before a route's
# business logic ever runs, and before any RLS-filtered-to-empty query
# result could be mistaken for "not found" instead of "not permitted."
#
# No FastAPI (Depends/Header) imports here on purpose — these functions
# take already-resolved values, so they're testable with a fake `Client`
# and no ASGI machinery. api/dependencies.py wires them into route
# signatures.


def is_workspace_member(client: Client, workspace_id: UUID) -> bool:
    result = client.rpc("is_workspace_member", {"p_workspace_id": str(workspace_id)}).execute()
    return bool(result.data)


def has_permission(client: Client, workspace_id: UUID, permission: Permission) -> bool:
    result = client.rpc(
        "has_permission",
        {"p_workspace_id": str(workspace_id), "p_permission_code": permission.value},
    ).execute()
    return bool(result.data)


def require_workspace_member(client: Client, workspace_id: UUID) -> None:
    if not is_workspace_member(client, workspace_id):
        raise PermissionDeniedError(f"Not a member of workspace {workspace_id}.")


def require_permission(client: Client, workspace_id: UUID, permission: Permission) -> None:
    if not has_permission(client, workspace_id, permission):
        raise PermissionDeniedError(f"Missing permission: {permission.value}")


# ---- short-lived cache of "yes" answers --------------------------------------------------------
# Every request used to ask the database two questions first (is this person a member? do they have
# this permission?) - two network round trips before any real work. A "yes" is remembered for a few
# seconds per (person, workspace, permission), so a screen that fires many requests at once asks once.
# Only "yes" is cached, and only briefly: a removed member or revoked permission is refused within
# _ALLOW_TTL_SECONDS, and the database (RLS) still enforces every row-level rule regardless.
_ALLOW_TTL_SECONDS = 30.0
_allowed_until: dict[tuple[str, str, str], float] = {}


def clear_allow_cache() -> None:
    _allowed_until.clear()


def _recently_allowed(key: tuple[str, str, str]) -> bool:
    expires = _allowed_until.get(key)
    if expires is None:
        return False
    if expires < time.monotonic():
        _allowed_until.pop(key, None)
        return False
    return True


def _remember_allowed(key: tuple[str, str, str]) -> None:
    if len(_allowed_until) > 5000:  # never grows without bound
        _allowed_until.clear()
    _allowed_until[key] = time.monotonic() + _ALLOW_TTL_SECONDS


def require_workspace_member_cached(client: Client, user_id: str, workspace_id: UUID) -> None:
    key = (user_id, str(workspace_id), "member")
    if _recently_allowed(key):
        return
    require_workspace_member(client, workspace_id)
    _remember_allowed(key)


def require_permission_cached(client: Client, user_id: str, workspace_id: UUID, permission: Permission) -> None:
    key = (user_id, str(workspace_id), permission.value)
    if _recently_allowed(key):
        return
    require_permission(client, workspace_id, permission)
    _remember_allowed(key)
