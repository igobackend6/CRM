"""Regression test for a real bug found during Phase 21A physical-device
verification: `get_user_scoped_client()` used to call only
`client.postgrest.auth(access_token)`, which mutates the postgrest
sub-client's own header copy and never touches `Client.options.headers`
— so `client.storage` (a separately lazy-initialized sub-client) kept
carrying only the anon key, with no user identity. Every
storage.objects RLS check (upload/signed-url/delete) then ran as
anonymous, failing with "new row violates row-level security policy"
even though the same request's has_permission()/current_member_id() RPC
calls (routed through .postgrest) succeeded. Requires real Supabase
credentials to construct a client at all, so this is gated the same way
as any other test that needs `SUPABASE_URL`/`SUPABASE_ANON_KEY` configured.
"""

import pytest

from app.core.config import get_settings
from app.core.supabase_client import get_user_scoped_client

_settings = get_settings()

pytestmark = pytest.mark.skipif(
    not _settings.supabase_url or not _settings.supabase_anon_key,
    reason="Requires real Supabase credentials (backend/.env) to construct a client.",
)


def test_the_storage_sub_client_carries_the_same_bearer_token_as_postgrest():
    client = get_user_scoped_client("fake-user-access-token")

    postgrest_auth = client.postgrest.headers.get("Authorization")
    storage_auth = client.storage._headers.get("Authorization")

    assert postgrest_auth == "Bearer fake-user-access-token"
    assert storage_auth == "Bearer fake-user-access-token"


def test_a_freshly_constructed_client_never_leaks_the_previous_token_into_a_new_ones_storage_client():
    """Not cached (see the function's own docstring) — a second call
    with a different token must produce an entirely independent client,
    not one sharing state with the first."""
    first = get_user_scoped_client("token-a")
    second = get_user_scoped_client("token-b")

    assert first.storage._headers.get("Authorization") == "Bearer token-a"
    assert second.storage._headers.get("Authorization") == "Bearer token-b"
