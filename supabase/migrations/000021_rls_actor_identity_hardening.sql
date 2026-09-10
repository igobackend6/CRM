-- Phase 21 — Security Hardening. Closes a real RLS gap found across
-- every already-shipped INSERT policy that carries a "who performed
-- this" column (leads.created_by_member_id, follow_ups.created_by_member_id,
-- allocations.assigned_by_member_id, interactions.actor_member_id,
-- lead_documents.uploaded_by_member_id, ai_call_insights.requested_by_member_id):
-- none of those policies' own WITH CHECK verified that column against
-- the caller's own identity. Every backend service already sets these
-- fields to current_member_id() correctly (never client-supplied — see
-- e.g. LeadService.create_lead, InteractionRepository.create_note), so
-- this was never exploitable through the normal FastAPI path. But this
-- project's own architecture treats RLS as the FINAL security boundary,
-- not the backend's discipline alone — and RLS alone, as shipped, would
-- have let any authenticated member who already passes the existing
-- permission/visibility check (i.e. a legitimate user of their OWN
-- workspace) forge a raw REST call (Supabase's anon key + a real user
-- JWT are both reachable from any installed build of the Flutter app)
-- attributing a note/status-change/follow-up/allocation/document/AI
-- request to a DIFFERENT member than themselves — an audit-trail/
-- attribution integrity gap, not a cross-workspace or data-exfiltration
-- one.
--
-- Every policy below is reproduced in full (drop + recreate, per this
-- project's "never edit an existing migration" rule) with exactly one
-- kind of addition: `<actor_column> = current_member_id(workspace_id)`
-- (or `... is null`, for the columns the schema already allows to be
-- null for a system-generated row — see each table's own migration).
-- No column, permission, or visibility rule changes; every existing,
-- legitimate write already sets these columns correctly and is
-- unaffected.
--
-- Also included: `workspace_members_insert` didn't verify that the
-- inserted `role_id` is one the inserter is actually allowed to grant —
-- a member holding `members.invite` without `members.manage` (only
-- possible via a deliberate per-member `rep_permissions` override,
-- since the seeded roles always grant both together — see
-- 000013_reference_data.sql) could otherwise insert themselves or an
-- accomplice directly as `admin`/`ceo`. No member-management API exists
-- yet (this table's INSERT is unused by the shipped app), so this is a
-- dormant-surface hardening, included here since 000014_rls_policies.sql
-- is explicitly in this phase's audit scope.

drop policy leads_insert on leads;
create policy leads_insert on leads
  for insert to authenticated
  with check (
    has_permission(workspace_id, 'leads.create')
    and (created_by_member_id is null or created_by_member_id = current_member_id(workspace_id))
    and (is_manager_or_above(workspace_id) or assigned_member_id is null or assigned_member_id = current_member_id(workspace_id))
  );

drop policy follow_ups_insert on follow_ups;
create policy follow_ups_insert on follow_ups
  for insert to authenticated
  with check (
    has_permission(workspace_id, 'followups.create')
    and (created_by_member_id is null or created_by_member_id = current_member_id(workspace_id))
  );

drop policy allocations_insert on allocations;
create policy allocations_insert on allocations
  for insert to authenticated
  with check (
    has_permission(workspace_id, 'allocations.manage')
    and assigned_by_member_id = current_member_id(workspace_id)
  );

drop policy interactions_insert on interactions;
create policy interactions_insert on interactions
  for insert to authenticated
  with check (
    (actor_member_id is null or actor_member_id = current_member_id(workspace_id))
    and (
      is_manager_or_above(workspace_id)
      or exists (
        select 1 from leads l
        where l.id = interactions.lead_id
          and l.workspace_id = interactions.workspace_id
          and (l.assigned_member_id = current_member_id(interactions.workspace_id)
               or l.created_by_member_id = current_member_id(interactions.workspace_id))
      )
    )
  );

drop policy lead_documents_insert on lead_documents;
create policy lead_documents_insert on lead_documents
  for insert to authenticated
  with check (
    has_permission(workspace_id, 'documents.upload')
    and (uploaded_by_member_id is null or uploaded_by_member_id = current_member_id(workspace_id))
    and exists (
      select 1 from leads l
      where l.id = lead_documents.lead_id and l.workspace_id = lead_documents.workspace_id
    )
  );

drop policy ai_call_insights_insert on ai_call_insights;
create policy ai_call_insights_insert on ai_call_insights
  for insert to authenticated
  with check (
    has_permission(workspace_id, 'calls.update')
    and (requested_by_member_id is null or requested_by_member_id = current_member_id(workspace_id))
    and (
      is_manager_or_above(workspace_id)
      or exists (
        select 1 from calls c
        where c.workspace_id = ai_call_insights.workspace_id
          and c.id = ai_call_insights.call_id
          and c.agent_member_id = current_member_id(workspace_id)
      )
    )
  );

drop policy workspace_members_insert on workspace_members;
create policy workspace_members_insert on workspace_members
  for insert to authenticated
  with check (
    has_permission(workspace_id, 'members.invite')
    and (
      has_permission(workspace_id, 'members.manage')
      or exists (
        select 1 from roles r
        where r.id = workspace_members.role_id
          and r.name in ('team_mate', 'manager')
      )
    )
  );
