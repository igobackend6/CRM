from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

import app.services.ai.service as ai_service_module
from app.api import dependencies as deps
from app.main import app
from app.schemas.auth import AuthenticatedUser
from app.services.ai.provider import AIProvider
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = str(uuid4())
OTHER_WORKSPACE_ID = str(uuid4())
LEAD_ID = str(uuid4())
CALL_ID = str(uuid4())
AGENT_ID = str(uuid4())


class _StubProvider(AIProvider):
    """Deterministic, offline stub used ONLY to prove the pipeline is
    reachable end-to-end when a provider IS configured — never a real
    provider, never network I/O, and never asserted as "real AI
    validated" in any report."""

    def transcribe(self, *, audio_ref: str) -> str:
        return "stub transcript"

    def summarize(self, *, transcript: str) -> str:
        return "stub summary"

    def analyze_sentiment(self, *, transcript: str) -> str:
        return "neutral"

    def extract_action_items(self, *, transcript: str) -> list[str]:
        return []

    def score_call(self, *, transcript: str) -> int:
        return 50

    def answer_question(self, *, context: str, question: str) -> str:
        return "stub answer"


def _lead_row():
    return {"id": LEAD_ID, "workspace_id": WORKSPACE_ID, "name": "Acme Corp", "priority": "medium", "is_customer": False}


def _call_row():
    return {"id": CALL_ID, "workspace_id": WORKSPACE_ID, "lead_id": LEAD_ID, "agent_member_id": AGENT_ID, "state": "ENDED"}


def _insight_row(**overrides):
    # Deliberately `completed` by default, not `pending`/`processing` —
    # those would trip request_analysis's own concurrency guard before
    # a POST's fresh pipeline run could ever be observed (the fake
    # returns this same fixture for both the guard's own read AND
    # upsert_pending's insert/update, since it's shared per-table — see
    # test_ai_insight_service.py's `_client` docstring for the identical
    # reasoning).
    row = {
        "id": str(uuid4()),
        "workspace_id": WORKSPACE_ID,
        "call_id": CALL_ID,
        "requested_by_member_id": AGENT_ID,
        "status": "completed",
        "provider": None,
        "transcript": None,
        "summary": None,
        "sentiment": None,
        "action_items": [],
        "call_score": None,
        "error_message": None,
        "requested_at": "2026-01-01T00:00:00Z",
        "completed_at": "2026-01-01T00:05:00Z",
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }
    row.update(overrides)
    return row


