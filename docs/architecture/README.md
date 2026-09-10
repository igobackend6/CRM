# Architecture — Phase 1 Snapshot

This file is the entry point for architecture documentation. The full pre-implementation architecture package (feature matrix, ERD, folder layouts, security/testing/deployment strategy, risk register) produced during Phase 0 lives in this same folder:

- [00 — Overview & Feature Matrix](00-overview-and-feature-matrix.md)
- [01 — Database Architecture & ERD](01-database-erd.md)
- [02 — Flutter Architecture](02-flutter-architecture.md)
- [03 — Python Backend Architecture](03-python-backend-architecture.md)
- [04 — Supabase Architecture](04-supabase-architecture.md)
- [05 — Auth, RBAC & Security Model](05-security-and-permission-architecture.md)
- [06 — Calling, Recording, Realtime & Notification Architecture](06-calling-architecture.md)
- [07 — AI Architecture](07-ai-architecture.md)
- [08 — Testing Strategy](08-testing-strategy.md)
- [09 — Phases, Deployment & Risk Register](09-phases-deployment-and-risk-register.md)

## High-Level System (as built in Phase 1)

```text
Flutter Mobile (mobile/)
      |
      ├── Supabase (Auth, Postgres, Storage, Realtime — client-safe anon key only)
      |
      └── Python FastAPI (backend/)
               |
               └── Supabase / PostgreSQL (privileged service-role access)
```

Phase 1 establishes the skeleton on both sides of this diagram — no CRM tables, no business endpoints, no auth flow yet. See `09-phases-deployment-and-risk-register.md` for what each later phase adds.

## What Phase 1 Actually Built

- `mobile/` — a clean Flutter Android app with a feature-first `lib/core` foundation (config, router, theme, error handling, logging) and a `lib/services` layer (Supabase client, secure storage) wired but not yet used by any feature.
- `backend/` — a minimal FastAPI app (`app/main.py`) with a `/health` endpoint, centralized settings, structured logging, and a generic exception-handling layer. `app/services` and `app/repositories` exist as empty scaffolding for Phase 2+.
- `supabase/` — CLI project structure (`config.toml`, `migrations/`, `seed.sql`) with **no CRM tables** — schema design is Phase 2.
