# 09 — Development Phases, Deployment Architecture & Risk Register

## 1. Development Phases (gate: each phase requires explicit approval before the next starts)

| # | Phase | Exit Criteria |
|---|---|---|
| 0 | Architecture & requirement audit | This document set reviewed and approved |
| 1 | Repository/project initialization | Flutter + backend skeletons, CI skeleton, lint/format configs, `.env.example` files |
| 2 | Supabase database foundation | Full schema migrated, RLS on every table, seed data for dev |
| 3 | Python FastAPI foundation | App skeleton, auth dependency, health check, background-job runner chosen and wired |
| 4 | Flutter foundation | Folder structure, theme, router skeleton, Supabase/Dio clients wired, flavors (dev/staging/prod) |
| 5 | Authentication | Full login/logout/session/permission-load flow, end-to-end |
| 6 | App shell | Nav shell, offline banner, notification badge, presence stub |
| 7 | Leads | Full CRUD + search/filter/sort/tags/custom fields, end-to-end |
| 8 | Customer 360 | Timeline aggregation, notes, documents surfaced |
| 9 | Calling | Native bridge, state machine, call logging end-to-end |
| 10 | Call Logs | Filterable log views |
| 11 | Follow-ups | CRUD, reminders, push notifications |
| 12 | Calendar | Day/week/month views |
| 13 | Allocations | Assign/reassign flows, notifications |
| 14 | Notifications | Full inbox + push, realtime badge |
| 15 | Documents | Upload/preview/delete, signed URLs |
| 16 | Messaging | WhatsApp deep links + templates |
| 17 | Realtime | Selective channel wiring across relevant features |
| 18 | Dashboard | KPI aggregation, quick actions |
| 19 | Reports | Personal/team reports, date filters |
| 20 | Auto Dialer | Queue + state machine, permission-respecting |
| 21 | Call Recording | Capability detection, upload, status tracking |
| 22 | Rechurn | Re-engagement queue and workflow |
| 23 | AI | Transcription/summary/scoring pipeline |
| 24 | Security hardening | Pen-test-style pass, rate limiting, audit coverage review |
| 25 | QA | Full regression across modules |
| 26 | Production release | Store listing, release signing, monitoring live |

## 2. Per-Phase Implementation Checklist (applies to every phase from #7 onward)

1. Inspect existing project structure.
2. Inspect current DB schema.
3. Inspect current RLS.
4. Inspect related Admin functionality (once Admin exists).
5. Identify existing tables/functions — don't duplicate.
6. Define data contract (DTOs).
7. Define UI states (loading/empty/error/data).
8. Define error states.
9. Implement.
10. Test.
11. Run static analysis.
12. Run unit tests.
13. Document the change.

## 3. Deployment Architecture

- **Supabase**: managed project, separate `dev`/`staging`/`prod` projects (or schemas, decided in Phase 1) to avoid dev churn touching real data; migrations applied via CLI in CI.
- **Python backend**: containerized (Docker), deployed to a managed host (target decided in Phase 3 — e.g., Fly.io/Render/Cloud Run class of platform); environment-specific `.env` injected via the platform's secret store, never committed.
- **Flutter**: flavor-based builds (dev/staging/prod) pointing at the matching Supabase project + API base URL; release build signed and distributed via Play Console (internal testing track first, per Phase 26).
- **CI/CD**: lint + test gates from Phase 1; deployment automation hardens through Phase 24–26 (not fully automated on day one).

## 4. Risk Register

| Risk | Impact | Likelihood | Mitigation |
|---|---|---|---|
| RLS policy gap leaks cross-workspace data | High | Medium | RLS tests per table (Phase 2), defense-in-depth API checks, security hardening pass (Phase 24) |
| Native Android call/recording behavior varies wildly by OEM | Medium | High | Capability detection at runtime, never assume support; call logging never depends on recording success |
| Background job platform choice (Phase 3) turns out under-scaled | Medium | Low | Start simple (APScheduler/cron), architecture keeps workers decoupled behind a job interface so swapping the runner doesn't touch business logic |
| Offline queued writes cause duplicate/lost data | Medium | Medium | Only idempotent-safe writes are queued; risky writes (lead creation) fail explicitly instead of silently queuing |
| Secrets leak into Flutter build (service-role key, AI keys) | Critical | Low (if disciplined) | Explicit rule + code review checklist; secrets never referenced in `lib/` |
| Scope creep — building AI/advanced features before core is stable | Medium | Medium | Strict phase gating (§1), AI is Phase 23 not before |
| WhatsApp deep-link messaging misrepresented as Business API automation | Low (reputational/legal) | Low | Explicit UI copy review in Phase 16 — never claim automation the feature doesn't have |
| Custom fields (EAV) degrade query performance at scale | Medium | Medium | Indexing plan on `custom_field_values`, revisit denormalization if a workspace's custom-field volume becomes a bottleneck |
| Multi-tenant migration mistakes affect all tenants at once | High | Low | Migrations reviewed pre-apply, staged through dev/staging before prod, reversible where feasible |
| Real-device recording/telephony testing coverage is limited | Medium | Medium | Document known-untested OEM/API-level gaps explicitly rather than claiming full coverage |

## 5. Approval Gate

Per the master plan: **implementation of Phase 1 does not begin until this document set is reviewed and explicitly approved.** Open questions are flagged inline (see `01-database-erd.md` §9) for resolution during that review.
