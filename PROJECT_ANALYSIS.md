# Sales CRM — Project Analysis

_Snapshot as of 2026-09-30 (branch `main`, HEAD `45ce3c9`, plus a large uncommitted working tree)._
_This is the working reference for the project. Where it disagrees with an older doc in `docs/`, this file reflects the actual code. See §9 for the doc audit._

---

## 1. What this is

A multi-tenant **Sales CRM** for field and inside sales teams. Its workflow is inspired by Runo CRM: leads, click-to-call, follow-ups, allocations and a dialer. The branding, schema and code are all original.

| Layer | Tech | Location |
|---|---|---|
| Mobile app | Flutter / Dart 3.12, Riverpod (StateNotifier), GoRouter 18, Dio, supabase_flutter. Targets Android first. | `mobile/` |
| Backend API | Python 3.10 with FastAPI, pydantic v2, supabase-py, PyJWT and APScheduler | `backend/` |
| Data platform | Supabase: Postgres 17, Auth, RLS, Storage, Realtime | `supabase/` |
| Admin web panel | React + Vite, built by a **co-developer in a separate repo** on the **same Supabase DB** | not in this repo |

```text
Flutter app ──(anon key + user JWT)──► Supabase (Auth, some direct reads: profiles, workspace_members)
     │
     └──(Bearer user JWT)──► FastAPI /api/v1 ──(user-scoped anon client → RLS applies)──► Postgres
                                   └──(service-role client, only for notify() + push)──► Postgres
React admin panel (co-dev) ──────────────────────────────────────────────────────────► same Postgres
```

### Governing rules (from the master plan; treat as non-negotiable)
- **Security is enforced in the database.** RLS and `has_permission()` are the real boundary. Flutter role checks are UX only.
- **Multi-tenant by construction.** Every tenant table has `workspace_id`, and FKs are composite `(workspace_id, x_id)`.
- **No secrets in Flutter.** The service-role key, AI keys and FCM credentials live only in `backend/.env`. `tests/security/test_no_secrets_in_flutter.py` checks this.
- **One database.** The mobile app and the admin panel share one canonical schema.
- **Definition of Done.** A feature needs UI + state + repository + backend + error/loading/empty states + permissions + validation + tests + docs. A screen on its own is not done.
- **No destructive changes without approval.** No fake data in production paths. Don't duplicate backend logic. Don't touch unrelated features.
- **Inspect before building.** Before each phase, check the existing structure, schema and RLS policies, then define the data contract and UI/error states.

---

## 2. Repository layout

```text
E:\CRM
├── backend/            FastAPI app, tests, scripts/validate_rls.py, requirements.txt
├── mobile/             Flutter app (lib/, test/, android/, env/, assets/)
├── supabase/           config.toml, migrations/000001–000032, seed.sql (empty), tests/rls_security_tests.sql
├── docs/               architecture/, setup/, design/, dependencies.md
├── scripts/            dev-device.ps1 (adb reverse + auto-start uvicorn)  [untracked]
├── .kilo/worktrees/daffy-warlock   stale git worktree (detached at initial commit 5addee6) — ignore
├── mobile_screen.png   stray screenshot [untracked]
└── .gitignore          ignores .env*, mobile/env/.env.{development,staging,production}, *.log, .claude/
```

Clutter that could be cleaned up: `mobile/flutter_run*.log` (about 13 files) and `backend/uvicorn*.log`. All of these are gitignored.

---

## 3. Backend (`backend/`)

### Structure
- `app/main.py` creates `app` at module level (there is no factory). It sets up logging, and the lifespan starts and stops the APScheduler. Middleware order is exception handlers → `RateLimitMiddleware` → v1 router at `/api/v1` → `/internal` router. `GET /health` is the health check. `/docs` is disabled in production.
- `app/core/`:
  - `config.py`: pydantic-settings loaded from `.env`
  - `supabase_client.py`
  - `errors.py` / `exceptions.py`: the `AppError` hierarchy, mapped to 401/403/404/409/422
  - `logging.py`
  - `rate_limit.py`: in-memory and per-process
  - `date_ranges.py`
  - `timeparse.py`
