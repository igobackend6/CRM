from functools import lru_cache

from supabase import Client, create_client

from app.core.config import get_settings
from app.core.logging import get_logger

logger = get_logger(__name__)


@lru_cache
def get_supabase_client() -> Client | None:
    """Privileged Supabase client for the backend only — configured with
    the service-role key, which must never be sent to or reachable from
    Flutter. Bypasses RLS entirely, so use it only for genuinely
    system-level operations (background jobs, cross-workspace admin
    tasks) — never as a shortcut for "act on behalf of this request's
    user," which is what get_user_scoped_client() is for. Returns None
    (and logs a warning) if credentials aren't configured yet, rather
    than crashing app startup.
    """
    settings = get_settings()
    if not settings.supabase_url or not settings.supabase_service_role_key:
        logger.warning("Supabase credentials not configured; service-role client not initialized.")
        return None
    return create_client(settings.supabase_url, settings.supabase_service_role_key)


def get_user_scoped_client(access_token: str) -> Client:
    """Per-request Supabase client authenticated as the calling user
    (their own access token, not the service-role key), so every query
    made through it is still subject to RLS exactly as if Flutter had
    called Supabase directly — see docs/architecture/03-python-backend-architecture.md
    §4. This is the client every route/service should use for anything
    done "as the current user," including authorization.py's
    has_permission() RPC calls. Not cached: the token is per-request and
    expires, so a cached client would eventually hold a stale token.

    `client.postgrest.auth(access_token)` alone is NOT enough: supabase-py's
    `Client.postgrest`/`Client.storage` are two independent, separately
    lazy-initialized sub-clients, and `.postgrest.auth()` only ever
    mutates the postgrest sub-client's own header copy — it never
    touches `Client.options.headers`, so `.storage` (accessed later, by
    DocumentStorage) would still only carry the anon key and no user
    identity, making every storage.objects RLS check run as anonymous
    (discovered via a real 403 "new row violates row-level security
    policy" during Phase 21A device verification, even though the same
    request's own has_permission()/current_member_id() RPC calls, going
    through .postgrest, succeeded correctly). Setting the header on
    `client.options.headers` before either sub-client is first touched
    ensures both inherit the same identity.
    """
    settings = get_settings()
    if not settings.supabase_url or not settings.supabase_anon_key:
        raise RuntimeError("SUPABASE_URL and SUPABASE_ANON_KEY must be configured.")

    client = create_client(settings.supabase_url, settings.supabase_anon_key)
    client.options.headers["Authorization"] = f"Bearer {access_token}"
    client.postgrest.auth(access_token)
    return client
