# Backend Security Implementation — Phase 3

How `docs/architecture/03-python-backend-architecture.md` §4 ("Auth on the Backend") and `05-security-and-permission-architecture.md` §3 (three-layer enforcement) were actually implemented. No CRM endpoints exist yet — this is the plumbing every later phase's endpoints will sit on top of.

## 1. Request Flow

```
Flutter: Authorization: Bearer <supabase-access-token>
  |
FastAPI: api/dependencies.get_current_user
  -> security/authentication.authenticate(token)
    -> security/jwt.verify_access_token(token)   # HS256, SUPABASE_JWT_SECRET, checks exp
  -> AuthenticatedUser(id, email, phone, access_token)
  |
(if the route needs a workspace-scoped action)
api/dependencies.get_user_client
  -> core/supabase_client.get_user_scoped_client(access_token)
     # anon-key client, .postgrest.auth(access_token) — RLS applies
  |
api/dependencies.require_permission(Permission.X) / require_workspace_member
  -> security/authorization.require_permission/require_workspace_member
     -> client.rpc("has_permission" / "is_workspace_member", {...})
        # the SAME Postgres functions RLS policies use — see
        # docs/architecture/rls.md §3. No permission logic is
        # reimplemented in Python.
  -> PermissionDeniedError (403) if the RPC returns false
```

## 2. Why the Backend Doesn't Re-Derive Permissions

`security/authorization.py` never queries `role_permissions`/`rep_permissions` itself — it calls the database's `has_permission()`/`is_workspace_member()` RPCs, the exact functions RLS policies call. Two reasons this matters, not just "less code":

1. **One decision, not two.** If Python re-implemented the override-beats-role-baseline logic, a bug or a missed edge case could make the API layer and the database layer disagree — e.g., the API approves a write that RLS then silently drops (empty result, confusing 404) or, worse, the API rejects something RLS would have allowed. Calling the same function eliminates that class of bug by construction.
2. **`docs/architecture/rls.md`'s `SECURITY DEFINER` reasoning still applies.** The RPC runs inside Postgres with the same recursion-safe, `search_path`-pinned functions already audited for Phase 2.

The API-layer check is still real defense-in-depth, not redundant: it returns a clean `403` with a stable `error_code` before any query runs, instead of letting a route's business logic discover "0 rows" and have to guess whether that means "not found" or "not permitted."

## 3. Two Supabase Clients, Deliberately

| Client | Key | Bypasses RLS? | Used for |
|---|---|---|---|
| `get_supabase_client()` | service-role | Yes | Genuinely system-level work only (background jobs, cross-workspace admin) — nothing in Phase 3 uses this yet |
| `get_user_scoped_client(token)` | anon key + user's access token | No | Everything done "as the current request's user" — the default for every future route |

The service-role key is read from `SUPABASE_SERVICE_ROLE_KEY` (backend `.env` only) and is never sent to, or reachable from, Flutter — enforced by construction: it's only ever referenced inside `core/supabase_client.py`, on the backend.

## 4. Error Shape

Every `AppError` subclass (`core/exceptions.py`) maps to `{"error_code": "...", "message": "..."}` via `core/errors.py`'s handlers, registered once in `main.py`. `RequestValidationError` (malformed request bodies) and any unhandled exception get the same shape, so Flutter's error handling never has to special-case "this one endpoint returns a different error format."

## 5. What's Still Missing (by design — later phases)

- No CRM endpoints (leads/calls/followups/...) — Phase 7+.
- No refresh-token handling — Supabase Flutter SDK manages refresh client-side; the backend only ever sees short-lived access tokens per request.
- No rate limiting — noted as a Phase 24 (Security hardening) task in `05-security-and-permission-architecture.md` §4, not implemented here.
- No JWKS/asymmetric-key JWT verification — `security/jwt.py`'s docstring notes this is a one-function change if the Supabase project is later switched off shared-secret HS256 signing.