- `app/security/`:
  - `jwt.py` picks the algorithm from the token's `alg` header. ES256/RS256 are verified against the project JWKS; HS256 uses `SUPABASE_JWT_SECRET`.
  - `authentication.py`
  - `authorization.py` calls the DB RPCs `is_workspace_member` and `has_permission`.
  - `permissions.py` holds the enum that mirrors migration 000013.
- `app/api/dependencies.py`: `get_current_user`, `get_user_client`, `require_workspace_member`, `require_permission(P)`.
- `app/api/v1/*.py`: one router per domain, aggregated in `router.py`.
- `app/services/<domain>/`: business logic. `services/analytics/` is an empty placeholder.
- `app/repositories/*.py`: built on `BaseRepository`, with PostgREST errors mapped to `AppError`s.
- `app/schemas/*.py`: Pydantic in/out models.
- `app/integrations/storage.py`: `DocumentStorage` for the `lead-documents` bucket.
- `app/workers/scheduler.py`: APScheduler is started, but **no jobs are registered**.

### Supabase client usage
- **Per request:** `get_user_scoped_client(token)` is the anon key plus the user's JWT, so RLS and Storage RLS apply to everything the user does.
- **Service role:** `get_supabase_client()` is used **only** by `notifications.notify()` (notifications has no authenticated INSERT policy) and `push.push_to_member()`.

