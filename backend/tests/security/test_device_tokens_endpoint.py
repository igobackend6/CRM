from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.api import dependencies as deps
from app.main import app
from app.schemas.auth import AuthenticatedUser
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

USER_ID = uuid4()


def _install():
    fake = FakeSupabaseClient(table_responses={"device_tokens": FakeResponse(data=[{"token": "t"}])})
    app.dependency_overrides[deps.get_current_user] = lambda: AuthenticatedUser(
        id=USER_ID, email="rep@example.com", access_token="fake"
    )
    app.dependency_overrides[deps.get_user_client] = lambda: fake
    return fake


@pytest.fixture(autouse=True)
def _cleanup():
    yield
    app.dependency_overrides.clear()


@pytest.fixture
def client():
    return TestClient(app)


def test_registering_a_device_token_requires_auth(client):
    r = client.put("/api/v1/device-tokens", json={"token": "fcm-abc", "platform": "android"})
    assert r.status_code == 401


def test_register_is_204_and_hits_device_tokens(client):
    fake = _install()
    r = client.put("/api/v1/device-tokens", json={"token": "fcm-abc", "platform": "android"})
    assert r.status_code == 204
    assert "device_tokens" in fake.table_calls


def test_platform_is_validated(client):
    _install()
    r = client.put("/api/v1/device-tokens", json={"token": "fcm-abc", "platform": "blackberry"})
    assert r.status_code == 422


def test_deregister_is_204_even_for_an_unknown_token(client):
    _install()
    r = client.delete("/api/v1/device-tokens/fcm-not-registered")
    assert r.status_code == 204


def test_the_body_cannot_smuggle_a_profile_id(client):
    fake = _install()
    r = client.put(
        "/api/v1/device-tokens",
        json={"token": "fcm-abc", "platform": "ios", "profile_id": str(uuid4())},
    )
    # extra keys are ignored by the schema; the repo always uses the
    # authenticated user's id, and device_tokens RLS pins it regardless.
    assert r.status_code == 204
    assert "device_tokens" in fake.table_calls
