import jwt as pyjwt
from jwt import PyJWKClient

from app.core.config import get_settings
from app.core.exceptions import UnauthorizedError
from app.schemas.auth import TokenPayload

# Older Supabase projects issue HS256-signed access tokens using a
# static, per-project "JWT secret". Projects created since Supabase's
# move to asymmetric signing keys (confirmed against the real project
# connected 2026-09-03 — its tokens' header is `{"alg": "ES256", ...}`)
# instead sign with a rotating EC/RSA key, verified via the project's
# public JWKS endpoint (`{SUPABASE_URL}/auth/v1/.well-known/jwks.json`),
# not a shared secret at all. A token's own `alg` header says which
# scheme was used, so this module supports both rather than assuming
# one — the existing unit tests (tests/unit/test_jwt.py) exercise the
# HS256 path with a locally-minted token; the JWKS path is exercised in
# scripts/validate_rls.py against the real project's real tokens.
_HS256 = "HS256"
_ASYMMETRIC_ALGORITHMS = ["ES256", "RS256"]

# One PyJWKClient per Supabase URL, reused across calls — PyJWKClient
# caches fetched keys internally (by kid, with a TTL), so this avoids
# both a repeated JWKS fetch per request and a repeated client
# construction per request.
_jwks_clients: dict[str, PyJWKClient] = {}


def _jwks_client(supabase_url: str) -> PyJWKClient:
    client = _jwks_clients.get(supabase_url)
    if client is None:
        client = PyJWKClient(f"{supabase_url.rstrip('/')}/auth/v1/.well-known/jwks.json")
        _jwks_clients[supabase_url] = client
    return client


def verify_access_token(token: str) -> TokenPayload:
    """Verifies a Supabase-issued access token's signature and expiry,
    and returns its claims. Raises UnauthorizedError (never a raw
    jwt.* exception) so callers don't need to know this module uses
    PyJWT specifically.
    """
    settings = get_settings()

    try:
        header = pyjwt.get_unverified_header(token)
    except pyjwt.InvalidTokenError as exc:
        raise UnauthorizedError("Access token is invalid.", error_code="token_invalid") from exc

    algorithm = header.get("alg")

    try:
        if algorithm in _ASYMMETRIC_ALGORITHMS:
            if not settings.supabase_url:
                raise UnauthorizedError("Server is not configured to verify access tokens.", error_code="auth_not_configured")
            signing_key = _jwks_client(settings.supabase_url).get_signing_key_from_jwt(token).key
            claims = pyjwt.decode(
                token, signing_key, algorithms=_ASYMMETRIC_ALGORITHMS, audience="authenticated",
                options={"require": ["exp", "sub"]},
            )
        else:
            if not settings.supabase_jwt_secret:
                raise UnauthorizedError("Server is not configured to verify access tokens.", error_code="auth_not_configured")
            claims = pyjwt.decode(
                token, settings.supabase_jwt_secret, algorithms=[_HS256], audience="authenticated",
                options={"require": ["exp", "sub"]},
            )
    except pyjwt.ExpiredSignatureError as exc:
        raise UnauthorizedError("Access token has expired.", error_code="token_expired") from exc
    except pyjwt.PyJWKClientError as exc:
        # JWKS unreachable, or no key matches the token's `kid`.
        raise UnauthorizedError("Access token is invalid.", error_code="token_invalid") from exc
    except pyjwt.InvalidTokenError as exc:
        raise UnauthorizedError("Access token is invalid.", error_code="token_invalid") from exc

    return TokenPayload.model_validate(claims)
