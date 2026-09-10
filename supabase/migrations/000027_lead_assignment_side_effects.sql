-- Phase 0 (Admin/App alignment cycle) — Lead assignment side effects.
--
-- Two clients now change leads.assigned_member_id: the FastAPI backend
-- (mobile app's POST /leads/{id}/assignment) and the React Admin panel
-- (direct UPDATE under RLS, from its Allocations screen). The two side
-- effects that must accompany every assignment — an allocations history
-- row and a notification to the new assignee — were implemented only in
-- FastAPI's LeadService (Phase 6). An assignment made from the Admin
-- panel produced neither: no allocation history, no notification, the
-- rep's badge never moved.
--
-- This moves both side effects into a database trigger so they hold for
-- ANY writer. LeadService.assign_lead is updated in the same change to
-- STOP doing them itself (otherwise every mobile-side reassignment
-- writes two allocation rows). This is scoped to assignment only — the
-- broader "move all service invariants into triggers" question
-- (soft-delete filtering, conversion stamping) stays deferred per the
-- Implementation Plan §7.
--
-- Ordering: the existing BEFORE trigger leads_enforce_assignment_permission
-- (000017) still runs first and blocks anyone without leads.assign, so
-- by the time this AFTER trigger fires the change is already authorized.
-- The generic leads_audit AFTER trigger (000012) is unaffected.

create or replace function on_lead_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
begin
  -- Only a real (re)assignment. Unassignment (new.assigned_member_id
  -- null) has no assignee to record or notify — allocations.assigned_member_id
  -- is NOT NULL, and there is no recipient. It is still captured by
  -- leads_audit like every other leads UPDATE.
  if new.assigned_member_id is distinct from old.assigned_member_id
     and new.assigned_member_id is not null then

    v_actor := current_member_id(new.workspace_id);

    insert into allocations
      (workspace_id, lead_id, assigned_member_id, assigned_by_member_id, status)
    values
      (new.workspace_id, new.id, new.assigned_member_id,
       coalesce(v_actor, new.assigned_member_id), 'new');

    -- No point notifying someone of their own action (a rep grabbing a
    -- lead, or an admin assigning one to themselves). lead_assigned vs
    -- lead_reassigned distinguishes a first assignment from a hand-off,
    -- matching the two CHECK values notifications.type already carries
    -- (000011) — same distinction LeadService made before this trigger.
    if new.assigned_member_id is distinct from v_actor then
      insert into notifications
        (workspace_id, recipient_member_id, type, title, body,
         related_entity_type, related_entity_id)
      values
        (new.workspace_id, new.assigned_member_id,
         case when old.assigned_member_id is null then 'lead_assigned' else 'lead_reassigned' end,
         case when old.assigned_member_id is null then 'Lead assigned to you' else 'Lead reassigned to you' end,
         new.name,
         'lead', new.id);
    end if;
  end if;

  return new;
end;
$$;

comment on function on_lead_assignment() is
  'Writes the allocations history row and the assignee notification on every leads.assigned_member_id change, regardless of which client made it. LeadService.assign_lead no longer does this itself (would double the allocation row).';

create trigger leads_on_assignment
  after update of assigned_member_id on leads
  for each row
  execute function on_lead_assignment();
