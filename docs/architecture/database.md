# Database Architecture — Phase 2

This supersedes the Phase 0 ERD proposal (`01-database-erd.md`) where the two disagree — Phase 2 is the implemented schema, produced after re-inspecting the actual Phase 0/1 output rather than assuming the Phase 0 draft was correct as-is. The most significant change: **workspace membership is modeled as its own table (`workspace_members`)**, not a `workspace_id` column on `profiles`, so a person can belong to more than one workspace without a redesign (see §2).

## 1. Entity List & Purpose

| Table | Purpose | Workspace-scoped |
|---|---|---|
| `workspaces` | Tenant root | n/a (root) |
| `profiles` | Global person identity, 1:1 with `auth.users` | ❌ (global) |
| `roles` | System role catalog (team_mate/manager/admin/ceo) | ❌ (global) |
| `permissions` | System permission catalog | ❌ (global) |
| `role_permissions` | Role → permission baseline grants | ❌ (global) |
| `workspace_members` | **The tenant boundary.** A profile's membership + role in a workspace | ✅ |
| `rep_permissions` | Per-membership permission overrides (grant or revoke) | ✅ |
| `lead_statuses` | Configurable pipeline stages | ✅ |
| `lead_sources` | Configurable lead origin catalog | ✅ |
| `call_outcomes` | Configurable call result catalog | ✅ |
| `tags` | Freeform label catalog | ✅ |
| `leads` | Core lead/prospect/customer record | ✅ |
| `lead_tags` | Lead ↔ tag join | ✅ |
| `lead_documents` | File metadata (bytes in Storage) | ✅ |
| `calls` | Call attempt history | ✅ |
| `follow_ups` | Scheduled follow-up actions | ✅ |
| `allocations` | Lead assignment event history | ✅ |
| `interactions` | Append-only Customer 360 timeline (includes notes) | ✅ |
| `notifications` | Per-user notification inbox | ✅ |
| `audit_logs` | Immutable mutation trail | ✅ |

**20 tables.** Every table evaluated from the Phase 2 prompt's "also evaluate" list that isn't here was deliberately rejected or deferred — see §9.

## 2. Workspace Membership Model

`profiles` holds identity only (name, phone, avatar) and is never workspace-scoped. `workspace_members` is a join between `profiles` and `workspaces` carrying `role_id` and `status`. This means:

- One profile can be an active member of multiple workspaces simultaneously (each with a potentially different role) — the schema doesn't block this even though the Flutter app's v1 UX assumes one active workspace at a time.
- Every "who owns/is-assigned-to this row" column elsewhere in the schema (`leads.assigned_member_id`, `calls.agent_member_id`, `follow_ups.assigned_member_id`, etc.) points at `workspace_members.id`, **not** `profiles.id` directly. This is deliberate: a reference to a `workspace_members` row is inherently workspace-scoped, so it composes with the composite foreign key pattern below to make a cross-workspace assignment structurally unrepresentable.

## 3. Composite Foreign Key Pattern

Every workspace-scoped table carries `unique (workspace_id, id)` in addition to its primary key. Every foreign key from one workspace-scoped table to another is then a **composite** foreign key on `(workspace_id, ref_id)` referencing `(workspace_id, id)` on the target — with `workspace_id` duplicated (not derived) on the referencing row.

Example (`lead_tags`):
```sql
constraint lead_tags_lead_fk
  foreign key (workspace_id, lead_id) references leads (workspace_id, id) on delete cascade,
constraint lead_tags_tag_fk
  foreign key (workspace_id, tag_id) references tags (workspace_id, id) on delete cascade
```

If `lead_tags.workspace_id` doesn't match the `workspace_id` actually stored on the referenced `leads`/`tags` row, the insert is rejected by Postgres — **before RLS is even evaluated**. This directly satisfies the requirement that "a lead from Workspace A must not reference a Workspace B tag," "a call from Workspace A must not reference a Workspace B user," and "an allocation from Workspace A must not reference a Workspace B lead" as database constraints, not just RLS/application checks. Applied to every cross-table reference in the schema: `leads`→`lead_statuses`/`lead_sources`/`workspace_members`, `lead_tags`→`leads`/`tags`, `lead_documents`→`leads`/`workspace_members`, `calls`→`leads`/`workspace_members`/`call_outcomes`, `follow_ups`→`leads`/`workspace_members`, `allocations`→`leads`/`workspace_members`, `interactions`→`leads`/`workspace_members`, `notifications`→`workspace_members`, `audit_logs`→`workspace_members`, `rep_permissions`→`workspace_members`.

