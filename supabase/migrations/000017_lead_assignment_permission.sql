-- Phase 6 — Lead Assignment & Allocation Foundation.
--
-- Why this migration is genuinely required (per the "do not modify RLS
-- without a clear requirement" rule): the existing `leads_update` RLS
-- policy (000014_rls_policies.sql) only requires `leads.update` +
-- ownership-or-manager for ANY column change on a lead, including
-- `assigned_member_id`. It does not independently require `leads.assign`
-- (the permission the RBAC catalog defines specifically for "assign or
-- reassign a lead to a rep" — 000013_reference_data.sql) when that
-- particular column changes.
--
-- The FastAPI backend's new POST /leads/{id}/assignment endpoint (Phase
-- 6) already gates on `leads.assign` before issuing the update — but
-- this project's repeated, explicit principle (every phase since
-- Phase 2) is that RLS/the database is the *real* security boundary,
-- not the API layer. Without this trigger, a team_mate who owns a lead
-- and has the (commonly-granted) `leads.update` permission could
-- reassign it away by calling Supabase's PostgREST directly with their
-- own JWT, bypassing the backend's stricter gate entirely.
--
-- RLS policies alone cannot express "only if this specific column
-- changed" (USING/WITH CHECK don't get an OLD-vs-NEW diff), so this is
-- a trigger, not a policy edit — 000014_rls_policies.sql is untouched.
-- Scope is intentionally narrow: it only fires when assigned_member_id
-- is actually changing, so `leads_update` continues to be the only
-- thing that governs every other field.

create or replace function enforce_lead_assignment_permission()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.assigned_member_id is distinct from old.assigned_member_id then
    if not has_permission(new.workspace_id, 'leads.assign') then
      raise exception 'permission denied: leads.assign is required to assign, reassign, or unassign a lead'
        using errcode = '42501'; -- insufficient_privilege
    end if;
  end if;
  return new;
end;
$$;

comment on function enforce_lead_assignment_permission() is
  'Closes an RLS granularity gap: leads_update (000014_rls_policies.sql) only checks leads.update + ownership-or-manager for any field. This trigger additionally requires leads.assign specifically when assigned_member_id changes (assign/reassign/unassign), matching the RBAC catalog''s dedicated permission for that action.';

-- BEFORE UPDATE, same timing as leads_set_updated_at (000008_leads.sql).
-- Postgres runs same-timing triggers in name order, but this one only
-- validates and never modifies NEW, so its order relative to that
-- trigger doesn't matter. leads_audit (000012_security_functions.sql)
-- is a separate AFTER trigger and unaffected either way.
create trigger leads_enforce_assignment_permission
  before update on leads
  for each row
  execute function enforce_lead_assignment_permission();
