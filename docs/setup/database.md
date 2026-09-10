# Database Setup — Phase 2

## Migrations

All schema is in `supabase/migrations/`, applied in filename order:

| File | Contents |
|---|---|
| `000001_extensions.sql` | `pgcrypto`, `uuid-ossp` |
| `000002_functions_generic.sql` | `set_updated_at()` |
| `000003_workspaces.sql` | `workspaces` |
| `000004_profiles.sql` | `profiles`, `handle_new_user()` trigger on `auth.users` |
| `000005_roles_permissions.sql` | `roles`, `permissions`, `role_permissions` |
| `000006_workspace_members_permissions.sql` | `workspace_members`, `rep_permissions` |
| `000007_leads_pipeline_config.sql` | `lead_statuses`, `lead_sources`, `call_outcomes`, `tags` |
| `000008_leads.sql` | `leads`, `lead_tags`, `lead_documents`, `pg_trgm` |
| `000009_calls_followups.sql` | `calls`, `follow_ups` |
| `000010_allocations_interactions.sql` | `allocations`, `interactions` |
| `000011_notifications_audit.sql` | `notifications`, `audit_logs` |
| `000012_security_functions.sql` | RLS helper functions, `create_workspace()`, `provision_default_workspace_data()`, audit triggers |
| `000013_reference_data.sql` | Seeds `roles`/`permissions`/`role_permissions` (global RBAC catalog — see `docs/architecture/rbac.md` §6 for why this is a migration, not `seed.sql`) |
| `000014_rls_policies.sql` | Every RLS policy + table grants |
| `000015_storage.sql` | `lead-documents` bucket + Storage policies |
| `000016_realtime.sql` | Adds `leads`/`follow_ups`/`notifications`/`allocations` to the realtime publication |

## Applying Locally

```bash
cd E:\CRM
supabase start      # requires Docker Desktop running
supabase db reset    # applies every migration + seed.sql to a fresh local DB
```

`supabase db reset` is the right command here (not `supabase migration up`) because it rebuilds the local DB from scratch, which is how these migrations were validated for this phase — see "Validation" below.

## `seed.sql`

Deliberately near-empty. Workspace pipeline defaults (statuses/sources/outcomes) are provisioned automatically per-workspace by a trigger (`provision_default_workspace_data()`), and RBAC reference data is a migration (`000013_reference_data.sql`) because it's needed in every environment, not just local dev. There is no fake lead/customer data anywhere in this repo.

## Validation

**Docker was not available in the environment this phase was built in.** `docker --version` reports Docker 29.7.2 installed, but the daemon was never reachable (`docker ps` → `failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine`). Two attempts were made to launch Docker Desktop; the Windows `com.docker.service` remained `Stopped` and would not start (likely requires elevated/interactive privileges this environment doesn't have). As a result, **`supabase start` / `supabase db reset` were not run, and `supabase/tests/rls_security_tests.sql` has not been executed against a real Postgres instance.**

What *was* done instead, given that constraint:
- Every migration file was manually re-read end-to-end for syntax and logical correctness after being written, cross-checking every foreign key, generated column, and trigger against the columns actually defined on its target table.
- This review caught and fixed one real bug: `rep_permissions` originally had no surrogate `id` column, which would have made the generic `log_audit_event()` trigger fail at runtime (`record "new" has no field "id"`) the first time a permission override was inserted/updated/deleted. Fixed by adding `rep_permissions.id` (`000006_workspace_members_permissions.sql`).
- `supabase init` (CLI-only, no daemon needed) succeeded and produced a valid `config.toml`.

**This is a real, unresolved gap, not a passed test.** The migrations and the RLS test suite should be run against a real local (or disposable remote) Supabase project — `supabase start && supabase db reset && psql "$(supabase status -o env | grep DB_URL)" -f supabase/tests/rls_security_tests.sql`, or equivalent — before Phase 3 relies on this schema, and especially before any real data is ever written to a production project using it.

## Extending the Schema Later

- **New workspace-scoped table**: give it `id uuid primary key default gen_random_uuid()`, `workspace_id uuid not null references workspaces(id) on delete cascade`, `unique (workspace_id, id)`, and use composite `(workspace_id, ref_id)` foreign keys for any reference to another workspace-scoped table (`docs/architecture/database.md` §3). Enable RLS immediately; add policies before the table is used for real data.
- **New permission**: insert into `permissions`, then `role_permissions` for whichever roles should have it by default, in a new migration (not `seed.sql` — see `rbac.md` §6).
- **Per-workspace custom roles**: `docs/architecture/rbac.md` §2 documents the forward-compatible path.
