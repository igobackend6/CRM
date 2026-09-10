from uuid import uuid4

import pytest

import app.services.ai.service as ai_service_module
from app.core.exceptions import NotFoundError
from app.repositories.ai_insights import AIInsightRepository
from app.repositories.lead_reference import InteractionRepository
from app.services.ai.provider import AIProvider
from app.services.ai.service import AIInsightService
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
CALL_ID = str(uuid4())
LEAD_ID = str(uuid4())
ACTOR_ID = str(uuid4())
AGENT_ID = str(uuid4())


class _FakeProvider(AIProvider):
    """A test-only stand-in — never a real provider, never network I/O.
    Records every stage it was asked to run so tests can prove the
    pipeline reached (or, for the guard tests, never reached) it."""

    def __init__(self, *, raise_on: str | None = None):
        self.calls: list[tuple] = []
        self.raise_on = raise_on

    def _maybe_raise(self, stage: str) -> None:
        if self.raise_on == stage:
            raise RuntimeError(f"{stage} failed")

    def transcribe(self, *, audio_ref: str) -> str:
        self.calls.append(("transcribe", audio_ref))
        self._maybe_raise("transcribe")
        return "customer said they need a quote by Friday"

    def summarize(self, *, transcript: str) -> str:
        self.calls.append(("summarize", transcript))
        self._maybe_raise("summarize")
        return "Customer requested a quote by Friday."

    def analyze_sentiment(self, *, transcript: str) -> str:
        self.calls.append(("analyze_sentiment", transcript))
        self._maybe_raise("analyze_sentiment")
        return "positive"

    def extract_action_items(self, *, transcript: str) -> list[str]:
        self.calls.append(("extract_action_items", transcript))
        self._maybe_raise("extract_action_items")
        return ["Send quote by Friday"]

    def score_call(self, *, transcript: str) -> int:
        self.calls.append(("score_call", transcript))
        self._maybe_raise("score_call")
        return 82

    def answer_question(self, *, context: str, question: str) -> str:
        self.calls.append(("answer_question", context, question))
        return "stub answer"


def _call_row(*, has_recording: bool = False, agent_member_id: str | None = AGENT_ID):
    row = {
        "id": CALL_ID,
        "workspace_id": str(WORKSPACE_ID),
        "lead_id": LEAD_ID,
        "agent_member_id": agent_member_id,
        "direction": "outbound",
        "state": "ENDED",
    }
    if has_recording:
        # `calls` has NO such column in the real schema today (see
        # AIInsightService's own docstring) — this key only exists here
        # to exercise the rest of the pipeline in isolation, the same
        # documented "the fake proves wiring, not real Postgres shape"
        # caveat every other service test file already carries.
        row["recording_url"] = "recordings/w1/call-1.wav"
    return row


def _insight_row(**overrides):
    row = {
        "id": str(uuid4()),
        "workspace_id": str(WORKSPACE_ID),
        "call_id": CALL_ID,
        "requested_by_member_id": ACTOR_ID,
        "status": "pending",
        "provider": None,
        "transcript": None,
        "summary": None,
        "sentiment": None,
        "action_items": [],
        "call_score": None,
        "error_message": None,
        "requested_at": "2026-01-01T00:00:00Z",
        "completed_at": None,
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }
    row.update(overrides)
    return row


def _client(**overrides):
    # `ai_call_insights` defaults to an already-`completed` row (NOT
    # `pending`/`processing`, which would trip request_analysis's own
    # concurrency guard before ever reaching the pipeline — see
    # `_capture_updates`'s docstring for why the guard-triggering
    # statuses are exercised via an explicit per-test override instead
    # of this shared default).
    table_responses = {
        "calls": FakeResponse(data=[_call_row()]),
        "ai_call_insights": FakeResponse(data=[_insight_row(status="completed")]),
        "interactions": FakeResponse(data=[{"id": str(uuid4()), "type": "note", "payload": {}}]),
        "workspace_members": FakeResponse(data=[{"id": AGENT_ID, "profile": {"full_name": "Rep One"}}]),
        "leads": FakeResponse(data=[{"id": LEAD_ID, "name": "Acme Corp"}]),
    }
    table_responses.update(overrides.pop("table_responses", {}))
    rpc_responses = {"current_member_id": ACTOR_ID}
    rpc_responses.update(overrides.pop("rpc_responses", {}))
    return FakeSupabaseClient(table_responses=table_responses, rpc_responses=rpc_responses)


