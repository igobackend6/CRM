-- Row Level Security policies for every table, plus the table-level
-- GRANTs Supabase's PostgREST layer requires before RLS is even
-- evaluated (this project's config.toml does not set
-- auto_expose_new_tables, so new tables are NOT reachable via the Data
-- API without an explicit GRANT — RLS alone is not sufficient for
-- client access, and a missing GRANT here is the correct, safe failure
-- mode: the table simply isn't reachable at all).
--
-- Convention used throughout: GRANT is the coarse "this role may attempt
-- this kind of statement on this table" switch; RLS policies are the
-- fine-grained "which rows" filter. Nothing here grants anything to the
-- `anon` role — this CRM has no unauthenticated read surface.

grant usage on schema public to authenticated;

-- ---------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------
grant select, update on profiles to authenticated;

create policy profiles_select on profiles
  for select to authenticated
  using (id = auth.uid() or shares_workspace_with(id));

create policy profiles_update_self on profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- No INSERT/DELETE policy: rows are created only by handle_new_user()
-- (SECURITY DEFINER) and never deleted directly (auth.users cascade
-- handles identity removal).

-- ---------------------------------------------------------------------
-- workspaces
-- ---------------------------------------------------------------------
grant select, update on workspaces to authenticated;

create policy workspaces_select on workspaces
  for select to authenticated
  using (is_workspace_member(id));

create policy workspaces_update on workspaces
  for update to authenticated
  using (has_permission(id, 'workspace.manage'))
  with check (has_permission(id, 'workspace.manage'));

-- No INSERT/DELETE policy: creation only via create_workspace()
-- (SECURITY DEFINER); archiving is done via status = 'archived' through
-- the UPDATE policy above, not physical deletion.

-- ---------------------------------------------------------------------
-- roles / permissions / role_permissions (global, read-only catalog)
-- ---------------------------------------------------------------------
grant select on roles to authenticated;
grant select on permissions to authenticated;
grant select on role_permissions to authenticated;

create policy roles_select on roles for select to authenticated using (true);
create policy permissions_select on permissions for select to authenticated using (true);
create policy role_permissions_select on role_permissions for select to authenticated using (true);

-- No INSERT/UPDATE/DELETE policy on any of the three: managed only via
-- migrations in Phase 2 (no client-facing role/permission editing yet).

-- ---------------------------------------------------------------------
-- workspace_members
-- ---------------------------------------------------------------------
grant select, insert, update on workspace_members to authenticated;

create policy workspace_members_select on workspace_members
  for select to authenticated
  using (is_workspace_member(workspace_id));

create policy workspace_members_insert on workspace_members
  for insert to authenticated
  with check (has_permission(workspace_id, 'members.invite'));

create policy workspace_members_update on workspace_members
  for update to authenticated
  using (has_permission(workspace_id, 'members.manage'))
  with check (has_permission(workspace_id, 'members.manage'));

-- No DELETE policy: removal is status = 'removed' via the UPDATE policy,
-- preserving the row for history (calls/allocations/audit_logs that
-- reference it stay valid).

-- ---------------------------------------------------------------------
-- rep_permissions
-- ---------------------------------------------------------------------
grant select, insert, update, delete on rep_permissions to authenticated;

create policy rep_permissions_select on rep_permissions
  for select to authenticated
  using (
    is_manager_or_above(workspace_id)
    or workspace_member_id = current_member_id(workspace_id)
  );

create policy rep_permissions_insert on rep_permissions
  for insert to authenticated
  with check (has_permission(workspace_id, 'members.manage'));

create policy rep_permissions_update on rep_permissions
  for update to authenticated
  using (has_permission(workspace_id, 'members.manage'))
  with check (has_permission(workspace_id, 'members.manage'));

create policy rep_permissions_delete on rep_permissions
  for delete to authenticated
  using (has_permission(workspace_id, 'members.manage'));

-- ---------------------------------------------------------------------
-- lead_statuses / lead_sources / call_outcomes (admin-managed pipeline
-- config: any member reads, only workspace.manage can write)
-- ---------------------------------------------------------------------
grant select, insert, update, delete on lead_statuses to authenticated;
grant select, insert, update, delete on lead_sources to authenticated;
grant select, insert, update, delete on call_outcomes to authenticated;

create policy lead_statuses_select on lead_statuses for select to authenticated using (is_workspace_member(workspace_id));
create policy lead_statuses_write on lead_statuses for insert to authenticated with check (has_permission(workspace_id, 'workspace.manage'));
create policy lead_statuses_update on lead_statuses for update to authenticated using (has_permission(workspace_id, 'workspace.manage')) with check (has_permission(workspace_id, 'workspace.manage'));
create policy lead_statuses_delete on lead_statuses for delete to authenticated using (has_permission(workspace_id, 'workspace.manage'));

create policy lead_sources_select on lead_sources for select to authenticated using (is_workspace_member(workspace_id));
create policy lead_sources_write on lead_sources for insert to authenticated with check (has_permission(workspace_id, 'workspace.manage'));
create policy lead_sources_update on lead_sources for update to authenticated using (has_permission(workspace_id, 'workspace.manage')) with check (has_permission(workspace_id, 'workspace.manage'));
create policy lead_sources_delete on lead_sources for delete to authenticated using (has_permission(workspace_id, 'workspace.manage'));

create policy call_outcomes_select on call_outcomes for select to authenticated using (is_workspace_member(workspace_id));
create policy call_outcomes_write on call_outcomes for insert to authenticated with check (has_permission(workspace_id, 'workspace.manage'));
create policy call_outcomes_update on call_outcomes for update to authenticated using (has_permission(workspace_id, 'workspace.manage')) with check (has_permission(workspace_id, 'workspace.manage'));
create policy call_outcomes_delete on call_outcomes for delete to authenticated using (has_permission(workspace_id, 'workspace.manage'));

-- ---------------------------------------------------------------------
-- tags (any active member may create; only admins edit/delete, since a
-- tag rename/delete affects every lead using it)
-- ---------------------------------------------------------------------
grant select, insert, update, delete on tags to authenticated;

create policy tags_select on tags for select to authenticated using (is_workspace_member(workspace_id));
create policy tags_insert on tags for insert to authenticated with check (is_workspace_member(workspace_id));
create policy tags_update on tags for update to authenticated using (has_permission(workspace_id, 'workspace.manage')) with check (has_permission(workspace_id, 'workspace.manage'));
create policy tags_delete on tags for delete to authenticated using (has_permission(workspace_id, 'workspace.manage'));

-- ---------------------------------------------------------------------
-- leads
-- ---------------------------------------------------------------------
grant select, insert, update, delete on leads to authenticated;

create policy leads_select on leads
  for select to authenticated
  using (
    is_workspace_member(workspace_id)
    and (
      is_manager_or_above(workspace_id)
      or assigned_member_id = current_member_id(workspace_id)
      or created_by_member_id = current_member_id(workspace_id)
    )
  );

create policy leads_insert on leads
  for insert to authenticated
  with check (has_permission(workspace_id, 'leads.create'));

create policy leads_update on leads
  for update to authenticated
  using (
    has_permission(workspace_id, 'leads.update')
    and (is_manager_or_above(workspace_id) or assigned_member_id = current_member_id(workspace_id))
  )
  with check (
    has_permission(workspace_id, 'leads.update')
    and (is_manager_or_above(workspace_id) or assigned_member_id = current_member_id(workspace_id))
  );

create policy leads_delete on leads
  for delete to authenticated
  using (
    has_permission(workspace_id, 'leads.delete')
    and (is_manager_or_above(workspace_id) or assigned_member_id = current_member_id(workspace_id))
  );

-- ---------------------------------------------------------------------
-- lead_tags (visibility/write follows the parent lead's visibility)
-- ---------------------------------------------------------------------
grant select, insert, delete on lead_tags to authenticated;

create policy lead_tags_select on lead_tags
  for select to authenticated
  using (
    exists (
      select 1 from leads l
      where l.id = lead_tags.lead_id
        and l.workspace_id = lead_tags.workspace_id
        and (
          is_manager_or_above(l.workspace_id)
          or l.assigned_member_id = current_member_id(l.workspace_id)
          or l.created_by_member_id = current_member_id(l.workspace_id)
        )
    )
  );

create policy lead_tags_insert on lead_tags
  for insert to authenticated
  with check (
    has_permission(workspace_id, 'leads.update')
    and exists (
      select 1 from leads l
      where l.id = lead_tags.lead_id
        and l.workspace_id = lead_tags.workspace_id
        and (is_manager_or_above(l.workspace_id) or l.assigned_member_id = current_member_id(l.workspace_id))
    )
  );

create policy lead_tags_delete on lead_tags
  for delete to authenticated
  using (
    has_permission(workspace_id, 'leads.update')
    and exists (
      select 1 from leads l
      where l.id = lead_tags.lead_id
        and l.workspace_id = lead_tags.workspace_id
        and (is_manager_or_above(l.workspace_id) or l.assigned_member_id = current_member_id(l.workspace_id))
    )
  );

-- ---------------------------------------------------------------------
-- lead_documents (soft-delete via UPDATE, not DELETE)
-- ---------------------------------------------------------------------
grant select, insert, update on lead_documents to authenticated;

create policy lead_documents_select on lead_documents
  for select to authenticated
  using (
    exists (
      select 1 from leads l
      where l.id = lead_documents.lead_id
        and l.workspace_id = lead_documents.workspace_id
        and (
          is_manager_or_above(l.workspace_id)
          or l.assigned_member_id = current_member_id(l.workspace_id)
          or l.created_by_member_id = current_member_id(l.workspace_id)
        )
    )
  );

create policy lead_documents_insert on lead_documents
  for insert to authenticated
  with check (
    has_permission(workspace_id, 'documents.upload')
    and exists (
      select 1 from leads l
      where l.id = lead_documents.lead_id and l.workspace_id = lead_documents.workspace_id
    )
  );

create policy lead_documents_soft_delete on lead_documents
  for update to authenticated
  using (has_permission(workspace_id, 'documents.delete'))
  with check (has_permission(workspace_id, 'documents.delete'));

-- ---------------------------------------------------------------------
-- calls (no DELETE policy anywhere: calls are permanent history)
-- ---------------------------------------------------------------------
grant select, insert, update on calls to authenticated;

create policy calls_select on calls
  for select to authenticated
  using (
    is_workspace_member(workspace_id)
    and (is_manager_or_above(workspace_id) or agent_member_id = current_member_id(workspace_id))
  );

create policy calls_insert on calls
  for insert to authenticated
  with check (
    has_permission(workspace_id, 'calls.create')
    and (is_manager_or_above(workspace_id) or agent_member_id = current_member_id(workspace_id))
  );

create policy calls_update on calls
  for update to authenticated
  using (
    has_permission(workspace_id, 'calls.update')
    and (is_manager_or_above(workspace_id) or agent_member_id = current_member_id(workspace_id))
  )
  with check (
    has_permission(workspace_id, 'calls.update')
    and (is_manager_or_above(workspace_id) or agent_member_id = current_member_id(workspace_id))
  );

-- ---------------------------------------------------------------------
-- follow_ups (no DELETE policy: use status = 'cancelled')
-- ---------------------------------------------------------------------
grant select, insert, update on follow_ups to authenticated;

create policy follow_ups_select on follow_ups
  for select to authenticated
  using (
    is_workspace_member(workspace_id)
    and (
      is_manager_or_above(workspace_id)
      or assigned_member_id = current_member_id(workspace_id)
      or created_by_member_id = current_member_id(workspace_id)
    )
  );

create policy follow_ups_insert on follow_ups
  for insert to authenticated
  with check (has_permission(workspace_id, 'followups.create'));

create policy follow_ups_update on follow_ups
  for update to authenticated
  using (
    has_permission(workspace_id, 'followups.update')
    and (is_manager_or_above(workspace_id) or assigned_member_id = current_member_id(workspace_id))
  )
  with check (
    has_permission(workspace_id, 'followups.update')
    and (is_manager_or_above(workspace_id) or assigned_member_id = current_member_id(workspace_id))
  );

-- ---------------------------------------------------------------------
-- allocations (created/updated by managers+; no DELETE: history)
-- ---------------------------------------------------------------------
grant select, insert, update on allocations to authenticated;

create policy allocations_select on allocations
  for select to authenticated
  using (
    is_workspace_member(workspace_id)
    and (is_manager_or_above(workspace_id) or assigned_member_id = current_member_id(workspace_id))
  );

create policy allocations_insert on allocations
  for insert to authenticated
  with check (has_permission(workspace_id, 'allocations.manage'));

create policy allocations_update on allocations
  for update to authenticated
  using (has_permission(workspace_id, 'allocations.manage'))
  with check (has_permission(workspace_id, 'allocations.manage'));

-- ---------------------------------------------------------------------
-- interactions (append-only: no UPDATE/DELETE policy at all)
-- ---------------------------------------------------------------------
grant select, insert on interactions to authenticated;

create policy interactions_select on interactions
  for select to authenticated
  using (
    is_manager_or_above(workspace_id)
    or exists (
      select 1 from leads l
      where l.id = interactions.lead_id
        and l.workspace_id = interactions.workspace_id
        and (l.assigned_member_id = current_member_id(interactions.workspace_id)
             or l.created_by_member_id = current_member_id(interactions.workspace_id))
    )
  );

create policy interactions_insert on interactions
  for insert to authenticated
  with check (
    is_manager_or_above(workspace_id)
    or exists (
      select 1 from leads l
      where l.id = interactions.lead_id
        and l.workspace_id = interactions.workspace_id
        and (l.assigned_member_id = current_member_id(interactions.workspace_id)
             or l.created_by_member_id = current_member_id(interactions.workspace_id))
    )
  );

-- ---------------------------------------------------------------------
-- notifications (strictly personal; no client-facing INSERT policy —
-- only backend/service-role or a future SECURITY DEFINER function
-- creates notification rows)
-- ---------------------------------------------------------------------
grant select, update on notifications to authenticated;

create policy notifications_select on notifications
  for select to authenticated
  using (recipient_member_id = current_member_id(workspace_id));

create policy notifications_mark_read on notifications
  for update to authenticated
  using (recipient_member_id = current_member_id(workspace_id))
  with check (recipient_member_id = current_member_id(workspace_id));

-- ---------------------------------------------------------------------
-- audit_logs (read-only to authenticated with audit.read; all writes
-- come from SECURITY DEFINER trigger functions, not client statements)
-- ---------------------------------------------------------------------
grant select on audit_logs to authenticated;

create policy audit_logs_select on audit_logs
  for select to authenticated
  using (has_permission(workspace_id, 'audit.read'));
