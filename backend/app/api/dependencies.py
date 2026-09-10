from typing import Annotated
from uuid import UUID

from fastapi import Depends, Header
from supabase import Client

from app.core.exceptions import UnauthorizedError
from app.core.supabase_client import get_user_scoped_client
from app.schemas.auth import AuthenticatedUser
from app.security import authorization as authz
from app.security.authentication import authenticate
from app.security.permissions import Permission


def _extract_bearer_token(authorization: str | None) -> str | None:
    if not authorization:
        return None
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        return None
    return token


def get_current_user(authorization: Annotated[str | None, Header()] = None) -> AuthenticatedUser:
    """FastAPI dependency: resolves the caller's identity from the
    `Authorization: Bearer <token>` header. Raises 401 (via
    UnauthorizedError) if it's missing or the token doesn't verify.
    """
    token = _extract_bearer_token(authorization)
    if token is None:
        raise UnauthorizedError("Missing or malformed Authorization header.", error_code="missing_token")
    return authenticate(token)


def get_user_client(user: Annotated[AuthenticatedUser, Depends(get_current_user)]) -> Client:
    """A Supabase client scoped to the current request's user — every
    query made through it is RLS-filtered exactly as if Flutter had
    called Supabase directly.
    """
    return get_user_scoped_client(user.access_token)


def require_workspace_member(
    workspace_id: UUID,
    client: Annotated[Client, Depends(get_user_client)],
) -> Client:
    """Route dependency: 403s unless the current user is an active
    member of :workspace_id (taken from the route's path parameter of
    the same name). Returns the user-scoped client so the route can
    reuse it for its own queries without asking twice.
    """
    authz.require_workspace_member(client, workspace_id)
    return client


def require_permission(permission: Permission):
    """Route dependency factory: 403s unless the current user has
    `permission` in :workspace_id (taken from the route's path
    parameter of the same name). Usage:

        @router.get("/workspaces/{workspace_id}/...")
        def handler(client: Client = Depends(require_permission(Permission.LEADS_READ))): ...
    """

    def dependency(
        workspace_id: UUID,
        client: Annotated[Client, Depends(get_user_client)],
    ) -> Client:
        authz.require_permission(client, workspace_id, permission)
        return client

    return dependency