### Env vars (names only)
`ENVIRONMENT`, `LOG_LEVEL`, `API_V1_PREFIX`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY`, `SUPABASE_JWT_SECRET`, `AI_PROVIDER`, `AI_PROVIDER_API_KEY`, `FCM_PROJECT_ID`, `FCM_SERVICE_ACCOUNT_JSON`, `INTERNAL_WEBHOOK_SECRET`

### Endpoints
Everything is under `/api/v1/workspaces/{workspace_id}` unless noted. "member" means the route only requires workspace membership.

| Router | Endpoints (permission) |
|---|---|
| auth | `GET /api/v1/me` (valid JWT only) |
| leads | `GET/POST /leads`, `GET/PATCH/DELETE /leads/{id}` (LEADS_READ/CREATE/UPDATE/DELETE), `PATCH /leads/{id}/status`, `POST /leads/{id}/convert`, `POST /leads/bulk` (per-action permission), `POST /leads/import` (CSV), `GET /pipeline`, `GET /leads/{id}/interactions`, `/activity`, `/follow-ups`, `/calls`, `/allocations`, `POST /leads/{id}/notes`, `POST /leads/{id}/assignment` (LEADS_ASSIGN), tags CRUD on leads, `GET /members`, `/lead-statuses`, `/lead-sources`, `/tags` (member) |
| followups | `GET/POST /follow-ups`, `GET/PATCH /follow-ups/{id}` |
| customers | `GET /customers/{id}`, `/timeline`, `/documents`, `/follow-ups`, `POST /notes` (a customer is a lead with `is_customer=true`) |
| calls | `GET/POST /calls`, `GET /calls/{id}`, `GET /call-outcomes` |
| notifications | list, get, `PATCH /{id}` (mark read), `POST /mark-all-read` |
| dashboard | `GET /dashboard/summary`, `/dashboard/recent-activity` |
| messages | `GET /conversations`, `GET /leads/{id}/conversation`, `GET/POST /conversations/{id}/messages`, `POST /conversations/{id}/read` (internal team chat per lead) |
| rechurn | `GET /rechurn` |
| ai_insights | `GET/POST /calls/{id}/ai-insight`, `GET /leads/{id}/ai-insights`, `POST /leads/{id}/ai-assistant` |
| documents | `GET/POST /leads/{id}/documents`, `GET …/{doc}/signed-url`, `DELETE …/{doc}` |
| message_templates | `GET` (member); `POST`, `PATCH`, `DELETE` (TEMPLATES_MANAGE) |
| custom_fields | `GET` (member); `POST`, `PATCH`, `DELETE` (WORKSPACE_MANAGE) |
| reports | `GET /reports/personal` (member), `/reports/call-trends` (member, **new**), `/reports/team`, `/reports/pipeline` (REPORTS_READ) |
| device_tokens | `PUT /api/v1/device-tokens`, `DELETE /api/v1/device-tokens/{token}` (not workspace-scoped) |
| activity (**new, untracked**) | `POST /activity/heartbeat`, `/sign-out`, `/break/start`, `/break/end`; `GET /activity/summary`, `/activity/daily` |
| internal | `POST /internal/push/notification`, the target of a Supabase DB webhook on notifications INSERT. It is guarded by the `X-Webhook-Secret` header. |

These permissions exist in the enum but no route uses them: `members.*`, `allocations.*`, `audit.read`. Member management and audit are handled by the admin panel.

### Integrations
- **Push (FCM HTTP v1)** is built but dormant. `get_fcm_sender()` returns `None` when `FCM_*` is unset. Enabling it is covered in `docs/setup/push-notifications.md`.
- **AI:** the `AIProvider` interface exists, but `get_ai_provider()` **always returns `None`** because there is no concrete provider. The insight service degrades gracefully.
- **Recordings:** the `call_recordings` table and bucket exist, but the backend has no pipeline for them.
- **Login Analytics** (`services/activity/`): heartbeats and sessions (3-minute timeout), breaks, and a daily rollup that refreshes at most every 5 minutes. Time is classified with the priority call > break > wrap-up (2 minutes after a call) > idle.

### Tests
- Test files:
  - `tests/unit`: about 540 tests
  - `tests/security`: about 345 tests
  - `tests/integration`: 7 tests
  - That is roughly 890 in total.
- Mocking uses `tests/support/fake_supabase.py`.
- Run them from `backend/` with `python -m pytest`.
- `scripts/validate_rls.py` is a **live** RLS check against a real Supabase project. It creates users, verifies them, then cleans up.

### Backend gaps and risks
- `requirements.txt` has **no version pins** and no lockfile, and pytest/httpx are listed as runtime dependencies. `docs/dependencies.md` records the versions that were actually installed.
- There is no CORS middleware, and the rate limiter only works correctly with a single process.
- The internal webhook secret is compared with `!=`; it should use `hmac.compare_digest`. The payload is an untyped `dict`.
- No scheduler jobs exist, so follow-up reminders and overdue notifications are **not implemented**.
- Custom-field option normalization happens on read only. The admin panel saves options as plain strings.

---

## 4. Mobile (`mobile/`)

### Config
- The flavor comes from `--dart-define=FLAVOR=development|staging|production` (default `development`). It loads `env/.env.<flavor>` through flutter_dotenv.
- Required keys are `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `API_BASE_URL`. There are no Gradle flavors.
- Startup: `GlobalErrorHandler.install()` → `AppConfig.load` → `SupabaseService.initialize()` → `ProviderScope(MyApp)`. The app is wrapped in `CallOutcomeListener`.
- **No codegen.** Despite what the early docs say, the project does not use freezed, json_serializable or build_runner.
- Android `applicationId` is `com.crmapp.mobile` and `compileSdk` is 37. `MainActivity.kt` is an empty `FlutterActivity`.
- **There is no MethodChannel or native telephony.**

### Structure (`lib/`, about 325 hand-written files)
- `core/`:
  - `config/`
  - `constants/` (`defaultPhoneCountryCode='91'`)
  - `errors/` (sealed `AppException`)
  - `logging/`
  - `realtime/`: a single channel `workspace:<id>`, plus `realtime_refresh_mixin` for list controllers
  - `router/`: `app_router.dart`, `route_paths.dart`, and `route_guard.dart` containing the pure `resolveRedirect`
  - `theme/`: tokens copied from the admin panel CSS, primary `#1D4ED8`
  - `utils/`
  - `widgets/`: shared UI plus a `widgets.dart` barrel
- `services/`:
  - `api/api_client.dart`: static Dio with a per-request Bearer token
  - `api_error_mapper.dart`
  - one `*_api_data_source.dart` per domain
  - `supabase/`, `storage/`: secure storage
- `features/<name>/{data,domain,presentation}`. Almost everything goes **through FastAPI**. The exceptions are Supabase Auth, the `profiles` read and the `workspace_members` read, which go directly to Supabase.

