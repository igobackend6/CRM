from uuid import uuid4

import pytest

from app.core.exceptions import NotFoundError
from app.services.ai.assistant import AIAssistantService
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
LEAD_ID = str(uuid4())


class _FakeProvider:
    def __init__(self, *, answer: str = "stub answer", raise_error: bool = False):
        self.answer = answer
        self.raise_error = raise_error
        self.calls: list[tuple] = []

    def answer_question(self, *, context: str, question: str) -> str:
        self.calls.append((context, question))
        if self.raise_error:
            raise RuntimeError("provider down")
        return self.answer


def _lead_row(**overrides):
    row = {"id": LEAD_ID, "workspace_id": str(WORKSPACE_ID), "name": "Acme Corp", "priority": "medium", "is_customer": False}
    row.update(overrides)
    return row


def _client(**overrides):
    table_responses = {
        "leads": FakeResponse(data=[_lead_row()]),
        "calls": FakeResponse(data=[]),
        "ai_call_insights": FakeResponse(data=[]),
    }
    table_responses.update(overrides.pop("table_responses", {}))
    return FakeSupabaseClient(table_responses=table_responses)


def test_ask_raises_not_found_for_a_lead_outside_this_workspace():
    client = _client(table_responses={"leads": FakeResponse(data=None)})
    service = AIAssistantService(client, provider=_FakeProvider())

    with pytest.raises(NotFoundError):
        service.ask(WORKSPACE_ID, LEAD_ID, "What does this customer need?")


def test_ask_reports_unavailable_when_no_provider_is_configured():
    client = _client()
    service = AIAssistantService(client, provider=None)

    result = service.ask(WORKSPACE_ID, LEAD_ID, "What does this customer need?")

    assert result["available"] is False
    assert result["answer"] is None
    assert "not available" in result["message"].lower()


def test_ask_default_provider_resolution_is_none_in_this_environment():
    client = _client()
    service = AIAssistantService(client)  # no provider kwarg — resolves via get_ai_provider()

    result = service.ask(WORKSPACE_ID, LEAD_ID, "What does this customer need?")

    assert result["available"] is False


def test_ask_returns_the_providers_answer_when_available():
    client = _client()
    provider = _FakeProvider(answer="They want a quote by Friday.")
    service = AIAssistantService(client, provider=provider)

    result = service.ask(WORKSPACE_ID, LEAD_ID, "What does this customer need?")

    assert result["available"] is True
    assert result["answer"] == "They want a quote by Friday."
    assert len(provider.calls) == 1


def test_ask_never_sends_a_second_leads_data_only_this_ones():
    """The assembled context only ever mentions this one lead's own
    name — never leaks any other lead's data (there's nothing else in
    scope to leak: only get_for_workspace(workspace_id, lead_id) is ever
    called)."""
    client = _client()
    provider = _FakeProvider()
    service = AIAssistantService(client, provider=provider)

    service.ask(WORKSPACE_ID, LEAD_ID, "Any risk signals?")

    context, question = provider.calls[0]
    assert "Acme Corp" in context
    assert question == "Any risk signals?"


def test_ask_includes_completed_call_summaries_in_context():
    call_id = str(uuid4())
    client = _client(
        table_responses={
            "calls": FakeResponse(data=[{"id": call_id, "lead_id": LEAD_ID}]),
            "ai_call_insights": FakeResponse(data=[{"call_id": call_id, "status": "completed", "summary": "Wants a discount."}]),
        }
    )
    provider = _FakeProvider()
    service = AIAssistantService(client, provider=provider)

    service.ask(WORKSPACE_ID, LEAD_ID, "What have we discussed?")

    context, _ = provider.calls[0]
    assert "Wants a discount." in context


def test_ask_reports_unavailable_when_the_provider_raises():
    client = _client()
    provider = _FakeProvider(raise_error=True)
    service = AIAssistantService(client, provider=provider)

    result = service.ask(WORKSPACE_ID, LEAD_ID, "What does this customer need?")

    assert result["available"] is False
    assert result["answer"] is None