The one exception: `workspace_members.profile_id → profiles.id` is a plain (non-composite) foreign key, because `profiles` is intentionally not workspace-scoped (§2).

## 4. Lead → Customer Conversion

There is **no separate `customers` table**. A `leads` row becomes a customer by setting `is_customer = true` and stamping `converted_at` (enforced by a `CHECK` constraint that `converted_at` is set whenever `is_customer` is true). This was a deliberate choice, not an oversight:

- A `customers` table referencing `leads` (or vice versa) creates exactly the circular `lead.customer_id` / `customer.lead_id` ownership the Phase 2 brief warned against.
- Every other table's `lead_id` reference (`calls`, `follow_ups`, `interactions`, `lead_documents`, `allocations`) keeps working unmodified after conversion — the row's identity never changes, so **interaction history survives conversion automatically**, with no migration/copy step.
- Customer-specific fields, if a real need appears later, add as nullable columns on `leads` or via the `metadata` jsonb column — not a second table.

## 5. Notes

There is **no separate `notes` table**. A note is an `interactions` row with `type = 'note'` and the note body in `payload`. The Phase 2 brief's own list of interaction types includes `note` — a note *is* a timeline event, not a related-but-distinct entity, so representing it any other way would mean either duplicating it in two places or building a dual-write path for no benefit.

## 6. Allocations vs. `leads.assigned_member_id`

`allocations` is the assignment **event history** (manager allocates → pending → actioned, potential reassignment). `leads.assigned_member_id` is the **current-owner pointer** used by every day-to-day query, index, and RLS check. These deliberately overlap: `allocations` answers "who was this lead assigned to, and when, and by whom, over time"; `leads.assigned_member_id` answers "who owns this lead right now" in O(1) without scanning history. This is a documented, intentional denormalization, not accidental duplication — see also §8 (indexes) for why the current-owner pointer needs to be a plain column rather than a `MAX(assigned_at)` subquery on every lead list render.

## 7. Configurable vs. Hardcoded

| Concept | Choice | Why |
|---|---|---|
| Lead pipeline stage (`lead_statuses`) | Configurable table | Admin manages the pipeline per workspace; also carries `is_won`/`is_lost` semantics other code depends on |
| Lead source (`lead_sources`) | Configurable table | Same — Admin-managed catalog |
| Call outcome (`call_outcomes`) | Configurable table | Same — Admin-managed catalog |
| Lead priority | `CHECK` constraint (`low`/`medium`/`high`/`urgent`) | Small, ordinal, not something Admin manages independently — a table would be ceremony without benefit |
| Notification type | `CHECK` constraint (fixed 5-value set) | Code-controlled (the backend decides when to notify), not Admin-configurable — a `notification_types` lookup table would have no writer other than a migration, indistinguishable from a CHECK |
| Call/follow-up/allocation state machines | `CHECK` constraint | Fixed, code-driven state machines (see `06-calling-architecture.md`), not business-configurable |

## 8. Index Strategy

| Table | Index | Serves |
|---|---|---|
| every workspace-scoped table | `(workspace_id, ...)` prefix on every meaningful index | RLS filters on `workspace_id` constantly; a bare `workspace_id` btree exists implicitly via these composite indexes |
| `leads` | `(workspace_id, status_id)`, `(workspace_id, assigned_member_id)`, `(workspace_id, created_at desc)`, `(workspace_id, phone)`, `(workspace_id, email)`, GIN trigram on `name` | Status/assignment filtering, recency sort, phone/email lookup, partial-name search |
| `calls` | `(workspace_id, lead_id, started_at desc)`, `(workspace_id, agent_member_id, started_at desc)` | Customer 360 call history, per-rep call log |
| `follow_ups` | `(workspace_id, assigned_member_id, due_at)`, `(workspace_id, lead_id)` | Today/overdue/upcoming queries, Customer 360 |
| `allocations` | `(workspace_id, assigned_member_id, status)`, `(workspace_id, lead_id)` | Rep's allocation queue, lead assignment history |
| `interactions` | `(workspace_id, lead_id, created_at desc)` | Customer 360 timeline render |
| `notifications` | `(workspace_id, recipient_member_id, is_read, created_at desc)` | Inbox badge + unread list |
| `audit_logs` | `(workspace_id, created_at desc)`, `(workspace_id, entity_type, entity_id)` | Audit browsing, "history for this record" |
| `workspace_members` | `(workspace_id)`, `(profile_id)`, `(workspace_id, status)` | Membership lookups, active-member filtering |

