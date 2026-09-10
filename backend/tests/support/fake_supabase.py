"""A minimal stand-in for `supabase.Client`, shared by Phase 5's
repository/service/endpoint tests.

This is a mock/fake, not a real Postgres connection — it proves this
Python code builds the queries and RPC calls it's meant to, nothing
more. It is NOT a substitute for the still-outstanding real
Postgres/RLS validation documented in docs/architecture/database.md and
every phase report since Phase 2 (Docker unavailable in this
environment). Do not read a pass here as "database security verified."
"""

from typing import Any


class FakeResponse:
    def __init__(self, data: Any = None, count: int | None = None):
        self.data = data
        self.count = count


class _FakeQueryBuilder:
    """Every builder method (select/eq/is_/or_/order/range/limit/in_/
    maybe_single/insert/update/delete/...) returns this same object, so
    an arbitrary chain resolves to whatever `.execute()` was configured
    to return — real postgrest-py chains work the same way.

    One table is sometimes queried two different ways within the same
    service call (e.g. leads: a single-row `.maybe_single()` visibility
    check, then a list-returning `.update()`). To let one configured
    response serve both without per-call sequencing: if `.maybe_single()`
    was called and the configured `data` is a list, `.execute()` auto-
    unwraps it to its first element (or None if empty) — configure the
    list shape once, and each call site gets the shape it actually
    expects. A configured plain dict (not a list) always passes through
    unchanged, so existing maybe_single-only fixtures are unaffected.
    """

    def __init__(self, response: FakeResponse):
        self._response = response
        self._used_maybe_single = False

    def __getattr__(self, name: str):
        if name == "maybe_single":
            def _mark_maybe_single():
                self._used_maybe_single = True
                return self

            return _mark_maybe_single
        return lambda *args, **kwargs: self

    def execute(self) -> FakeResponse:
        data = self._response.data
        if self._used_maybe_single and isinstance(data, list):
            return FakeResponse(data=(data[0] if data else None), count=self._response.count)
        return self._response


class FakeSupabaseClient:
    """Configured per-table (`table_responses`) and per-RPC-name
    (`rpc_responses`). Records every `.table()`/`.rpc()` call so tests
    can assert on what was queried (e.g. workspace-scoping)."""

    def __init__(
        self,
        table_responses: dict[str, FakeResponse] | None = None,
        rpc_responses: dict[str, Any] | None = None,
    ):
        self._table_responses = table_responses or {}
        self._rpc_responses = rpc_responses or {}
        self.table_calls: list[str] = []
        self.rpc_calls: list[tuple[str, dict | None]] = []

    def table(self, name: str) -> _FakeQueryBuilder:
        self.table_calls.append(name)
        return _FakeQueryBuilder(self._table_responses.get(name, FakeResponse(data=[])))

    def rpc(self, name: str, params: dict | None = None) -> _FakeQueryBuilder:
        self.rpc_calls.append((name, params))
        value = self._rpc_responses.get(name, True)
        return _FakeQueryBuilder(FakeResponse(data=value))
