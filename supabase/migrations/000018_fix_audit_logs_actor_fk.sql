-- Fixes a real bug found via live Postgres/RLS validation (Phase 8/9
-- handoff, 2026-09-03, backend/scripts/validate_rls.py): audit_logs
-- had a COMPOSITE FK, audit_logs_actor_member_fk
-- (workspace_id, actor_member_id) -> workspace_members (workspace_id, id)
-- on delete set null (000011_notifications_audit.sql). Postgres's SET
-- NULL action on a composite FK nulls EVERY column of the FK, including
-- workspace_id — but audit_logs.workspace_id is NOT NULL, so physically
-- deleting a workspace_members row that had ever acted as an audit
-- actor made the FK's own cascade action violate that NOT NULL
-- constraint (23502 null value in column "workspace_id"), blocking the
-- delete entirely. Never hit through normal app usage (workspace_members
-- is only ever soft-removed via status='removed' through the client-
-- facing RLS-gated UPDATE policy — see 000014_rls_policies.sql's
-- comment "No DELETE policy"), but would hit any admin/ops hard-delete
-- or GDPR-erasure tooling, and did hit this migration's own validation
-- script's service-role cleanup step.
--
-- Fix: narrow the FK to a single column, actor_member_id ->
-- workspace_members(id), on delete set null. workspace_id is a
-- permanent historical fact about WHERE an event happened and must
-- never be nulled, regardless of whether the specific actor row still
-- exists — it no longer needs to travel in the same FK as
-- actor_member_id. No cross-workspace-reference protection is actually
-- lost in practice: log_audit_event() (000012_security_functions.sql)
-- always derives actor_member_id from current_member_id(v_workspace_id)
-- for the SAME v_workspace_id it writes, so the pair is correct by
-- construction — the composite FK's extra defense-in-depth was what
-- conflicted with the NOT NULL constraint, not something protecting
-- against a real, reachable bug.

alter table audit_logs drop constraint audit_logs_actor_member_fk;

alter table audit_logs
  add constraint audit_logs_actor_member_fk
    foreign key (actor_member_id) references workspace_members (id) on delete set null;