| Feature | Notes |
|---|---|
| auth | Phone + password login (+91 prefix), with a forced first-login password change driven by `user_metadata.must_change_password`. `/api/v1/me` is called as a backend check. Uncommitted: a robot-mascot login redesign and an email toggle added back. |
| workspace | Workspace selection. It auto-selects when the user has exactly one, and remembers the choice in secure storage. |
| app_shell | Bottom nav with **Home / Allocations / Customers / Menu**, plus a center call FAB that opens `/app/dialer`. |
| dashboard | Summary and recent activity, with date-range chips |
| leads | List (modes: allocations or customers), detail, form, CSV import, saved views, tags, bulk actions, contact actions (call, WhatsApp) |
| pipeline | Kanban board by status |
| followups | List, detail and form. They are created from a lead (`?leadId=`). |
| customer360 | Customer detail plus a unified timeline; customers overview |
| calls | Manually logged call history (list, detail, form) |
| call_outcome (**new**) | After a `tel:` or WhatsApp handoff, a dialog pops up when the user returns to the app and PATCHes the lead's status and custom fields |
| dialer | Full-screen keypad that hands off to `tel:`, plus a "create customer" shortcut |
| documents | Section inside lead/customer screens: upload, list, signed URLs |
| notifications, messaging, rechurn, whatsapp (templates + `wa.me` deep links), custom_fields (dynamic form fields), ai (insight sections) | — |
| reports | Personal / Team / Pipeline. Team and Pipeline are UI-gated to manager and above. |
| analytics (**new**) | Hub with Call, Customer and User analytics. Includes bar charts, CSV and a conversion-funnel **PDF** export (`pdf` package). |
| activity (**new**) | Login Analytics: a heartbeat every minute, break toggle, sign-out event |
| push | `PushRegistrar` wired to **`NoopFcmTokenSource`**. There is no Firebase dependency yet. |

### Routes
- Entry and auth: `/splash`, `/login`, `/change-password`, `/workspace`.
- Shell branches: `/app` (Home), `/app/leads` (with its children), `/app/customers`, `/app/menu`.
- Full-screen routes:
  - `/app/dialer`, `/app/pipeline`
  - `/app/follow-ups*`, `/app/calls*`
  - `/app/notifications`, `/app/messages*`
  - `/app/rechurn`, `/app/message-templates`, `/app/reports`
  - `/app/analytics`, `/app/analytics/{calls,customers,users}`

### Tests
119 `*_test.dart` files under `test/`, mirroring `lib/`. They use fake repositories and data sources. Run them with `flutter test` and `flutter analyze`.

### Mobile gaps and risks
- The main `AndroidManifest.xml` has **no `INTERNET` permission**, which release builds need. It only has location permissions and DIAL/https queries.
- There is no native call-log sync, recording or CALL_PHONE. Auto-dialer and recording are not built on the device side.
- There is no lead picker for creating a follow-up or call, so both must be started from a lead.
- The login direction is unresolved: the committed code is phone-only, while the uncommitted code adds an email toggle back.
- `assets/specs/` (login animation spec) is not declared in pubspec. The `mime` dependency looks unused.
- `mobile/README.md` is still the Flutter template text.

---

## 5. Database (`supabase/`)

