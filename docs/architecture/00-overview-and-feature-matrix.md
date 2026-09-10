# 00 — Overview, Principles & Feature Matrix

## 1. Product Summary

A production-grade, multi-tenant Sales CRM mobile application, functionally inspired by the field-sales workflow of Runo CRM (lead management, click-to-call, follow-ups, auto-dialer, allocations) but with **original branding, UI, database schema, business logic and source code**. No Runo source, assets, copy, or exact visual identity is used anywhere in this project.

- **Mobile**: Flutter (Android first, iOS-ready architecture)
- **Backend**: Python FastAPI (business logic, AI, integrations, background jobs)
- **Data platform**: Supabase (Postgres, Auth, RLS, Storage, Realtime, Edge Functions) — single source of truth shared by mobile and a future Admin web app
- **Calling**: Native Android bridge, not a Flutter-widget-coupled implementation

## 2. Governing Principles

1. **Security is enforced server-side.** RLS + API authorization are the real boundary; Flutter UI checks are UX only.
2. **One database.** Mobile and Admin never maintain separate copies of CRM data.
3. **No secrets in the client.** Supabase service-role key, AI provider keys, and third-party integration secrets live only in the Python backend's environment.
4. **Phased delivery.** Nothing is "done" until it's wired end-to-end (see Definition of Done, §9 of this doc) — no screen-only features.
5. **Multi-tenant by construction.** Every tenant-owned table carries `workspace_id`; cross-workspace access is impossible at the DB layer, not just hidden in UI.
6. **Offline-tolerant, not offline-first.** The app must degrade gracefully (cached reads, queued safe writes, reconnection) without silently losing CRM updates. Full offline-first sync is out of scope for v1.
7. **Calling is decoupled.** Native Android call handling is a service behind a stable channel contract, so Flutter (and future platforms) never depend on Android internals directly.
8. **Recording is best-effort, not load-bearing.** Call logging must never be blocked by recording being unsupported/denied/failed.

## 3. Feature Matrix

| Module | Mobile (Flutter) | Backend (Python) | Supabase Direct | Realtime | Phase |
|---|---|---|---|---|---|
| Auth (phone/email login, session, logout, permissions load) | ✅ | Session/permission assembly | Supabase Auth | — | 5 |
| App Shell (nav, theme, offline banner, notif badge) | ✅ | — | — | Presence | 6 |
| Leads (CRUD, search, filter, sort, tags, custom fields) | ✅ | Validation-heavy writes, bulk ops | Simple CRUD/reads | Lead changes | 7 |
| Customer 360 (timeline, docs, notes, history) | ✅ | Timeline aggregation | Reads | Lead/interaction changes | 8 |
| Calling (native bridge, state machine, logging) | ✅ (native) | Call event ingestion | Call writes | Call events (team) | 9 |
| Call Logs | ✅ | Aggregation/export | Reads | — | 10 |
| Follow-ups (create/reschedule/complete, reminders) | ✅ | Reminder scheduling (worker) | CRUD | Follow-up changes | 11 |
| Calendar (day/week/month) | ✅ | — | Reads | Event changes | 12 |
| Allocations (assign/reassign) | ✅ | Bulk allocation logic | CRUD | Allocation events | 13 |
| Notifications | ✅ | Orchestration, push dispatch | Reads/mark-read | Notification insert | 14 |
| Documents (upload/preview/delete) | ✅ | Signed URL issuance (sensitive) | Storage + simple CRUD | — | 15 |
| Messaging (WhatsApp deep link, templates) | ✅ | Template variable resolution | CRUD templates | — | 16 |
| Dashboard (KPIs, pipeline, quick actions) | ✅ | Heavy aggregation | Light reads | Dashboard-relevant tables | 18 |
| Reports (personal/team, date filters) | ✅ | Report computation | — | — | 19 |
| Auto Dialer (queue, state machine) | ✅ | Queue rules validation | Reads | Queue updates | 20 |
| Call Recording | ✅ (native) | Upload/transcription trigger | Storage | Status updates | 21 |
| Rechurn (inactive/lost re-engagement) | ✅ | Rechurn rule evaluation | CRUD | — | 22 |
| Team (presence, performance) | ✅ | Performance calc | Reads | Presence | 17 |
| AI (transcription, summary, scoring, assistant) | ✅ (consumer only) | Full AI orchestration | Storage of results | Status updates | 23 |

Legend: "Supabase Direct" = simple CRUD Flutter can call directly against Supabase (subject to RLS). "Backend (Python)" = must route through FastAPI because it's business-logic-heavy, sensitive, or requires an external/AI provider.

## 4. Definition of Done (per feature)

A feature is complete only when **all** of the following exist:
UI · state management (Riverpod) · repository layer · backend integration (Supabase and/or FastAPI) · error handling · loading state · empty state · permission handling · input validation · automated tests · logging where required · documentation of the change.

## 5. Non-Goals for v1

- iOS build (architecture must not block it, but no iOS release in v1)
- Full offline-first bi-directional sync
- WhatsApp Business API automation (v1 uses manual deep links only — must never be represented as Business API automation)
- SMS/Email integrations (placeholder architecture only)
- AI features (Phase 23, after core stabilizes)

## 6. Dependency List (indicative — pinned exactly at Phase 1/3/4)

**Flutter**: `flutter_riverpod`, `riverpod_annotation`, `go_router`, `freezed`, `json_serializable`, `dio`, `supabase_flutter`, `flutter_secure_storage`, `hive` or `drift` (local cache — decide in Phase 4), `firebase_messaging`, `permission_handler`, `connectivity_plus`.

**Python backend**: `fastapi`, `uvicorn`, `pydantic` v2, `supabase-py`, `python-jose` (JWT validation), `httpx`, `apscheduler` or a task queue (`celery`/`arq` — decide in Phase 3) for background jobs, `structlog`, `pytest`, `pytest-asyncio`.

**Android native**: Kotlin, `TelephonyManager`/`PhoneStateListener` (or `TelecomManager` for call state on newer APIs), Android `CallScreeningService` where applicable, MediaRecorder-based call recording (device-dependent, best-effort).

Final versions are pinned when each phase's foundation is actually created (Phase 3/4), not guessed here.

## 7. Environment Variable Plan (names only — values never committed)

**Flutter (`--dart-define` / secure config, no service-role key ever)**
- `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `API_BASE_URL`, `FCM_SENDER_ID`, `APP_ENV` (dev/staging/prod)

**Python backend (`.env`, never committed)**
- `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_JWT_SECRET`, `DATABASE_URL` (if direct PG access needed), `AI_PROVIDER_API_KEY`, `FCM_SERVER_KEY` / service account JSON path, `SENTRY_DSN`, `LOG_LEVEL`, `ENVIRONMENT`, `ALLOWED_ORIGINS`, `RATE_LIMIT_*`

**Supabase project**
- Managed via Supabase dashboard/CLI secrets for Edge Functions: any AI keys used *inside* Edge Functions, webhook signing secrets.

A concrete `.env.example` is created in Phase 3 (backend) and Phase 4 (Flutter), not before — no real secrets exist yet.
