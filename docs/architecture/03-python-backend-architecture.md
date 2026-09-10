# 03 — Python Backend Architecture (FastAPI)

## 1. Folder Structure

```
backend/
  app/
    api/                # routers, versioned (v1/)
      v1/
        leads.py
        calls.py
        followups.py
        allocations.py
        dashboard.py
        reports.py
        ai.py
        webhooks.py
    core/                # settings, security, logging, exceptions, middleware
    models/              # SQLAlchemy models (only if/where direct DB access is needed)
    schemas/             # Pydantic request/response DTOs
    services/            # business logic (one module per domain)
    repositories/        # data access abstraction (Supabase client / SQL)
    workers/             # background job definitions
    integrations/         # external API clients (FCM, AI provider, WhatsApp future)
    ai/                   # AI orchestration (transcription, summary, scoring)
    security/              # JWT validation, permission checks, rate limiting
  tests/
    unit/
    api/
    services/
    security/
```

## 2. Why Python Owns What

Python (not direct Supabase calls from Flutter) is required for:
- Anything needing a **secret** (AI provider keys, FCM server credentials, future WhatsApp Business API keys).
- **Cross-entity business logic** that must be atomic/consistent (e.g., allocate lead → write allocation → write interaction → send notification, as one transaction/orchestration).
- **Heavy computation** (dashboard aggregation, reports, analytics) that shouldn't run as ad-hoc client-side joins.
- **Background/scheduled work** (reminders, rechurn evaluation, cleanup).
- **AI orchestration** end-to-end.

Everything else (simple list/detail CRUD already covered by RLS) goes directly from Flutter to Supabase — no pointless proxy layer.

## 3. Service/Repository Separation

```
Router (FastAPI endpoint)
  -> Schema validation (Pydantic)
    -> Service (business rules, orchestration, permission checks)
      -> Repository (Supabase client calls / SQL)
        -> Supabase Postgres
```

Routers stay thin: validate input, call one service method, map result/errors to HTTP response. All business logic lives in `services/`, all data access in `repositories/` — services never call Supabase directly.

## 4. Auth on the Backend

- Every request carries the Supabase-issued JWT (`Authorization: Bearer <token>`).
- `security/` module verifies the JWT signature against the Supabase JWT secret, extracts `sub` (user id) and `workspace_id`/`role` claims (via a lookup or custom claim, decided in Phase 3/5).
- Backend then acts using the **service-role** key only for operations that legitimately need to bypass RLS (e.g., cross-workspace admin jobs) — everyday requests act as the authenticated user via a Supabase client configured with the user's JWT, so RLS still applies even through the backend.

## 5. API Design Rules

- Versioned under `/api/v1/`.
- Every endpoint: request DTO, response DTO, explicit status codes, structured error body (`{ "error_code": "...", "message": "..." }`).
- AuthN via JWT dependency; AuthZ via a `require_permission("lead.reassign")`-style dependency reading the caller's role/permission set.
- Rate limiting on write-heavy and auth-adjacent endpoints (e.g., login-adjacent, bulk allocation).
- All endpoints documented via FastAPI's OpenAPI (auto-generated) plus a short docstring describing business intent.

## 6. Background Jobs

Never run long jobs synchronously inside a request/response cycle. Candidates for background workers:
- Call recording upload → transcription → AI summary pipeline.
- Follow-up reminder scan (due-soon / overdue) → push notification dispatch.
- Rechurn candidate evaluation (nightly).
- Analytics/report pre-aggregation.
- Notification fan-out for bulk allocation events.

Mechanism (finalized Phase 3): APScheduler for simple cron-style jobs initially; revisit Celery/Redis or `arq` if job volume/retry needs grow. Supabase Edge Functions + `pg_cron` are considered for lightweight DB-adjacent jobs (e.g., marking follow-ups overdue) instead of round-tripping through the Python service.

## 7. Observability

- Structured logging (`structlog`) with request id, user id, workspace id on every log line.
- Errors reported to a tracking service (Sentry or equivalent — confirmed in Phase 3).
- Every state-changing endpoint logs an audit-relevant event (complementing DB-level `audit_logs` triggers, not duplicating them).

## 8. Testing

- Unit tests per service (business rules) with repositories mocked.
- API tests (FastAPI `TestClient`) covering auth failure, permission failure, validation failure, happy path per endpoint.
- Security tests: JWT tampering, cross-workspace access attempts (must be rejected even if RLS is somehow bypassed — defense in depth).
