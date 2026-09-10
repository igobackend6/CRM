import pytest

import app.services.calls.service as calls_service_module
import app.services.followups.service as followups_service_module
import app.services.leads.service as leads_service_module
from app.core.rate_limit import reset_rate_limit_state


@pytest.fixture(autouse=True)
def _reset_rate_limits():
    """Phase 21's RateLimitMiddleware keeps its counters in a single
    process-global dict (see core/rate_limit.py's own docstring on why
    that's a documented, deployment-layer limitation, not a test
    concern) — without this, hundreds of tests across the whole suite
    hitting the same rate-limited paths (most via TestClient with no
    real Authorization header, so they'd all share one IP-based bucket)
    would eventually start tripping 429s against each other. Every test
    gets a fresh window regardless of what ran before or after it."""
    reset_rate_limit_state()
    yield
    reset_rate_limit_state()


@pytest.fixture(autouse=True)
def _stub_notification_hooks(monkeypatch):
    """Phase 10 §2's notification hooks (lead assignment, follow-up
    assignment, call activity) call `notify()`, which uses the
    privileged service-role Supabase client
    (core/supabase_client.get_supabase_client) — and Settings loads
    real credentials from backend/.env (SettingsConfigDict(env_file=
    ".env")), the same ones the live, connected project uses. Without
    this, every unit/security test that exercises assign_lead/
    create_follow_up/update_follow_up/create_call (most of them, not
    just the notification-specific ones) would make a real network call
    against the live Supabase project as a side effect.

    Each of LeadService/FollowUpService/CallService's own modules did
    `from app.services.notifications import notify`, which bound its own
    independent reference to the function — patching
    `app.services.notifications.service.notify` alone would not reach
    those already-bound names, so this patches all three call sites
    directly. Defaults every test to a harmless no-op; tests that
    specifically assert on notification creation (test_lead_assignment_service.py,
    test_followup_service.py, test_call_service.py, test_notification_service.py)
    layer their own `monkeypatch.setattr(..., "notify", <capturing fn>)`
    on top of this within the same test, which pytest's monkeypatch
    correctly unwinds at teardown either way.
    """
    noop = lambda *args, **kwargs: None  # noqa: E731
    monkeypatch.setattr(leads_service_module, "notify", noop)
    monkeypatch.setattr(followups_service_module, "notify", noop)
    monkeypatch.setattr(calls_service_module, "notify", noop)
