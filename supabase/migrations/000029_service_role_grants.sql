-- Phase 0 (Admin/App alignment cycle) — explicit service_role grants.
--
-- Every prior migration grants table/function access to `authenticated`
-- only (see docs/architecture/rls.md §5). `service_role` — the role the
-- FastAPI backend uses for its privileged client (notify(), background
-- jobs, admin operations) — has been covered until now by Supabase's
-- *implicit* default privileges on a managed project's `public` schema.
--
-- A full schema reset (`drop schema public cascade; create schema public`)
-- destroys those implicit defaults: pg_default_acl entries are keyed to
-- the dropped schema's OID. Without this migration, the backend gets
-- "permission denied" on every table immediately after a reset — and it
-- reads like an RLS bug, not a grants bug. This makes the 29-migration
-- chain self-sufficient on any empty database, no out-of-band runbook
-- step required.
--
-- `anon` is deliberately NOT granted anything here — this CRM has no
-- unauthenticated data surface (rls.md §5), and RLS is default-deny
-- regardless. Only `service_role` was actually relying on the implicit
-- defaults.
--
-- Assumes migrations are applied as the `postgres` role (true for
-- `supabase db push` and the Supabase SQL Editor). The ALTER DEFAULT
-- PRIVILEGES below therefore covers objects a later migration creates;
-- the plain GRANTs cover everything migrations 000001-000028 already
-- created.

grant usage on schema public to service_role;

grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;
grant all on all functions in schema public to service_role;

alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant all on sequences to service_role;
alter default privileges in schema public grant all on functions to service_role;

-- Also latent-until-reset: ai_call_insights (000020) created RLS policies
-- but never an explicit GRANT to `authenticated` (every other table has
-- one — see 000014, 000019, 000022, 000025, 000028). Supabase's implicit
-- default privileges have masked it; a reset removes that. Grant exactly
-- the statement types its policies use (select/insert/update, no delete —
-- AI insights are never client-deleted).
grant select, insert, update on ai_call_insights to authenticated;
