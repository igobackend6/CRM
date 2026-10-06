from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.api import dependencies as deps
from app.main import app
from app.schemas.auth import AuthenticatedUser
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = str(uuid4())
MEMBER_ID = str(uuid4())
BASE = f"/api/v1/workspaces/{WORKSPACE_ID}/activity"


def _install(*, is_member: bool = True, tables=None, member_id: str | None = MEMBER_ID):
    fake_client = FakeSupabaseClient(
        table_responses=tables or {},
        rpc_responses={"is_workspace_member": is_member, "current_member_id": member_id},
    )
    app.dependency_overrides[deps.get_current_user] = lambda: AuthenticatedUser(
        id=uuid4(), email="rep@example.com", access_token="fake-token"
    )
    app.dependency_overrides[deps.get_user_client] = lambda: fake_client
    return fake_client


@pytest.fixture(autouse=True)
def _cleanup():
    yield
    app.dependency_overrides.clear()


@pytest.fixture
def client():
    return TestClient(app)


_WRITES = ["heartbeat", "sign-out", "break/start", "break/end"]


@pytest.mark.parametrize("path", _WRITES)
def test_reporting_in_requires_authentication(client, path):
    app.dependency_overrides.clear()
    assert client.post(f"{BASE}/{path}").status_code == 401


@pytest.mark.parametrize("path", _WRITES)
def test_reporting_in_is_denied_for_a_non_member(client, path):
    _install(is_member=False)
    assert client.post(f"{BASE}/{path}").status_code == 403


@pytest.mark.parametrize("path", _WRITES)
def test_every_role_may_report_in_because_it_only_touches_their_own_rows(client, path):
    """Plain membership is the gate — no permission code, since a team_mate
    must log their own login time (and RLS pins the rows to them)."""
    _install()
    response = client.post(f"{BASE}/{path}")

    assert response.status_code == 200
    assert set(response.json()) == {"on_break", "break_started_at"}


def test_a_heartbeat_with_no_body_uses_a_zero_offset(client):
    _install()
    assert client.post(f"{BASE}/heartbeat").status_code == 200


def test_a_heartbeat_accepts_the_apps_utc_offset(client):
    _install()
    assert client.post(f"{BASE}/heartbeat", json={"utc_offset_minutes": 330}).status_code == 200


@pytest.mark.parametrize("offset", [841, -841, 10_000])
def test_an_impossible_utc_offset_is_rejected(client, offset):
    _install()
    assert client.post(f"{BASE}/heartbeat", json={"utc_offset_minutes": offset}).status_code == 422


def test_a_non_numeric_offset_is_rejected(client):
    _install()
    assert client.post(f"{BASE}/heartbeat", json={"utc_offset_minutes": "east"}).status_code == 422


def test_reporting_in_fails_cleanly_when_the_membership_cannot_be_resolved(client):
    _install(member_id=None)
    assert client.post(f"{BASE}/heartbeat").status_code == 422


def test_the_heartbeat_reports_an_open_break(client):
    _install(tables={"agent_breaks": FakeResponse(data=[{"id": "b1", "started_at": "2026-09-24T10:00:00+00:00", "ended_at": None}])})

    body = client.post(f"{BASE}/heartbeat").json()

    assert body["on_break"] is True
    assert body["break_started_at"].startswith("2026-09-24T10:00:00")


# ---- summary ----

_SUMMARY = {"since": "2026-09-23T18:30:00Z", "until": "2026-09-24T18:30:00Z"}


def test_summary_requires_authentication(client):
    app.dependency_overrides.clear()
    assert client.get(f"{BASE}/summary", params=_SUMMARY).status_code == 401


def test_summary_is_denied_for_a_non_member(client):
    _install(is_member=False)
    assert client.get(f"{BASE}/summary", params=_SUMMARY).status_code == 403


def test_summary_returns_every_total_in_seconds(client):
    _install()

    response = client.get(f"{BASE}/summary", params=_SUMMARY)

    assert response.status_code == 200
    assert set(response.json()) == {
        "since", "until", "login_seconds", "talk_seconds", "wrap_up_seconds", "break_seconds", "idle_seconds",
        "on_break", "break_started_at",
    }


def test_summary_computes_from_the_stored_rows(client):
    _install(
        tables={
            "agent_sessions": FakeResponse(
                data=[{"started_at": "2026-09-24T03:00:00+00:00", "last_seen_at": "2026-09-24T04:00:00+00:00", "ended_at": "2026-09-24T04:00:00+00:00"}]
            ),
        }
    )

    body = client.get(f"{BASE}/summary", params={"since": "2026-09-23T18:30:00Z", "until": "2099-01-01T00:00:00Z"}).json()

    assert body["login_seconds"] == 3600
    assert body["idle_seconds"] == 3600


@pytest.mark.parametrize("params", [{"until": _SUMMARY["until"]}, {"since": _SUMMARY["since"]}, {}])
def test_summary_requires_both_bounds(client, params):
    _install()
    assert client.get(f"{BASE}/summary", params=params).status_code == 422


def test_summary_rejects_a_reversed_window(client):
    _install()
    params = {"since": _SUMMARY["until"], "until": _SUMMARY["since"]}
    assert client.get(f"{BASE}/summary", params=params).status_code == 422


# ---- daily ----

_DAILY_ROW = {
    "member_id": MEMBER_ID,
    "day": "2026-09-24",
    "utc_offset_minutes": 330,
    "login_seconds": 3600,
    "talk_seconds": 600,
    "wrap_up_seconds": 120,
    "break_seconds": 300,
    "idle_seconds": 2580,
    "updated_at": "2026-09-24T10:00:00+00:00",
}


def test_daily_requires_authentication(client):
    app.dependency_overrides.clear()
    assert client.get(f"{BASE}/daily", params={"since": "2026-09-01", "until": "2026-09-30"}).status_code == 401


def test_daily_is_denied_for_a_non_member(client):
    _install(is_member=False)
    assert client.get(f"{BASE}/daily", params={"since": "2026-09-01", "until": "2026-09-30"}).status_code == 403


def test_daily_returns_the_stored_rows(client):
    _install(tables={"agent_daily_activity": FakeResponse(data=[_DAILY_ROW])})

    response = client.get(f"{BASE}/daily", params={"since": "2026-09-01", "until": "2026-09-30"})

    assert response.status_code == 200
    assert response.json() == [{**_DAILY_ROW, "updated_at": "2026-09-24T10:00:00Z"}]


def test_daily_can_be_narrowed_to_a_member(client):
    _install(tables={"agent_daily_activity": FakeResponse(data=[_DAILY_ROW])})

    response = client.get(f"{BASE}/daily", params={"since": "2026-09-01", "until": "2026-09-30", "member_id": MEMBER_ID})

    assert response.status_code == 200


def test_daily_rejects_a_malformed_member_id(client):
    _install()
    response = client.get(f"{BASE}/daily", params={"since": "2026-09-01", "until": "2026-09-30", "member_id": "nope"})
    assert response.status_code == 422


def test_daily_rejects_a_reversed_range(client):
    _install()
    assert client.get(f"{BASE}/daily", params={"since": "2026-09-30", "until": "2026-09-01"}).status_code == 422


@pytest.mark.parametrize("params", [{"since": "2026-09-01"}, {"until": "2026-09-30"}, {"since": "yesterday", "until": "today"}])
def test_daily_requires_valid_dates(client, params):
    _install()
    assert client.get(f"{BASE}/daily", params=params).status_code == 422
