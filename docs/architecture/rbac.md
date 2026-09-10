# RBAC — Phase 2

## 1. Model

```
auth.users (Supabase Auth identity)
    |
profiles (person, global — name/phone/avatar, no workspace_id)
    |
workspace_members (THE tenant boundary: profile + workspace + role + status)
    |
    +-- role (team_mate | manager | admin | ceo) --> role_permissions --> permissions (baseline)
    |
    +-- rep_permissions (per-membership override: grant beyond role, or revoke from role)
```

Effective permission for a given `(workspace, action)` = `rep_permissions` override if one exists for that permission code, else the role's `role_permissions` baseline, else `false`. Implemented in `has_permission(workspace_id, permission_code)` (`000012_security_functions.sql`).

## 2. Roles

| Role | Intent |
|---|---|
| `team_mate` | Field rep. Sees/acts on records assigned to or created by them. |
| `manager` | Team oversight. Sees/acts on all records in the workspace; can assign/reassign, delete leads, run reports. |
| `admin` | Workspace administration: members, permission overrides, pipeline configuration (statuses/sources/outcomes/tags), audit log access. |
| `ceo` | Organization-level identity. **Same permission grants as `admin` in Phase 2** — kept as a distinct role now so future org-wide/multi-workspace reporting features have a role to attach to, rather than inventing a fifth role later and migrating every existing CEO account onto it. |

Roles are a **global, system-managed catalog** (`is_system = true`, no `workspace_id`) in Phase 2 — not per-workspace custom roles. This is a scoping decision, not a limitation baked into the data model: adding per-workspace custom roles later means making `roles.workspace_id` nullable and relaxing the current implicit "roles are global" assumption in `get_member_role()`/`has_permission()` — a small, additive change, not a redesign. See `database.md` §9.

## 3. Permission Catalog

23 permissions, namespaced `<resource>.<action>`, defined in `000013_reference_data.sql`:

| Category | Permissions |
|---|---|
| workspace | `workspace.manage` |
| members | `members.invite`, `members.manage`, `members.remove` |
| leads | `leads.read`, `leads.create`, `leads.update`, `leads.delete`, `leads.assign` |
| calls | `calls.read`, `calls.create`, `calls.update` |
| followups | `followups.read`, `followups.create`, `followups.update` |
| allocations | `allocations.read`, `allocations.manage` |
| documents | `documents.read`, `documents.upload`, `documents.delete` |
| notifications | `notifications.read` |
| reports | `reports.read` |
| audit | `audit.read` |

There are no separate `customers.*` permissions — a customer is a `leads` row (`database.md` §4), so `leads.*` already covers it. `leads.read`/`calls.read`/`followups.read`/`notifications.read`/`documents.read` exist in the catalog for future fine-grained UI gating even though Phase 2's RLS policies gate *row visibility* primarily through workspace/ownership + role, not these specific `*.read` codes — see `rls.md` §2 for why.

## 4. Baseline Grants (`000013_reference_data.sql`)

| Permission | team_mate | manager | admin | ceo |
|---|:---:|:---:|:---:|:---:|
| leads.read/create/update | ✅ | ✅ | ✅ | ✅ |
| leads.delete, leads.assign | | ✅ | ✅ | ✅ |
| calls.read/create/update | ✅ | ✅ | ✅ | ✅ |
| followups.read/create/update | ✅ | ✅ | ✅ | ✅ |
| allocations.read | | ✅ | ✅ | ✅ |
| allocations.manage | | ✅ | ✅ | ✅ |
| documents.read/upload | ✅ | ✅ | ✅ | ✅ |
| documents.delete | | ✅ | ✅ | ✅ |
| notifications.read | ✅ | ✅ | ✅ | ✅ |
| reports.read | | ✅ | ✅ | ✅ |
| workspace.manage | | | ✅ | ✅ |
| members.invite/manage/remove | | | ✅ | ✅ |
| audit.read | | | ✅ | ✅ |

## 5. Overrides (`rep_permissions`)

Scoped to a specific `workspace_members` row, not a profile — an override granted to someone in Workspace A never applies if they're also a member of Workspace B. Two directions:
- `granted = true`: widen access beyond the role baseline (e.g. give one `team_mate` `reports.read` without promoting them to `manager`).
- `granted = false`: narrow access below the role baseline (e.g. a `manager` who should not have `leads.delete`).

Writing an override requires `members.manage` (admin/ceo only) — see `rls.md`.

## 6. Why Reference Data Is a Migration

`roles`, `permissions`, and `role_permissions` are inserted by `000013_reference_data.sql`, a **migration**, not `supabase/seed.sql`. The Phase 2 brief's own wording suggests seed.sql as a home for "development roles, permissions" — but `seed.sql` is a Supabase CLI convention for **local-development-only** data (`supabase db reset` runs it; a real deploy to a remote/production project does not). The RBAC catalog is required in every environment for the permission system to function at all, including production — so it belongs in the migration history that every environment applies, not a dev-only convenience file. This is a deliberate, documented deviation from the letter of that instruction in favor of what actually works correctly in production; see the completion report for this called out explicitly.

## 7. Access Matrix (row-level, cross-referenced with RLS)

| Actor | Leads | Calls | Follow-ups | Allocations | Notifications | Audit log | Members/roles |
|---|---|---|---|---|---|---|---|
| team_mate | own (assigned/created) | own (as agent) | own (assigned/created) | own (assigned) | own only | ❌ | read roster only |
| manager | all in workspace | all in workspace | all in workspace | all in workspace | own only | ❌ | read roster only |
| admin | all in workspace | all in workspace | all in workspace | all in workspace | own only | ✅ read | manage |
| ceo | all in workspace | all in workspace | all in workspace | all in workspace | own only | ✅ read | manage |

Full policy definitions: `rls.md`.
