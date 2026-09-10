import time

import jwt as pyjwt
import pytest

from app.core.config import get_settings
from app.core.exceptions import UnauthorizedError
from app.security.authentication import authenticate

TEST_SECRET = "unit-test-jwt-secret"


@pytest.fixture(autouse=True)
def configured_secret(monkeypatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", TEST_SECRET)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def test_authenticate_rejects_missing_token():
    with pytest.raises(UnauthorizedError) as exc_info:
        authenticate(None)
    assert exc_info.value.error_code == "missing_token"


def test_authenticate_returns_user_for_a_valid_token():
    user_id = "22222222-2222-2222-2222-222222222222"
    token = pyjwt.encode(
        {"sub": user_id, "aud": "authenticated", "email": "rep@example.com", "exp": int(time.time()) + 3600},
        TEST_SECRET,
        algorithm="HS256",
    )

    user = authenticate(token)

    assert str(user.id) == user_id
    assert user.email == "rep@example.com"
    assert user.access_token == token
