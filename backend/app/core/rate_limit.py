import time
from collections import defaultdict, deque

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

from app.core.logging import get_logger

logger = get_logger(__name__)

# Phase 21 §"Rate Limiting" — no rate limiting existed anywhere in this
# backend before this phase, and no rate-limiting library is installed
# (see requirements.txt). Rather than add an external dependency
# (slowapi, redis, ...) for a single-process CRM backend, this is a
# small, dependency-free, in-process fixed-window counter applied only
# to the sensitive/write-heavy/enumerable endpoints STEP 8 names —
# plain reads (dashboard, lead list, pipeline, ...) are left unlimited.
#
# KNOWN LIMITATION (see the Phase 21 completion report's own "Remaining
# security risks"): this state is a plain in-memory dict, correct only
# for a SINGLE backend process. Running multiple uvicorn/gunicorn
# workers or horizontally-scaled instances gives each its own counters,
# so the effective limit becomes (configured limit x worker count) —
# not a bypass of the concept, but a real gap at that scale. Production
# deployments beyond a single process should enforce these limits at
# the deployment layer instead (a shared Redis-backed limiter, or the
# reverse-proxy/API-gateway in front of the backend), which is exactly
# the "recommended deployment-layer control" this phase's own audit
# calls for when it can't safely add that infrastructure itself.
#
# Bucketed by the raw `Authorization` header value (never decoded/
# trusted here — this is abuse-rate bucketing, not an authorization
# decision; an unverifiable or forged token still lands in a real,
# still-enforced bucket) so two different users behind the same NAT/
# corporate IP don't throttle each other; falls back to the client IP
# for genuinely unauthenticated requests (e.g. a missing-token flood
# against a protected endpoint).

_RULES: list[tuple[str, str, int, int]] = [
    # (method, path suffix, max requests, window in seconds)
    ("GET", "/me", 60, 60),
    ("POST", "/leads/import", 5, 60),
    ("POST", "/leads/bulk", 10, 60),
    ("POST", "/leads", 30, 60),
    ("POST", "/calls", 60, 60),
    ("POST", "/follow-ups", 60, 60),
    ("POST", "/messages", 60, 60),
    ("POST", "/notifications/mark-all-read", 20, 60),
    ("POST", "/ai-insight", 10, 60),
    ("POST", "/ai-assistant", 10, 60),
]
# Longest suffix first, so e.g. "/leads/import" is matched before the
# more general "/leads" rule for the same path.
_RULES.sort(key=lambda r: len(r[1]), reverse=True)

_windows: dict[tuple[str, str], deque] = defaultdict(deque)


def reset_rate_limit_state() -> None:
    """Test-only: clears every in-memory counter between test cases so
    one test's requests never count against another's limit."""
    _windows.clear()


def _match_rule(method: str, path: str) -> tuple[str, str, int, int] | None:
    for rule in _RULES:
        rule_method, suffix, _limit, _window = rule
        if method == rule_method and path.endswith(suffix):
            return rule
    return None


def _bucket_key(request: Request) -> str:
    auth = request.headers.get("authorization")
    if auth:
        return auth
    client = request.client
    return client.host if client else "unknown"


class RateLimitMiddleware(BaseHTTPMiddleware):
    """Runs before routing/auth, so even an unauthenticated flood against
    a protected endpoint is throttled, not just successful requests."""

    async def dispatch(self, request: Request, call_next) -> Response:
        rule = _match_rule(request.method, request.url.path)
        if rule is not None:
            _, _, limit, window_seconds = rule
            key = (f"{rule[0]} {rule[1]}", _bucket_key(request))
            now = time.monotonic()
            window = _windows[key]
            while window and now - window[0] > window_seconds:
                window.popleft()
            if len(window) >= limit:
                logger.warning("Rate limit exceeded for %s %s", request.method, request.url.path)
                return JSONResponse(
                    status_code=429,
                    content={"error_code": "rate_limited", "message": "Too many requests. Please slow down and try again shortly."},
                )
            window.append(now)
        return await call_next(request)