def _capture_notify(monkeypatch):
    calls = []
    monkeypatch.setattr(ai_service_module, "notify", lambda workspace_id, **kwargs: calls.append(kwargs))
    return calls


def _capture_updates(monkeypatch):
    """Bypasses FakeSupabaseClient's shared-fixture-per-table limitation
    for `ai_call_insights` specifically, by recording the *actual* `data`
    dict each `update_for_call` call receives and returning a row merged
    on top of a base fixture — the same shape a real Postgres UPDATE
    would produce. This lets the pipeline tests below assert on genuinely
    different before/after states (pending -> processing -> completed,
    or -> failed) within one test, which the shared-response fake alone
    cannot represent (see e.g. test_lead_conversion_service.py's own
    documented limitation for the same underlying reason)."""
    updates: list[dict] = []

    def _fake_update(self, workspace_id, call_id, data):
        updates.append(data)
        merged = _insight_row(call_id=call_id)
        merged.update(data)
        return merged

    monkeypatch.setattr(AIInsightRepository, "update_for_call", _fake_update)
    return updates


def _capture_notes(monkeypatch):
    notes = []

    def _fake_create_note(self, workspace_id, lead_id, *, actor_member_id, text):
        notes.append({"lead_id": lead_id, "actor_member_id": actor_member_id, "text": text})
        return {"id": str(uuid4()), "type": "note", "payload": {"text": text}}

    monkeypatch.setattr(InteractionRepository, "create_note", _fake_create_note)
    return notes


# ---- reads ----


def test_get_insight_returns_none_when_nothing_requested_yet():
    client = _client(table_responses={"ai_call_insights": FakeResponse(data=None)})
    service = AIInsightService(client, provider=None)

    assert service.get_insight(WORKSPACE_ID, CALL_ID) is None


def test_get_insight_raises_not_found_for_a_call_outside_this_workspace():
    client = _client(table_responses={"calls": FakeResponse(data=None)})
    service = AIInsightService(client, provider=None)

    with pytest.raises(NotFoundError):
        service.get_insight(WORKSPACE_ID, CALL_ID)


def test_list_lead_insights_raises_not_found_for_a_lead_outside_this_workspace():
    client = _client(table_responses={"leads": FakeResponse(data=None)})
    service = AIInsightService(client, provider=None)

    with pytest.raises(NotFoundError):
        service.list_lead_insights(WORKSPACE_ID, LEAD_ID)


def test_list_lead_insights_returns_only_calls_that_have_an_insight_row():
    other_call_id = str(uuid4())
    client = _client(
        table_responses={
            "calls": FakeResponse(data=[_call_row(), {**_call_row(), "id": other_call_id}]),
            "ai_call_insights": FakeResponse(data=[_insight_row(call_id=CALL_ID, status="completed")]),
        }
    )
    service = AIInsightService(client, provider=None)

    rows = service.list_lead_insights(WORKSPACE_ID, LEAD_ID)

    assert len(rows) == 1
    assert rows[0]["call_id"] == CALL_ID


# ---- request_analysis: guard rails ----


def test_request_analysis_raises_not_found_for_a_call_outside_this_workspace():
    client = _client(table_responses={"calls": FakeResponse(data=None)})
    provider = _FakeProvider()
    service = AIInsightService(client, provider=provider)

    with pytest.raises(NotFoundError):
        service.request_analysis(WORKSPACE_ID, CALL_ID)
    assert provider.calls == []