### Migration timeline
| # | Summary |
|---|---|
| 001–002 | Extensions (pgcrypto, uuid-ossp); `set_updated_at()` |
| 003–006 | `workspaces`, `profiles` (+ `handle_new_user` trigger on auth.users), `roles`/`permissions`/`role_permissions`, `workspace_members`, `rep_permissions` (per-member overrides) |
| 007–011 | `lead_statuses`, `lead_sources`, `call_outcomes`, `tags`, `leads` (soft delete, trigram name index), `lead_tags`, `lead_documents`, `calls` (state machine, generated `duration_seconds`), `follow_ups`, `allocations`, `interactions` (append-only), `notifications`, `audit_logs` |
| 012 | Security helpers, `create_workspace()` RPC, `provision_default_workspace_data()` trigger (6 statuses, 5 sources, 7 outcomes), audit triggers |
| 013 | Seeds 4 roles and permissions |
| 014 | Grants to `authenticated` and all RLS policies (nothing granted to anon) |
| 015–016 | Private `lead-documents` bucket; realtime publication |
| 017 | Trigger enforcing `leads.assign` on reassignment |
| 018 | `audit_logs` actor FK fix |
| 019 | `conversations` / `messages` (internal chat) |
| 020 | `ai_call_insights` |
| 021 | RLS actor-identity hardening: actor columns must equal `current_member_id()` |
| 022 | `message_templates` plus the `templates.manage` permission |
| 023 | `messages` added to realtime |
| 024 | `report_call_duration_stats()` (SECURITY INVOKER) |
| 025 | `custom_fields` / `custom_field_values` (types `text`, `number`, `date`, `options`, `multi_options`) |
| 026 | `lead_statuses.stage` (`start`, `in_progress`, `closed_won`, `closed_lost`) **replaces `is_won`/`is_lost`** |
| 027 | `on_lead_assignment` trigger (INSERT or UPDATE of assignee): writes an `allocations` row and a notification. Edited in place in 5bc2321. |
| 028 | `call_recordings` plus private `call-recordings` bucket |
| 029 | `service_role` grants plus default privileges; fixes the `ai_call_insights` grant |
| 030 | `device_tokens` (profile-scoped) |
| 031 (**untracked in git; live**) | `agent_sessions`, `agent_breaks`, `agent_daily_activity` (Login Analytics) |
| 032 (**untracked in git; live**) | Surrogate `id` PK on `agent_daily_activity` (fixes PGRST201) |

### Data model (32 tables)
- **Tenancy:** `workspaces`, `profiles` (global), `workspace_members` (role, status).
- **RBAC:** `roles`, `permissions`, `role_permissions`, `rep_permissions`.
- **Leads:** `lead_statuses`, `lead_sources`, `call_outcomes`, `tags`, `leads`, `lead_tags`, `lead_documents`.
- **Calls:** `calls`, `call_recordings`, `ai_call_insights`.
- **Work:** `follow_ups`, `allocations`, `interactions`.
- **Messaging:** `conversations`, `messages`, `message_templates`.
- **Ops:** `notifications`, `audit_logs`, `device_tokens`.
- **Custom fields:** `custom_fields`, `custom_field_values`.
- **Activity:** `agent_sessions`, `agent_breaks`, `agent_daily_activity`.

A **customer is a `leads` row with `is_customer=true`**; there is no customers table. Notes are stored as `interactions` with `type='note'`.

### Security functions
All are SECURITY DEFINER with a pinned search_path: `is_workspace_member(ws)`, `current_member_id(ws)`, `get_member_role(ws)`, `is_manager_or_above(ws)`, `has_permission(ws, code)` (a `rep_permissions` override beats the role baseline), and `shares_workspace_with(profile)`.

### Roles and permissions
The roles are `team_mate`, `manager`, `admin` and `ceo`; `ceo` has the same grants as `admin`. There are 24 permission codes:
- `workspace.manage`
- `members.invite`, `members.manage`, `members.remove`
- `leads.read`, `leads.create`, `leads.update`, `leads.delete`, `leads.assign`
- `calls.read`, `calls.create`, `calls.update`
- `followups.read`, `followups.create`, `followups.update`
- `allocations.read`, `allocations.manage`
- `documents.read`, `documents.upload`, `documents.delete`
- `notifications.read`, `reports.read`, `audit.read`, `templates.manage`

Each role adds to the previous one:
- **team_mate** gets lead, call and follow-up read/create/update, plus document read/upload.
- **manager** adds lead delete and assign, allocations, document delete and reports.
- **admin** adds workspace management, member management and audit.

### Storage and realtime
- **Buckets** (both private, path `{workspace_id}/{entity_id}/{file}`): `lead-documents` and `call-recordings`.
- **Realtime publication:** `leads`, `follow_ups`, `notifications`, `allocations`, `messages`.