def _install(*, has_permission: bool, is_member: bool = True, table_responses=None):
    fake_client = FakeSupabaseClient(
        table_responses=table_responses
        or {
            "leads": FakeResponse(data=[_lead_row()]),
            "calls": FakeResponse(data=[_call_row()]),
            "ai_call_insights": FakeResponse(data=None),
            "interactions": FakeResponse(data=[{"id": str(uuid4()), "type": "note", "payload": {}}]),
            "workspace_members": FakeResponse(data=[{"id": AGENT_ID, "profile": {"full_name": "Agent Smith"}}]),
        },
        rpc_responses={"has_permission": has_permission, "is_workspace_member": is_member, "current_member_id": AGENT_ID},
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


# ---- GET .../calls/{call_id}/ai-insight ----


def test_get_insight_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/calls/{CALL_ID}/ai-insight")
    assert response.status_code == 401


def test_get_insight_denied_without_calls_read_permission(client):
    _install(has_permission=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/calls/{CALL_ID}/ai-insight")
    assert response.status_code == 403


def test_get_insight_returns_null_when_nothing_requested_yet(client):
    _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/calls/{CALL_ID}/ai-insight")
    assert response.status_code == 200
    assert response.json() is None


def test_get_insight_404s_for_a_call_not_visible_in_this_workspace(client):
    """Cross-workspace/unauthorized rejection: a call id that RLS would
    hide (simulated here by the fake returning no row) is a 404, not a
    leak of another workspace's call."""
    _install(has_permission=True, table_responses={"leads": FakeResponse(data=[_lead_row()]), "calls": FakeResponse(data=None)})
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/calls/{CALL_ID}/ai-insight")
    assert response.status_code == 404


def test_get_insight_workspace_id_is_taken_from_the_path_not_the_client(client):
    fake_client = _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/calls/{CALL_ID}/ai-insight")
    assert response.status_code == 200
    assert ("has_permission", {"p_workspace_id": WORKSPACE_ID, "p_permission_code": "calls.read"}) in fake_client.rpc_calls


# ---- POST .../calls/{call_id}/ai-insight ----


def test_request_analysis_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/calls/{CALL_ID}/ai-insight")
    assert response.status_code == 401


def test_request_analysis_denied_without_calls_update_permission(client):
    _install(has_permission=False)
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/calls/{CALL_ID}/ai-insight")
    assert response.status_code == 403


def test_request_analysis_404s_for_a_call_not_visible_in_this_workspace(client):
    _install(has_permission=True, table_responses={"calls": FakeResponse(data=None), "leads": FakeResponse(data=[_lead_row()])})
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/calls/{CALL_ID}/ai-insight")
    assert response.status_code == 404


def test_request_analysis_with_no_recording_and_no_provider_returns_a_failed_insight_not_a_5xx(client):
    """This environment's real, honest state: 200 with a `failed` row
    and a clear message — never a crash, never a fabricated result.
    (The fake echoes back its own configured "after" row for every
    write to the same table — see `_insight_row`'s docstring — so this
    is a routing/shape-level proof; the exact "missing recording ->
    failed, with THIS error text" *logic* is proven precisely at the
    unit level in test_ai_insight_service.py via a monkeypatched
    `update_for_call` that captures the real payload.)"""
    _install(
        has_permission=True,
        table_responses={
            "leads": FakeResponse(data=[_lead_row()]),
            "calls": FakeResponse(data=[_call_row()]),
            "ai_call_insights": FakeResponse(data=[_insight_row(status="failed", error_message="No call recording is available.")]),
            "interactions": FakeResponse(data=[{"id": str(uuid4()), "type": "note", "payload": {}}]),
            "workspace_members": FakeResponse(data=[{"id": AGENT_ID, "profile": {"full_name": "Agent Smith"}}]),
        },
    )
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/calls/{CALL_ID}/ai-insight")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "failed"
    assert body["error_message"]
    assert body["transcript"] is None
    assert body["summary"] is None


def test_request_analysis_completes_when_a_recording_and_provider_are_both_injected(client, monkeypatch):
    """Proves the pipeline is reachable end-to-end through the real HTTP
    route once both prerequisites exist — using an injected stub
    provider, never a real one, and a call row with a test-only
    recording_url key (`calls` has no such column in the real schema;
    see AIInsightService's own docstring). The fake echoes back its
    configured "after" row for every write to the same table, so the
    fixture below is pre-set to what the stub provider would produce —
    this is a routing/response-shape proof; the exact computation is
    proven precisely at the unit level (test_ai_insight_service.py's
    `test_request_analysis_runs_every_pipeline_stage_in_order_and_completes`,
    which captures the real update payload via monkeypatching)."""
    monkeypatch.setattr(ai_service_module, "get_ai_provider", lambda: _StubProvider())
    _install(
        has_permission=True,
        table_responses={
            "leads": FakeResponse(data=[_lead_row()]),
            "calls": FakeResponse(data=[{**_call_row(), "recording_url": "recordings/w1/c1.wav"}]),
            "ai_call_insights": FakeResponse(
                data=[_insight_row(status="completed", summary="stub summary", sentiment="neutral", transcript="stub transcript", call_score=50)]
            ),
            "interactions": FakeResponse(data=[{"id": str(uuid4()), "type": "note", "payload": {}}]),
            "workspace_members": FakeResponse(data=[{"id": AGENT_ID, "profile": {"full_name": "Agent Smith"}}]),
        },
    )
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/calls/{CALL_ID}/ai-insight")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "completed"
    assert body["summary"] == "stub summary"
    assert body["sentiment"] == "neutral"


# ---- GET .../leads/{lead_id}/ai-insights ----


def test_list_lead_insights_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/ai-insights")
    assert response.status_code == 401


def test_list_lead_insights_denied_without_leads_read_permission(client):
    _install(has_permission=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/ai-insights")
    assert response.status_code == 403


def test_list_lead_insights_404s_for_a_lead_not_visible_in_this_workspace(client):
    _install(has_permission=True, table_responses={"leads": FakeResponse(data=None)})
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/ai-insights")
    assert response.status_code == 404


def test_list_lead_insights_on_a_lead_with_no_analyzed_calls_returns_an_empty_list(client):
    _install(has_permission=True, table_responses={"leads": FakeResponse(data=[_lead_row()]), "calls": FakeResponse(data=[])})
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/ai-insights")
    assert response.status_code == 200
    assert response.json() == []


# ---- POST .../leads/{lead_id}/ai-assistant ----


def test_ask_assistant_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/ai-assistant", json={"question": "hi"})
    assert response.status_code == 401


def test_ask_assistant_denied_without_leads_read_permission(client):
    _install(has_permission=False)
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/ai-assistant", json={"question": "hi"})
    assert response.status_code == 403


def test_ask_assistant_404s_for_a_lead_not_visible_in_this_workspace(client):
    _install(has_permission=True, table_responses={"leads": FakeResponse(data=None)})
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/ai-assistant", json={"question": "hi"})
    assert response.status_code == 404


def test_ask_assistant_reports_unavailable_when_no_provider_is_configured(client):
    """The one meaningful assistant behavior available in this
    environment today — no provider configured, so it reports that
    honestly rather than 5xx-ing or fabricating an answer."""
    _install(has_permission=True)
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/ai-assistant", json={"question": "hi"})
    assert response.status_code == 200
    body = response.json()
    assert body["available"] is False
    assert body["answer"] is None


def test_ask_assistant_rejects_an_empty_question(client):
    _install(has_permission=True)
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/ai-assistant", json={"question": ""})
    assert response.status_code == 422


def test_ask_assistant_never_receives_a_workspace_id_that_disagrees_with_the_path(client):
    """§"Security" — never trusts a client-supplied workspace/actor
    identity; the only workspace_id in play is the one already
    validated by require_permission from the URL path, regardless of
    anything in the request body (there is no workspace_id field in
    AIAssistantQuestion at all — this test documents that by
    construction)."""
    fake_client = _install(has_permission=True)
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/ai-assistant",
        json={"question": "hi", "workspace_id": OTHER_WORKSPACE_ID},
    )
    assert response.status_code == 200
    assert ("has_permission", {"p_workspace_id": WORKSPACE_ID, "p_permission_code": "leads.read"}) in fake_client.rpc_calls
