from typing import Annotated

from fastapi import APIRouter, Depends

from app.api.dependencies import get_current_user
from app.schemas.auth import AuthenticatedUser

router = APIRouter(tags=["auth"])


@router.get("/me")
async def read_current_user(
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
) -> dict:
    """Identity/session verification endpoint — not a CRM feature. Its
    only purpose is proving the JWT-verification foundation works
    end-to-end (401 without a valid token, the caller's own id back with
    one). No workspace/role/permission data here — see
    docs/architecture/rbac.md for why that's resolved per-workspace,
    not attached to "who am I."
    """
    return {"id": str(user.id), "email": user.email, "phone": user.phone}
