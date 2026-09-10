from abc import ABC, abstractmethod

from app.core.config import get_settings


class AIProvider(ABC):
    """Small, provider-agnostic interface every stage of the Phase 20
    pipeline (see AIInsightService/AIAssistantService) is written
    against — see docs/architecture/07-ai-architecture.md for the
    target shape this deliberately stays compatible with. Swapping or
    adding a real provider later means adding one new implementation of
    this class, never touching the services/routes/schemas that call
    it. All methods are synchronous and provider-call-shaped (one
    transcript/text in, one small result out) — no provider SDK types
    leak past this boundary.
    """

    @abstractmethod
    def transcribe(self, *, audio_ref: str) -> str:
        """`audio_ref` is whatever locator the (future) recording
        infrastructure produces — a Storage path/URL, never raw audio
        bytes passed through this layer."""

    @abstractmethod
    def summarize(self, *, transcript: str) -> str: ...

    @abstractmethod
    def analyze_sentiment(self, *, transcript: str) -> str:
        """Returns one of 'positive' | 'neutral' | 'negative' — matches
        `ai_call_insights.sentiment`'s own CHECK constraint."""

    @abstractmethod
    def extract_action_items(self, *, transcript: str) -> list[str]: ...

    @abstractmethod
    def score_call(self, *, transcript: str) -> int:
        """0-100 — matches `ai_call_insights.call_score`'s own CHECK
        constraint."""

    @abstractmethod
    def answer_question(self, *, context: str, question: str) -> str:
        """The AI assistant's one operation (Phase 20 §"AI Assistant"):
        a bounded, already-authorized `context` (assembled by
        AIAssistantService from CRM data the caller can already see)
        plus a free-text `question`, returning a free-text answer. Never
        given raw database access or a way to request more data itself
        — the context passed in is the *entire* universe of CRM data
        this call can see."""


def get_ai_provider() -> AIProvider | None:
    """Returns the configured provider, or `None` if Phase 20's
    prerequisites aren't met (§"Do not add an AI provider unless the
    repository already has one configured and usable. Do not invent API
    keys or credentials."). Every caller (AIInsightService,
    AIAssistantService) MUST treat `None` as "unavailable" and report
    that plainly — never substitute a fabricated result.

    No concrete provider is registered in this codebase yet: as of
    Phase 20, `ai_provider`/`ai_provider_api_key` are unset in every
    environment (see config.py's own comment and the Phase 20
    completion report's dependency note), so this always returns
    `None` today. A future phase wires a real implementation in here,
    selected by `settings.ai_provider` — this function is the one and
    only place that changes.
    """
    settings = get_settings()
    if not settings.ai_provider or not settings.ai_provider_api_key:
        return None
    # Deliberately still returns None: no concrete AIProvider
    # implementation exists in this repository (see docstring above).
    # Wiring `settings.ai_provider == "openai"` (etc.) to a real class
    # is the smallest possible follow-up once a provider is actually
    # configured — not invented speculatively here.
    return None