Not every column is indexed — e.g. `leads.priority` and `follow_ups.status`/`type` are low-cardinality and filtered alongside an already-indexed column, so a dedicated index wasn't added.

## 9. Entities Evaluated and Rejected/Deferred

| Entity | Decision | Reason |
|---|---|---|
| `customers` | Rejected | See §4 |
| `notes` | Rejected | See §5 |
| `bd_reps` | Rejected | `workspace_members` (role = `team_mate`) already represents "a rep in a workspace." A separate table would only be justified by rep-specific fields (quota, territory, employee code) that don't exist yet in any phase's requirements; when they do, they're either columns on `workspace_members` or, if genuinely bulky, a 1:1 extension table added at that point — not speculatively now |
| `workspace_members` | **Implemented** | This *is* the multi-workspace-membership model the brief asked to prefer over a single `profiles.workspace_id` column |
| `role_permissions` | **Implemented** | Needed the moment more than one role exists |
| `lead_priorities` | Rejected | `CHECK` constraint instead — see §7 |
| `call_recordings` | Deferred to Phase 21 | Master plan dedicates an entire later phase to call recording; no consumer exists yet, and the calling state machine (Phase 9) doesn't need it to function. Adding it now would be speculative schema for a feature not being built for many phases |
| `custom_fields` / `custom_field_values` | Deferred | No Leads UI exists yet to consume them (Phase 7). `leads.metadata jsonb` is an interim escape hatch. Building a full EAV model before any screen needs it risks guessing the wrong shape |
| `notification_types` | Rejected | `CHECK` constraint instead — see §7 |
| `agent_presence` | Deferred to Phase 17 (Team) | Presence is inherently tied to a realtime UI feature that doesn't exist yet; the table would have no writer or reader until then |

## 10. Constraints

- `NOT NULL` on every column where a missing value would be a data-integrity bug, not a legitimate "not yet known" state (e.g. `leads.name`, `calls.state`, `follow_ups.due_at` are required; `leads.phone`/`leads.email` are nullable because a lead may only have one of the two).
- `CHECK` constraints enforce every fixed-vocabulary column (see §7) and `leads.converted_at is not null` whenever `is_customer` is true.
- `UNIQUE (workspace_id, code)` on `lead_statuses`/`lead_sources`/`call_outcomes`, `UNIQUE (workspace_id, name)` on `tags`, `UNIQUE (workspace_id, profile_id)` on `workspace_members` (one membership per person per workspace), `UNIQUE (storage_path)` on `lead_documents`.
- Composite foreign keys enforce workspace-consistency at the database level — see §3.

## 11. Foreign Key Delete Behavior

| Relationship | Behavior | Why |
|---|---|---|
| `profiles.id → auth.users.id` | `CASCADE` | Deleting the Auth identity should remove the app profile with it — standard Supabase pattern |
| `workspace_members.profile_id → profiles.id` | `RESTRICT` | A profile with workspace history can't be silently deleted; remove the person via `workspace_members.status = 'removed'` instead, which the app is expected to use — physical profile deletion is an explicit, separate admin/compliance action |
| `leads.assigned_member_id`, `follow_ups.assigned_member_id → workspace_members` | `SET NULL` | If a membership is ever hard-deleted, the lead/follow-up becomes unassigned rather than disappearing |
| `calls.agent_member_id`, `allocations.assigned_member_id`/`assigned_by_member_id → workspace_members` | `RESTRICT` | These represent historical fact ("who made this call," "who assigned this") that must never silently vanish; combined with the `RESTRICT` above on `workspace_members.profile_id`, hard-deleting a member with call/allocation history is blocked by design — deactivate instead |
| `*.lead_id → leads.id` (calls, follow_ups, allocations, interactions, lead_tags, lead_documents) | `CASCADE` | These rows are meaningless without their parent lead. In practice this almost never fires because `leads` uses soft delete (§12) — hard-deleting a lead is a rare, explicit admin/data-operations action |
| `workspaces.id → *` (all direct children) | `CASCADE` | Deleting a workspace (an exceptional, admin-only operation — not exposed through normal app flows) removes everything under it |

