# Dependencies

Only packages actually installed are listed, grouped by the phase that added them. Nothing here was added speculatively for a phase that hasn't happened yet.

## Flutter (`mobile/pubspec.yaml`)

| Package | Version | Purpose |
|---|---|---|
| flutter_riverpod | ^2.6.1 | State management |
| go_router | ^18.0.0 | Navigation / routing |
| supabase_flutter | ^2.17.2 | Supabase client (Auth, Postgres, Storage, Realtime) |
| flutter_secure_storage | ^11.0.0 | Encrypted local storage for session tokens |
| flutter_dotenv | ^6.0.1 | Per-flavor `.env` loading (dev/staging/prod configuration) |
| cupertino_icons | ^1.0.8 | Default Flutter template icon set (kept from `flutter create`) |
| flutter_lints (dev) | ^6.0.0 | Static analysis rule set (from `flutter create` default) |

## Flutter — Phase 4 additions

| Package | Version | Purpose |
|---|---|---|
| dio | ^5.11.0 | HTTP client for calling the FastAPI backend (`services/api/`) — added now because Phase 4 is the first phase that actually calls it (`GET /api/v1/me`) |

## Python Backend (`backend/requirements.txt`)

| Package | Version installed | Purpose |
|---|---|---|
| fastapi | 0.141.1 | API framework |
| uvicorn | 0.52.4 | ASGI server |
| pydantic | 2.13.4 | Request/response validation and settings parsing |
| pydantic-settings | 2.15.0 | Environment-variable-driven configuration (`app/core/config.py`) |
| supabase | 2.31.0 | Backend Supabase client (service-role access; never exposed to Flutter) |
| pytest | 9.1.1 | Test runner |
| httpx | 0.28.1 | Required by FastAPI's `TestClient` |

Transitive dependencies (postgrest, realtime, storage3, supabase-auth, supabase-functions, starlette, PyJWT, cryptography, etc.) are pulled in automatically by `fastapi`/`supabase` and are not chosen independently — see `backend/requirements.txt` lock via `pip freeze` in `docs/setup/README.md` if an exact transitive snapshot is ever needed.

## Python Backend — Phase 3 additions

| Package | Version installed | Purpose |
|---|---|---|
| pyjwt | 2.13.0 | Verifies Supabase-issued access tokens (`security/jwt.py`) — HS256 signature + expiry check against `SUPABASE_JWT_SECRET` |
| apscheduler | 3.11.3 | Background job scheduler lifecycle (`workers/scheduler.py`); started/stopped in `main.py`'s lifespan. No jobs registered yet — the first one lands with Follow-ups (Phase 11) |

No Celery/Redis was added — APScheduler is sufficient for Phase 3's foundation-only scope (zero jobs); revisit only if a later phase's job volume/retry needs actually outgrow it, per `docs/architecture/03-python-backend-architecture.md` §6.

## Tooling (not app dependencies)

| Tool | Version | Purpose |
|---|---|---|
| Supabase CLI | 2.106.0 | `supabase init`, migrations, local stack |
| Flutter SDK | 3.44.0 | Mobile build toolchain |
| Dart SDK | 3.12.0 | Ships with Flutter |
| Python | 3.10.11 | Backend runtime |