### Database gaps and risks
- `supabase/tests/rls_security_tests.sql` only covers migrations up to 000017. **Nothing from 019–032 is RLS-tested**, and per `docs/setup/database.md` the suite has never been run against real Postgres.
- Storage SELECT policies only check workspace membership, which is broader than the table RLS. For example, a rep can read any recording in the workspace if they know its path.
- `calls` has a duplicate unique `(workspace_id, id)` constraint, added in both 020 and 028.
- `custom_field_values` has no audit trigger, even though the 025 comment claims its history is kept in audit_logs.

---

## 6. Live environment and operational context

- There is **one shared Supabase project** (ref `knwvxgvawrxtynkfahhs`), used by both this app and the co-developer's React admin panel.
- **Incident, 2026-09-10:** the co-developer's rebuild script dropped our tables. On 2026-09-11 the DB was reset (`drop schema public cascade`) and migrations 000001–000030 were re-applied cleanly. One workspace was created ("Igo Sales CRM").
- **Migrations 000031 and 000032 are live** (verified 2026-09-30: all three `agent_*` tables exist with rows, `agent_daily_activity.id` exists, and the `workspace_members → workspaces` embed works with no PGRST201). The DB is at 000032. They are still untracked in git.
  - Future migrations need the Supabase SQL editor or a direct DB connection with the DB password, which is not in `backend/.env`. The Supabase MCP connector in this environment is bound to an unrelated project, so **never use MCP `apply_migration` for this project**.
- Credentials live only in `backend/.env` and `mobile/env/.env.development` (both gitignored).
- **Local dev loop:** run `scripts/dev-device.ps1`. It checks for an adb device, runs `adb reverse tcp:8000 tcp:8000`, and starts `uvicorn app.main:app` on 127.0.0.1:8000 if it isn't already running. Then run `flutter run --dart-define=FLAVOR=development`.
- **Ownership split** (from the implementation plan): we own the canonical schema (Phase 0), app alignment (Phase 4) and call recording (Phase 5). The co-developer owns the admin panel rewrite (Phases 1–3).
  - Admin-only actions such as deletes, member management, and workspace and custom-field configuration are moving to the web panel. The app is removing its delete actions to match, and `test/features/no_delete_actions_test.dart` enforces this.

---

## 7. Current uncommitted work (about 129 changed or new paths)