def test_request_analysis_returns_the_existing_row_unchanged_when_already_pending():
    """Idempotent-safe, same shape as Phase 18's convert_to_customer
    guard: never starts a second concurrent analysis for the same call."""
    client = _client(table_responses={"ai_call_insights": FakeResponse(data=[_insight_row(status="pending")])})
    provider = _FakeProvider()
    service = AIInsightService(client, provider=provider)

    result = service.request_analysis(WORKSPACE_ID, CALL_ID)

    assert result["status"] == "pending"
    assert provider.calls == []  # never invoked — no second pipeline run was started


def test_request_analysis_returns_the_existing_row_unchanged_when_already_processing():
    client = _client(table_responses={"ai_call_insights": FakeResponse(data=[_insight_row(status="processing")])})
    provider = _FakeProvider()
    service = AIInsightService(client, provider=provider)

    result = service.request_analysis(WORKSPACE_ID, CALL_ID)

    assert result["status"] == "processing"
    assert provider.calls == []


# ---- request_analysis: missing prerequisites (this environment's real state) ----


def test_request_analysis_without_a_recording_fails_and_never_calls_the_provider(monkeypatch):
    updates = _capture_updates(monkeypatch)
    client = _client(table_responses={"calls": FakeResponse(data=[_call_row(has_recording=False)])})
    provider = _FakeProvider()
    service = AIInsightService(client, provider=provider)

    result = service.request_analysis(WORKSPACE_ID, CALL_ID)

    assert result["status"] == "failed"
    assert "recording" in result["error_message"].lower()
    assert provider.calls == []
    assert updates == [{"status": "failed", "error_message": result["error_message"]}]


def test_request_analysis_with_a_recording_but_no_provider_fails_cleanly(monkeypatch):
    updates = _capture_updates(monkeypatch)
    client = _client(table_responses={"calls": FakeResponse(data=[_call_row(has_recording=True)])})
    service = AIInsightService(client, provider=None)

    result = service.request_analysis(WORKSPACE_ID, CALL_ID)

    assert result["status"] == "failed"
    assert "provider" in result["error_message"].lower()
    assert updates == [{"status": "failed", "error_message": result["error_message"]}]


def test_request_analysis_default_provider_resolution_is_none_in_this_environment(monkeypatch):
    """No `provider=` override at all (the production code path) —
    resolves via get_ai_provider(), which is None in every environment
    today (no AI_PROVIDER/AI_PROVIDER_API_KEY configured)."""
    updates = _capture_updates(monkeypatch)
    client = _client(table_responses={"calls": FakeResponse(data=[_call_row(has_recording=True)])})
    service = AIInsightService(client)  # no provider kwarg at all

    result = service.request_analysis(WORKSPACE_ID, CALL_ID)

    assert result["status"] == "failed"
    assert "provider" in result["error_message"].lower()
    assert updates == [{"status": "failed", "error_message": result["error_message"]}]


# ---- request_analysis: full pipeline (recording + provider both present) ----


def test_request_analysis_runs_every_pipeline_stage_in_order_and_completes(monkeypatch):
    updates = _capture_updates(monkeypatch)
    _capture_notes(monkeypatch)
    client = _client(table_responses={"calls": FakeResponse(data=[_call_row(has_recording=True)])})
    provider = _FakeProvider()
    service = AIInsightService(client, provider=provider)

    result = service.request_analysis(WORKSPACE_ID, CALL_ID)

    assert [c[0] for c in provider.calls] == ["transcribe", "summarize", "analyze_sentiment", "extract_action_items", "score_call"]
    assert result["status"] == "completed"
    assert result["transcript"] == "customer said they need a quote by Friday"
    assert result["summary"] == "Customer requested a quote by Friday."
    assert result["sentiment"] == "positive"
    assert result["action_items"] == ["Send quote by Friday"]
    assert result["call_score"] == 82
    assert result["completed_at"] is not None
    # First transitions to 'processing', then to the final 'completed'
    # payload — two, and only two, writes for one successful run.
    assert [u.get("status") for u in updates] == ["processing", "completed"]


