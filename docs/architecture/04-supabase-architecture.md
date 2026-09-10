# 04 — Supabase Architecture

## 1. Role of Supabase

Supabase is the **single source of truth** for CRM data — Postgres, Auth, Storage, Realtime, RLS, DB functions/triggers, and Edge Functions where appropriate. Both the Flutter app and any future Admin web app read/write the same project; no parallel database is ever created.

## 2. Auth

- Supabase Auth as identity provider. Primary method: **phone + password** (matches field-sales usage patterns), with **email** supported where a workspace configures it.
- `profiles` table extends `auth.users` 1:1 (id = auth.users.id), holding `workspace_id`, `role_id`, `full_name`, `status` (active/suspended), etc.
- On first login for an invited user, a Postgres trigger (`handle_new_user`) provisions the matching `profiles` row from invite metadata — no manual client-side profile creation that could be skipped or tampered with.
- Session handled entirely via `supabase_flutter`'s built-in session persistence + secure storage; Python backend validates the same JWT rather than issuing its own tokens.

## 3. Row Level Security

- RLS **enabled on every table** from creation — no table ships without a policy, even temporarily.
- Shared SQL helper functions (`current_workspace_id()`, `current_role()`, `has_permission(text)`) centralize policy logic so 20+ tables don't each hand-roll the same subquery — defined once in Phase 2, referenced everywhere.
- Policy pattern is separated per operation (`select`/`insert`/`update`/`delete`) rather than one blanket `all` policy, so visibility rules (e.g., "team_mate sees only their own leads") can differ from mutation rules.

## 4. Storage

- Buckets: `lead-documents`, `call-recordings`, `avatars` (others added only if a real need appears).
- Path convention: `{workspace_id}/{entity_id}/{filename}` — Storage policies check the `workspace_id` path segment against `current_workspace_id()`, mirroring table RLS.
- All client access via **signed URLs** with short expiry, issued either directly by Supabase (simple lead-document preview, if policy allows) or by the Python backend for sensitive cases (recordings tied to compliance/retention rules).
- No bucket is public by default.

## 5. Realtime

Enabled selectively (not "replication for all" broadcast to every client):
- `leads` — filtered by `workspace_id` and, for `team_mate` role, further filtered to `assigned_to = self` client-side subscription parameters.
- `follow_ups`, `notifications`, `agent_presence` — same pattern.
- `calls` — only subscribed by manager-level "live team activity" views, not by default for every rep.

Each Realtime channel subscription is created/torn down alongside the screen/provider that needs it (no app-wide always-on subscription to heavy tables).

## 6. Database Functions & Triggers

Used where they provide real guarantees Flutter/Python can't:
- `handle_new_user()` — provision `profiles` on signup.
- Audit triggers on sensitive tables (see ERD doc §8) — write `audit_logs` server-side, un-bypassable from the client.
- `follow_ups` overdue derivation — either a generated/computed status via a scheduled job or a view; avoided as a hand-maintained client-side "is this overdue" calc that could drift.
- Lead status transition validation (optional, Phase 7) — reject illegal status jumps at the DB layer if the business rules demand it.

Triggers are added only where they enforce an invariant or capture an audit trail — not as a general-purpose place to put business logic (that stays in Python/services for testability).

## 7. Edge Functions

Reserved for cases that need to run **close to the DB** but don't warrant a full FastAPI round trip or need a webhook receiver Supabase can host directly (e.g., inbound webhook from a future messaging provider). Not used as a second backend — FastAPI remains the primary business-logic home; Edge Functions are the exception, justified case-by-case in later phases.

## 8. Migrations

- Managed via the Supabase CLI, versioned SQL migration files committed to the repo (`supabase/migrations/`), never hand-edited directly on the remote project outside of migrations.
- Every schema change ships as a migration + corresponding RLS policy update + (if applicable) audit trigger update in the same change set — schema and security policy are never allowed to drift apart.
