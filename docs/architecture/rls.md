# Row Level Security — Phase 2

## 1. Principle

RLS is the real security boundary. Flutter and the Python backend perform permission checks too (defense in depth, and for better UX/error messages), but neither is trusted as the enforcement point — a compromised or buggy client can never read or write outside what these policies allow, because Postgres itself refuses the query.

Every table has `ALTER TABLE ... ENABLE ROW LEVEL SECURITY`. A table with RLS enabled and **no policy** for a given operation defaults to **deny** for that operation — several tables (e.g. `roles`, `profiles`, `workspaces`, `calls`, `follow_ups`, `allocations`, `interactions`) intentionally have no `DELETE` policy at all, and `notifications`/`audit_logs` intentionally have no client-facing `INSERT` policy. This is not an oversight; it's how "history can't be erased/fabricated from the client" is enforced.

## 2. Why Not Just `auth.uid() = user_id`

A policy like `using (auth.uid() = assigned_to)` would correctly stop User B from ever seeing User A's leads — but it would *also* stop a manager from seeing their team's leads, which breaks the product. Every ownership-sensitive policy in this schema instead checks: **is the row visible because of role (workspace-wide, for manager+) OR because of direct ownership (assigned/created/actor, for team_mate)** — see the `leads_select` policy for the canonical shape:

```sql
using (
  is_workspace_member(workspace_id)
  and (
    is_manager_or_above(workspace_id)
    or assigned_member_id = current_member_id(workspace_id)
    or created_by_member_id = current_member_id(workspace_id)
  )
)
```

## 3. Helper Functions (`000012_security_functions.sql`)

| Function | Returns | Purpose |
|---|---|---|
| `is_workspace_member(workspace_id)` | boolean | Is `auth.uid()` an active member of this workspace? |
| `current_member_id(workspace_id)` | uuid | `auth.uid()`'s `workspace_members.id` in this workspace |
| `get_member_role(workspace_id)` | text | `auth.uid()`'s role name in this workspace |
| `is_manager_or_above(workspace_id)` | boolean | role in (`manager`, `admin`, `ceo`) |
| `has_permission(workspace_id, code)` | boolean | Effective permission (override, else role baseline, else false) |
| `shares_workspace_with(profile_id)` | boolean | Do I share any active workspace with this profile? (used by `profiles` visibility) |
| `create_workspace(name, slug)` | uuid | Atomically creates a workspace + first member (bootstrap only) |

All are `SECURITY DEFINER` with `set search_path = public`, and all but `create_workspace` are `STABLE`.

### Why `SECURITY DEFINER` Doesn't Cause Recursion

A naive `is_workspace_member()` implemented as a plain (`SECURITY INVOKER`) SQL query against `workspace_members`, called from a policy defined *on* `workspace_members` itself, would re-trigger `workspace_members`'s own RLS on every internal lookup — which either loops or, more likely, silently sees zero rows (since the check hasn't resolved to "yes, member" yet) and always returns false. `SECURITY DEFINER` makes these functions run with the privileges of their owner (bypassing RLS internally) for this one, narrow, `auth.uid()`-scoped lookup — the standard Supabase pattern for this exact problem. `set search_path = public` is pinned on every one to prevent a search-path hijack from redirecting them to an attacker-controlled function/table.

## 4. Policy Summary by Table

| Table | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| `profiles` | self or shares a workspace | — (trigger-only) | self only | — |
| `workspaces` | member | — (via `create_workspace()` only) | `workspace.manage` | — |
| `roles`/`permissions`/`role_permissions` | any authenticated | — | — | — |
| `workspace_members` | member | `members.invite` | `members.manage` | — (use `status='removed'`) |
| `rep_permissions` | manager+, or own row | `members.manage` | `members.manage` | `members.manage` |
| `lead_statuses`/`lead_sources`/`call_outcomes` | member | `workspace.manage` | `workspace.manage` | `workspace.manage` |
| `tags` | member | any active member | `workspace.manage` | `workspace.manage` |
| `leads` | manager+ or owner/creator | `leads.create` | `leads.update` + (manager+ or owner) | `leads.delete` + (manager+ or owner) |
| `lead_tags` | via parent lead visibility | `leads.update` + lead ownership | — | `leads.update` + lead ownership |
| `lead_documents` | via parent lead visibility | `documents.upload` | `documents.delete` (soft-delete) | — |
| `calls` | manager+ or agent | `calls.create` + (manager+ or self) | `calls.update` + (manager+ or self) | — |
| `follow_ups` | manager+ or assignee/creator | `followups.create` | `followups.update` + (manager+ or assignee) | — |
| `allocations` | manager+ or assignee | `allocations.manage` | `allocations.manage` | — |
| `interactions` | manager+ or visible-lead | manager+ or visible-lead | — | — |
| `notifications` | recipient only | — (backend/service-role only) | recipient only, content-locked by trigger | — |
| `audit_logs` | `audit.read` | — (trigger only) | — | — |

"—" = no policy for that operation = default deny for the `authenticated` role.

## 5. Table-Level Grants

Because this project's `supabase/config.toml` does not set `auto_expose_new_tables = true` (the current Supabase default is to require explicit exposure), every table also needs a `GRANT` to the `authenticated` Postgres role before PostgREST will route requests to it at all — RLS policies are evaluated only *after* that coarse grant passes. `000014_rls_policies.sql` grants exactly the statement types each table's policies actually use (e.g. `calls` gets `SELECT, INSERT, UPDATE` but not `DELETE`, matching the missing delete policy). Nothing is granted to `anon` anywhere — this CRM has no unauthenticated read surface.

`000029_service_role_grants.sql` adds a blanket `GRANT ALL … TO service_role` on the whole `public` schema (tables, sequences, functions) plus matching `ALTER DEFAULT PRIVILEGES`. `service_role` is the role the FastAPI backend's privileged client uses (`notify()`, background jobs, admin ops); it bypasses RLS, so the grant is safe. On a managed Supabase project this is normally covered by *implicit* default privileges, but a full `drop schema public cascade` destroys those — this migration makes the whole chain self-sufficient on an empty database. `anon` is still granted nothing.

## 6. Storage Policies (`000015_storage.sql`)

Bucket `lead-documents` (private). Object path convention `{workspace_id}/{lead_id}/{filename}`. Policies read the workspace id out of the path (`storage.foldername(name)[1]`) and reuse the same `is_workspace_member`/`has_permission` functions as table RLS:

- `SELECT`: `is_workspace_member(workspace_id from path)`
- `INSERT`: `has_permission(workspace_id from path, 'documents.upload')`
- `DELETE`: `has_permission(workspace_id from path, 'documents.delete')`
- No `UPDATE` policy — files are replaced by delete + re-upload, never mutated in place.

## 7. Known Gaps / Not Enforced by RLS Alone

- **Notification content immutability**: RLS lets a recipient `UPDATE` their own notification row (to mark it read); a `BEFORE UPDATE` trigger (`prevent_notification_content_edit`) additionally rejects any change to `title`/`body`/`type`/`workspace_id`/`recipient_member_id`, since RLS alone can't express "only these two columns may change."
- **`interactions.payload` shape**: RLS controls which rows are visible/insertable, not what's inside `payload` — malformed or oversized payloads are an application-layer validation concern (Phase 3+), not a database one.
- **Realtime respects RLS**: Supabase Realtime evaluates the same RLS policies for change events, so enabling replication on `leads`/`follow_ups`/`notifications`/`allocations` (`000016_realtime.sql`) does not widen access beyond what these policies already allow.