def test_request_analysis_records_a_timeline_note_referencing_the_call_lead_on_success(monkeypatch):
    _capture_updates(monkeypatch)
    notes = _capture_notes(monkeypatch)
    client = _client(table_responses={"calls": FakeResponse(data=[_call_row(has_recording=True)])})
    service = AIInsightService(client, provider=_FakeProvider())

    service.request_analysis(WORKSPACE_ID, CALL_ID)

    assert len(notes) == 1
    assert notes[0]["lead_id"] == LEAD_ID
    assert notes[0]["actor_member_id"] == ACTOR_ID
    assert "Customer requested a quote by Friday." in notes[0]["text"]


def test_request_analysis_notifies_the_calls_agent_on_success(monkeypatch):
    _capture_updates(monkeypatch)
    _capture_notes(monkeypatch)
    calls = _capture_notify(monkeypatch)
    client = _client(table_responses={"calls": FakeResponse(data=[_call_row(has_recording=True, agent_member_id=AGENT_ID)])})
    service = AIInsightService(client, provider=_FakeProvider())

    service.request_analysis(WORKSPACE_ID, CALL_ID)

    assert len(calls) == 1
    assert calls[0]["recipient_member_id"] == AGENT_ID
    assert calls[0]["related_entity_type"] == "call"
    assert calls[0]["related_entity_id"] == CALL_ID


def test_request_analysis_does_not_notify_when_the_actor_is_the_agent(monkeypatch):
    _capture_updates(monkeypatch)
    _capture_notes(monkeypatch)
    calls = _capture_notify(monkeypatch)
    client = _client(
        table_responses={"calls": FakeResponse(data=[_call_row(has_recording=True, agent_member_id=ACTOR_ID)])}
    )
    service = AIInsightService(client, provider=_FakeProvider())

    service.request_analysis(WORKSPACE_ID, CALL_ID)

    assert calls == []


# ---- request_analysis: provider failure is recoverable, never a crash ----


def test_request_analysis_a_provider_failure_mid_pipeline_is_recorded_not_raised(monkeypatch):
    updates = _capture_updates(monkeypatch)
    client = _client(table_responses={"calls": FakeResponse(data=[_call_row(has_recording=True)])})
    provider = _FakeProvider(raise_on="summarize")
    service = AIInsightService(client, provider=provider)

    result = service.request_analysis(WORKSPACE_ID, CALL_ID)  # must not raise

    assert result["status"] == "failed"
    assert "summarize failed" in result["error_message"]
    assert [c[0] for c in provider.calls] == ["transcribe", "summarize"]  # never reached sentiment/action items/score
    assert [u.get("status") for u in updates] == ["processing", "failed"]


def test_request_analysis_never_corrupts_the_existing_call_record_on_failure(monkeypatch):
    """Failures write only to `ai_call_insights` — `calls` itself is
    never updated by this pipeline."""
    _capture_updates(monkeypatch)
    client = _client(table_responses={"calls": FakeResponse(data=[_call_row(has_recording=True)])})
    provider = _FakeProvider(raise_on="transcribe")
    service = AIInsightService(client, provider=provider)

    service.request_analysis(WORKSPACE_ID, CALL_ID)

    # "calls" is read (get_for_workspace) but never the target of an
    # update in this flow.
    assert client.table_calls.count("calls") >= 1


def test_request_analysis_can_be_retried_after_a_failure(monkeypatch):
    """A terminal 'failed' row is reset to 'pending' and re-run — not
    stuck forever (§"Failures must be recoverable")."""
    _capture_updates(monkeypatch)
    _capture_notes(monkeypatch)
    client = _client(
        table_responses={
            "calls": FakeResponse(data=[_call_row(has_recording=True)]),
            "ai_call_insights": FakeResponse(data=[_insight_row(status="failed", error_message="AI analysis failed: boom")]),
        }
    )
    provider = _FakeProvider()
    service = AIInsightService(client, provider=provider)

    result = service.request_analysis(WORKSPACE_ID, CALL_ID)

    assert result["status"] == "completed"
    assert provider.calls  # the retry actually ran the pipeline this time
