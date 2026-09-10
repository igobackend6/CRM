import pytest
from fastapi.testclient import TestClient

from app.core.rate_limit import _RULES, reset_rate_limit_state
from app.main import app


@pytest.fixture
def client():
    return TestClient(app)


def test_a_rate_limited_path_returns_429_once_its_limit_is_exceeded(client):
    method, suffix, limit, _window = next(r for r in _RULES if r[1] == "/me")
    assert method == "GET"

    for _ in range(limit):
        response = client.get("/api/v1/me")
        assert response.status_code != 429

    response = client.get("/api/v1/me")
    assert response.status_code == 429
    assert response.json()["error_code"] == "rate_limited"


def test_different_callers_get_independent_rate_limit_buckets(client):
    """Two different Authorization header values (i.e. two different
    users) never share one counter — one caller being throttled must
    never block another."""
    method, suffix, limit, _window = next(r for r in _RULES if r[1] == "/me")

    for _ in range(limit):
        client.get("/api/v1/me", headers={"Authorization": "Bearer user-a-token"})
    throttled = client.get("/api/v1/me", headers={"Authorization": "Bearer user-a-token"})
    assert throttled.status_code == 429

    still_allowed = client.get("/api/v1/me", headers={"Authorization": "Bearer user-b-token"})
    assert still_allowed.status_code != 429


def test_a_path_with_no_matching_rule_is_never_rate_limited(client):
    for _ in range(500):
        response = client.get("/health")
    assert response.status_code == 200


def test_the_rate_limit_applies_before_authentication_so_an_unauthenticated_flood_is_still_throttled(client):
    """The middleware runs at the ASGI level, before FastAPI's own
    auth dependency — an attacker flooding a protected endpoint with NO
    token at all is still throttled, not just successful callers."""
    method, suffix, limit, _window = next(r for r in _RULES if r[1] == "/me")

    responses = [client.get("/api/v1/me") for _ in range(limit + 1)]

    assert all(r.status_code == 401 for r in responses[:limit])
    assert responses[-1].status_code == 429


def test_reset_rate_limit_state_clears_counters_between_tests():
    reset_rate_limit_state()
    client = TestClient(app)
    method, suffix, limit, _window = next(r for r in _RULES if r[1] == "/me")

    for _ in range(limit):
        client.get("/api/v1/me")
    assert client.get("/api/v1/me").status_code == 429

    reset_rate_limit_state()
    assert client.get("/api/v1/me").status_code != 429