1. **Login Analytics.** Backend `activity` router, service, repository and schemas; migrations 031/032; mobile `features/activity`; §19 in `docs/architecture/database.md`.
2. **Call Analytics.** `GET /reports/call-trends` (hour/day buckets from the client's local midnight, zero-filled, capped at 800 buckets), plus the mobile `features/analytics` hub with a PDF funnel export.
3. **Custom-field fix.** Admin-panel string options are normalized to `{code, label, sort_order}` on read. Before this, `GET /custom-fields` returned a 500 and broke the lead form.
4. **Brand chrome.** `BrandAppBar` (gradient) is used across screens, and the bottom nav is now brand blue.
5. **Login redesign** with the robot mascot and a Phone/Email toggle, plus a token refresh on cold start.
6. **Allocations / Customers split** in `LeadListScreen` (date-range chips, shown/total badge). `canEditLead` restricts editing to leads you created.
7. **Call outcome pop-up** after call or WhatsApp handoffs.
8. **Delete actions removed** from the app (leads, documents, templates).
9. **Manifest:** a DIAL `tel:` query, and the app label changed to "Sales CRM".

None of this is committed yet. It should probably be split into several focused commits.

---

## 8. Known gaps and backlog (consolidated)

| Area | Gap |
|---|---|
| Deploy | Commit migrations 031/032 (already live) and share the `agent_daily_activity` contract with the co-developer |
| Android | Add the `INTERNET` permission to the main manifest before any release build |
| Calling | No native bridge. Auto-dialer, call-log sync and device-side recording upload are not built. |
| Push | Needs a Firebase project, `google-services.json` and a real `FcmTokenSource`; `FCM_*` must be set in the backend. See `docs/setup/push-notifications.md`. |
| Reminders | No scheduler jobs, so follow-up reminders and overdue notifications don't exist. Where they should run (pg_cron or FastAPI) is still an open decision. |
| AI | No concrete `AIProvider`, and no recording-to-transcription pipeline |
| Calendar / Team presence | Not built (they were in the original plan) |
| RLS tests | Extend `rls_security_tests.sql` to cover 019–032 and actually run it |
| Hardening | Pin requirements, add CORS, use a constant-time webhook secret compare, and a shared rate-limit store |
| Product | Decide the login method (phone-only or phone+email). Decide the fate of the admin-only screens still in the app (Settings/Calling). |
| Docs | Refresh the stale docs listed in §9 |

---

## 9. Existing documentation audit

| File | Status |
|---|---|
| `docs/architecture/README.md` | **Stale.** It is a "Phase 1 snapshot" that says no CRM tables exist. Still useful as an index. |
| `00-overview-and-feature-matrix.md` | Principles, Definition of Done and feature matrix are still valid. The phase numbers and "AI is a non-goal" are outdated. |
| `01-database-erd.md` | **Superseded** by `database.md`. It plans tables that were never built (notes, calendar_events, campaigns, agent_presence…). |
| `02-flutter-architecture.md` | The layering intent is valid. It mentions freezed/codegen, Hive/Drift and MethodChannels, none of which exist. |
| `03-python-backend-architecture.md` | Mostly valid. It uses old permission names such as `lead.reassign`. |
| `04-supabase-architecture.md` | **Stale.** It describes `profiles.workspace_id`, `current_workspace_id()` and an avatars bucket, none of which match the real schema. |
| `05-security-and-permission-architecture.md` | The threat model is valid; the permission codes are old (`lead.create` and similar). |
| `06-calling-architecture.md` | This is the **design target** for native calling, which is not built. The state machine matches `calls.state`. |
| `07-ai-architecture.md` | Design target. It says AI arrives in Phase 23, but `ai_call_insights` already exists. |
| `08-testing-strategy.md` | Valid as a goal; only partly met for DB RLS tests. |
| `09-phases-deployment-and-risk-register.md` | The 0–26 phase plan. The phases actually delivered were renumbered (see the memory and master plan). |
| `10-backend-security-implementation.md` | Accurate apart from "no CRM endpoints yet" and the HS256-only claim (ES256/JWKS was added later). |
| `database.md` | **The canonical schema doc** (§18 covers 025–028, §19 covers 031/032 and is uncommitted). The table count, the `is_won`/`is_lost` mentions and the "deferred" notes are stale. Migrations 019–024, 029 and 030 have no sections. |
| `database-erd.md` | Covers only the 20 Phase 2 tables. |
| `rbac.md` | Accurate, but it says 23 permissions and is missing `templates.manage`. |
| `rls.md` | Covers policies from 000014 only (plus a 029 note). It is missing 019–031 and the `call-recordings` bucket. |
| `setup/README.md` | Toolchain versions (Flutter 3.44, Dart 3.12, Python 3.10.11, Supabase CLI 2.106, Android SDK 36.1) are valid. "Migrations empty" is stale. |
| `setup/database.md` | The migration table stops at 016. |
| `setup/push-notifications.md` | Current and accurate. |
| `design/design-tokens.md` | Current: the palette is copied from the admin panel (primary `#1D4ED8`, gold `#C6960C`). |
| `design/login-animation-spec.json` | Untracked. It is the admin web login spec, reused for the mobile mascot. |
| `dependencies.md` | Partly stale: it is missing `google-auth`, `pdf`, `geolocator` and other later additions. |
| `mobile/README.md` | Flutter template text only. |
| `.kilo/worktrees/daffy-warlock/**` | A copy of the docs from the initial commit, 12 commits behind. **Ignore it.** |

**When the code and the docs disagree, trust:** the migrations first, then `database.md` §18–19, then this file, then everything else.

---

## 10. Quick commands

```bash
# backend
cd backend && .venv/Scripts/activate && python -m pytest
uvicorn app.main:app --host 127.0.0.1 --port 8000

# mobile
cd mobile && flutter pub get && flutter analyze && flutter test
flutter run --dart-define=FLAVOR=development

# device loop (Windows)
powershell -File scripts/dev-device.ps1
```
