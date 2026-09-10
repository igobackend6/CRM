import time
from unittest.mock import MagicMock

import jwt as pyjwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec

from app.core.config import get_settings
from app.core.exceptions import UnauthorizedError
from app.security import jwt as jwt_module
from app.security.jwt import verify_access_token

TEST_SECRET = "unit-test-jwt-secret"


def _encode(payload: dict, secret: str = TEST_SECRET) -> str:
    return pyjwt.encode(payload, secret, algorithm="HS256")


@pytest.fixture(autouse=True)
def configured_secret(monkeypatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", TEST_SECRET)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def test_verify_access_token_accepts_a_valid_token():
    token = _encode({"sub": "11111111-1111-1111-1111-111111111111", "aud": "authenticated", "exp": int(time.time()) + 3600})
    claims = verify_access_token(token)
    assert str(claims.sub) == "11111111-1111-1111-1111-111111111111"


def test_verify_access_token_rejects_expired_token():
    token = _encode({"sub": "11111111-1111-1111-1111-111111111111", "aud": "authenticated", "exp": int(time.time()) - 10})
    with pytest.raises(UnauthorizedError) as exc_info:
        verify_access_token(token)
    assert exc_info.value.error_code == "token_expired"


def test_verify_access_token_rejects_bad_signature():
    token = _encode(
        {"sub": "11111111-1111-1111-1111-111111111111", "aud": "authenticated", "exp": int(time.time()) + 3600},
        secret="wrong-secret",
    )
    with pytest.raises(UnauthorizedError) as exc_info:
        verify_access_token(token)
    assert exc_info.value.error_code == "token_invalid"


def test_verify_access_token_requires_configured_secret(monkeypatch):
    # An explicit empty-string env var (not delenv) is required here:
    # Settings reads from backend/.env as a fallback source, and since a
    # real .env now exists locally (with a real SUPABASE_JWT_SECRET),
    # delenv alone wouldn't un-set it — pydantic-settings would just
    # fall through to the .env file's value. Setting the OS env var to
    # "" overrides the .env file (env vars take priority) and is falsy,
    # matching what "not configured" means to verify_access_token.
    monkeypatch.setenv("SUPABASE_JWT_SECRET", "")
    get_settings.cache_clear()
    token = _encode({"sub": "11111111-1111-1111-1111-111111111111", "aud": "authenticated", "exp": int(time.time()) + 3600})

    with pytest.raises(UnauthorizedError) as exc_info:
        verify_access_token(token)
    assert exc_info.value.error_code == "auth_not_configured"


# ---- asymmetric (ES256/JWKS) path — added after connecting to a real
# Supabase project (2026-09-03) whose access tokens turned out to be
# ES256-signed via a rotating JWKS key, not the legacy HS256 shared
# secret this module originally assumed exclusively. ----


def _encode_es256(payload: dict, private_key, kid: str = "test-kid") -> str:
    return pyjwt.encode(payload, private_key, algorithm="ES256", headers={"kid": kid})


@pytest.fixture
def es256_keypair():
    private_key = ec.generate_private_key(ec.SECP256R1())
    return private_key, private_key.public_key()


@pytest.fixture(autouse=True)
def configured_supabase_url(monkeypatch):
    # verify_access_token's asymmetric branch needs supabase_url to
    # build the JWKS endpoint URL — the other (HS256) tests in this
    # file don't exercise that branch, so this is harmless to them.
    monkeypatch.setenv("SUPABASE_URL", "https://unit-test-project.supabase.co")
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def test_verify_access_token_accepts_a_valid_es256_token(monkeypatch, es256_keypair):
    private_key, public_key = es256_keypair
    token = _encode_es256(
        {"sub": "22222222-2222-2222-2222-222222222222", "aud": "authenticated", "exp": int(time.time()) + 3600},
        private_key,
    )

    fake_signing_key = MagicMock(key=public_key)
    fake_client = MagicMock(get_signing_key_from_jwt=MagicMock(return_value=fake_signing_key))
    monkeypatch.setattr(jwt_module, "_jwks_client", lambda url: fake_client)

    claims = verify_access_token(token)

    assert str(claims.sub) == "22222222-2222-2222-2222-222222222222"
    fake_client.get_signing_key_from_jwt.assert_called_once_with(token)


def test_verify_access_token_rejects_an_es256_token_with_no_matching_jwks_key(monkeypatch, es256_keypair):
    private_key, _public_key = es256_keypair
    token = _encode_es256(
        {"sub": "22222222-2222-2222-2222-222222222222", "aud": "authenticated", "exp": int(time.time()) + 3600},
        private_key,
    )

    fake_client = MagicMock(get_signing_key_from_jwt=MagicMock(side_effect=pyjwt.PyJWKClientError("no matching key")))
    monkeypatch.setattr(jwt_module, "_jwks_client", lambda url: fake_client)

    with pytest.raises(UnauthorizedError) as exc_info:
        verify_access_token(token)
    assert exc_info.value.error_code == "token_invalid"


def test_verify_access_token_rejects_es256_token_when_no_supabase_url_configured(monkeypatch, es256_keypair):
    private_key, _public_key = es256_keypair
    token = _encode_es256(
        {"sub": "22222222-2222-2222-2222-222222222222", "aud": "authenticated", "exp": int(time.time()) + 3600},
        private_key,
    )
    monkeypatch.setenv("SUPABASE_URL", "")
    get_settings.cache_clear()

    with pytest.raises(UnauthorizedError) as exc_info:
        verify_access_token(token)
    assert exc_info.value.error_code == "auth_not_configured"
