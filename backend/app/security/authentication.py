from app.core.exceptions import UnauthorizedError
from app.schemas.auth import AuthenticatedUser
from app.security.jwt import verify_access_token


def authenticate(bearer_token: str | None) -> AuthenticatedUser:
    """Turns a raw `Authorization: Bearer <token>` value into an
    AuthenticatedUser, or raises UnauthorizedError. Pure function, no
    FastAPI dependency-injection machinery — api/dependencies.py wraps
    this for use in route signatures, so this stays trivially unit
    testable on its own.
    """
    if not bearer_token:
        raise UnauthorizedError("Missing bearer token.", error_code="missing_token")

    claims = verify_access_token(bearer_token)

    return AuthenticatedUser(
        id=claims.sub,
        email=claims.email,
        phone=claims.phone,
        access_token=bearer_token,
    )
