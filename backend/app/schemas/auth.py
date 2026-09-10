from uuid import UUID

from pydantic import BaseModel


class TokenPayload(BaseModel):
    """The subset of a verified Supabase JWT's claims this backend
    actually reads. Extra claims are ignored, not rejected."""

    sub: UUID
    email: str | None = None
    phone: str | None = None
    role: str | None = None
    exp: int
    aud: str | None = None


class AuthenticatedUser(BaseModel):
    """The caller's identity, as established by security/authentication.py.
    Deliberately carries no workspace/role/permission data — those are
    per-workspace (see docs/architecture/rbac.md) and resolved by
    security/authorization.py against the database, not embedded here.
    """

    id: UUID
    email: str | None = None
    phone: str | None = None
    access_token: str