## 12. Soft Delete Strategy

| Table | Strategy |
|---|---|
| `leads` | `deleted_at` — pipeline history, interactions, calls, follow-ups, and audit trail referencing the lead must survive a "delete" |
| `lead_documents` | `deleted_at` — deletion is permission-gated (`documents.delete`) and should be auditable/recoverable |
| `workspaces` | `status = 'archived'` (not `deleted_at`) — a status lifecycle (`active`/`suspended`/`archived`) is more expressive than a single soft-delete flag for a tenant root |
| `workspace_members` | `status = 'removed'` (not `deleted_at`) — same reasoning; membership already has a status lifecycle |
| `calls`, `follow_ups`, `allocations`, `interactions`, `notifications`, `audit_logs` | **No soft delete, no delete at all** — these are historical/event records. There is no `DELETE` RLS policy for any of them (default-deny); the product flows are "cancel a follow-up" (`status`), not "delete a follow-up" |
| `tags`, `lead_statuses`, `lead_sources`, `call_outcomes` | Hard delete allowed (admin-only via `workspace.manage`) — these are configuration, not history; `ON DELETE CASCADE`/`SET NULL` on dependents handles cleanup |

## 13. Timestamp Strategy

Every timestamp column is `timestamptz`, stored in UTC by Postgres regardless of session timezone; the application layer converts for display. `created_at` is set once via `default now()` and never updated. `updated_at` (present only on tables that are actually mutated after creation: `workspaces`, `profiles`, `workspace_members`, `leads`, `follow_ups`) is maintained by the generic `set_updated_at()` trigger, not by application code, so it can't be forgotten on some write path.

## 14. Audit Strategy

The generic `log_audit_event()` trigger is attached to `leads`, `allocations`, `follow_ups`, `calls`, `workspace_members`, and `rep_permissions` — the tables the Phase 2 brief explicitly calls out (lead creation/update/assignment/conversion, permission changes, user/membership changes) plus `calls` (call creation) and `follow_ups` (follow-up changes). It is **not** attached to `tags`, `lead_statuses`/`lead_sources`/`call_outcomes`, `lead_documents`, `notifications`, or `interactions` — the first three are low-stakes configuration, `lead_documents` changes are already visible via `interactions`/Storage, `notifications` are ephemeral, and `interactions` is already an append-only log (auditing an audit-adjacent log would be pure noise). `audit_logs` rows are written exclusively by this trigger (`SECURITY DEFINER`) — no `authenticated`-role `INSERT` policy exists, so a client can never fabricate or omit an audit entry.

## 15. Realtime Strategy

Enabled (via `supabase_realtime` publication) for `leads`, `follow_ups`, `notifications`, `allocations` — the tables with a concrete Phase 0-documented live-update consumer (lead list/allocation updates, follow-up reminders, the notification inbox) — plus `messages` (Phase 21B, `000023_realtime_messages.sql`), for Phase 16's internal messaging to update live. `conversations` stays unpublished: a `messages` insert is already a sufficient live-update signal for both the conversation list and an open conversation (its `updated_at` only ever changes as a side effect of one). `calls`, `interactions`, and `audit_logs` are excluded: a manager "live activity" view is a specific later-phase feature, not part of this foundation, and enabling realtime speculatively has an ongoing replication cost. `agent_presence` doesn't exist yet (§9).

Flutter-side architecture: `mobile/lib/core/realtime/` — a single per-workspace `RealtimeChannel` (`RealtimeChannelManager`), owned by one app-lifetime `RealtimeService` (`RealtimeService`/`realtimeServiceProvider`) that starts/stops it on workspace selection/logout/switch and pauses/resumes it with the app's foreground/background lifecycle. Feature controllers subscribe to its shared event stream via `RealtimeRefreshMixin`, never open their own channel.

