import time

import jwt as pyjwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings

TEST_SECRET = "unit-test-jwt-secret"


@pytest.fixture(autouse=True)
def configured_secret(monkeypatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", TEST_SECRET)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


@pytest.fixture
def client():
    from app.main import app

    return TestClient(app)


def _token(**overrides):
    payload = {
        "sub": "33333333-3333-3333-3333-333333333333",
        "aud": "authenticated",
        "email": "rep@example.com",
        "exp": int(time.time()) + 3600,
    }
    payload.update(overrides)
    return pyjwt.encode(payload, TEST_SECRET, algorithm="HS256")


def test_me_without_a_token_is_401(client):
    response = client.get("/api/v1/me")
    assert response.status_code == 401
    assert response.json()["error_code"] == "missing_token"


def test_me_with_a_malformed_header_is_401(client):
    response = client.get("/api/v1/me", headers={"Authorization": "NotBearer abc"})
    assert response.status_code == 401


def test_me_with_an_expired_token_is_401(client):
    token = _token(exp=int(time.time()) - 10)
    response = client.get("/api/v1/me", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 401
    assert response.json()["error_code"] == "token_expired"


def test_me_with_a_valid_token_returns_the_caller_identity(client):
    token = _token()
    response = client.get("/api/v1/me", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    body = response.json()
    assert body["id"] == "33333333-3333-3333-3333-333333333333"
    assert body["email"] == "rep@example.com"