## 16. Storage Strategy

Single private bucket `lead-documents` (`public = false`). Path convention `{workspace_id}/{lead_id}/{filename}`, which lets every Storage RLS policy reuse the exact same `is_workspace_member`/`has_permission` helper functions as the table policies, by reading the workspace id out of the object path (`storage.foldername(name)[1]`). No public URLs are issued; the Flutter/Python layers request short-lived signed URLs (Phase 15). See `docs/architecture/rls.md` §6 for the policy definitions.

## 17. What's Deliberately Not Here

- No FastAPI endpoints, repositories, or services (Phase 3+).
- No Flutter feature code (Phase 7+).
- No `custom_fields`, `call_recordings`, `agent_presence`, `campaigns`, `message_templates`, `rechurn_records` — all deferred to the phase that actually consumes them (§9 covers the first three; the latter three weren't in this phase's entity list at all and are left for their respective phases per the master plan).

## 18. Admin/App Alignment Cycle Additions (migrations 000025–000028)

Added when the React Admin panel was brought onto this canonical schema (see `Sales-CRM-Implementation-Plan` §4). Each belongs to the mobile app's migration set.

- **`custom_fields` / `custom_field_values` (`000025`)** — retires the `leads.metadata` stopgap (§9). An admin (`workspace.manage`) defines a field once — Runo's five types verbatim: `text`, `number`, `date`, `options` (single), `multi_options` — with `options` jsonb `[{code,label,sort_order}]` for the choice types, and four controls (`auto_fill` default true, `is_filterable`, `is_readonly`, `is_mandatory`). The mobile app renders it into the lead form on next load. Values are `jsonb` (one column per type), primary-keyed `(lead_id, custom_field_id)`, cascade-deleted with the field, **per-lead not per-interaction** (the history a per-interaction model buys is already in `audit_logs` + the activity timeline). Validation/coercion (type match, option membership, mandatory-on-create, read-only) lives in `CustomFieldService.resolve_values_for_write`, called by `LeadService` so both clients validate identically. `LeadCreate`/`LeadUpdate`/`LeadOut` carry a `custom_fields: {code: value}` map.
- **`lead_statuses.stage` (`000026`)** — replaces the `is_won`/`is_lost` boolean pair with one fixed-value column: `start | in_progress | closed_won | closed_lost`, mutually exclusive by construction (the booleans permitted `is_won AND is_lost` and couldn't express Start vs In Progress). Confirmed from Runo: Stage is a fixed four-value list, **not** a configurable table. Backfills from the old booleans + ordering. `provision_default_workspace_data()` seeds `stage` directly. Both codebases moved their `is_won`/`is_lost` reads to `stage` (backend: `LeadStatusOut`, rechurn/reports "lost status" filters; Flutter: `LeadStatus.stage` with `isWon`/`isLost` kept as derived getters, `AppStatusChip.forLeadStatus` now takes `stage`). Drives the pipeline board, reporting conversion rate, and the Rechurn queue.
- **`on_lead_assignment()` trigger (`000027`)** — writes the `allocations` history row and the assignee notification on **any** `assigned_member_id` change (mobile *or* Admin panel direct UPDATE), so the side effects §6 describes are no longer FastAPI-only. `LeadService.assign_lead` stopped doing these itself (would double the allocation row). Fires AFTER the existing BEFORE `leads_enforce_assignment_permission` (000017), so the change is already authorized by the time it runs. Also fires on `INSERT` — a lead created with an assignee already set (Admin panel's New Customer form, CSV bulk import with Assign To/Auto Assign) is a real first assignment too, not just an `UPDATE OF assigned_member_id`; `OLD` is unassigned during an INSERT trigger, so the function resolves the previous assignee once into a `TG_OP`-guarded variable instead of reading `OLD` directly.
- **`call_recordings` (`000028`)** — metadata-only, same shape as `lead_documents` (§16): bytes in a new private `call-recordings` bucket (`{workspace_id}/{call_id}/{filename}`), signed URLs only. Required adding `calls`'s missing `unique (workspace_id, id)` for the composite FK. On-device capture is Phase 5, its own project.
