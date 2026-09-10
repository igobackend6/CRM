-- Security-definer helper functions used throughout RLS policies
-- (000014_rls_policies.sql). Each is SECURITY DEFINER + `set search_path`
-- so that:
--   1. Policies on workspace_members itself can call these helpers
--      without recursively re-triggering workspace_members' own RLS
--      (which would either infinite-loop or silently see zero rows).
--   2. `search_path` can't be hijacked by a session-level setting.
-- All are STABLE (safe to call multiple times per statement) and take
-- no writable side effects except the two explicitly transactional
-- bootstrap/audit functions at the bottom of this file.

create or replace function is_workspace_member(p_workspace_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from workspace_members
    where workspace_id = p_workspace_id
      and profile_id = auth.uid()
      and status = 'active'
  );
$$;

comment on function is_workspace_member(uuid) is
  'True if the current auth.uid() is an active member of the given workspace.';

create or replace function current_member_id(p_workspace_id uuid)
returns uuid
language sql
security definer
stable
set search_path = public
as $$
  select id
  from workspace_members
  where workspace_id = p_workspace_id
    and profile_id = auth.uid()
    and status = 'active'
  limit 1;
$$;

comment on function current_member_id(uuid) is
  'The workspace_members.id for the current auth.uid() in the given workspace, or null if not an active member.';

create or replace function get_member_role(p_workspace_id uuid)
returns text
language sql
security definer
stable
set search_path = public
as $$
  select r.name
  from workspace_members wm
  join roles r on r.id = wm.role_id
  where wm.workspace_id = p_workspace_id
    and wm.profile_id = auth.uid()
    and wm.status = 'active'
  limit 1;
$$;

comment on function get_member_role(uuid) is
  'The role name (team_mate/manager/admin/ceo) of the current auth.uid() in the given workspace, or null.';

create or replace function is_manager_or_above(p_workspace_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select coalesce(get_member_role(p_workspace_id) in ('manager', 'admin', 'ceo'), false);
$$;

comment on function is_manager_or_above(uuid) is
  'True if the current member''s role in the workspace is manager, admin, or ceo (workspace-wide visibility tier).';

create or replace function has_permission(p_workspace_id uuid, p_permission_code text)
returns boolean
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_member_id uuid;
  v_role_id uuid;
  v_override boolean;
  v_role_grant boolean;
begin
  select id, role_id into v_member_id, v_role_id
  from workspace_members
  where workspace_id = p_workspace_id
    and profile_id = auth.uid()
    and status = 'active';

  if v_member_id is null then
    return false;
  end if;

  select rp.granted into v_override
  from rep_permissions rp
  join permissions p on p.id = rp.permission_id
  where rp.workspace_member_id = v_member_id
    and p.code = p_permission_code;

  if v_override is not null then
    return v_override;
  end if;

  select exists (
    select 1
    from role_permissions rp
    join permissions p on p.id = rp.permission_id
    where rp.role_id = v_role_id
      and p.code = p_permission_code
  ) into v_role_grant;

  return v_role_grant;
end;
$$;

comment on function has_permission(uuid, text) is
  'Effective permission check: rep_permissions override (grant or revoke) takes precedence over the role_permissions baseline. False for anyone who is not an active member of the workspace.';

grant execute on function is_workspace_member(uuid) to authenticated;
grant execute on function current_member_id(uuid) to authenticated;
grant execute on function get_member_role(uuid) to authenticated;
grant execute on function is_manager_or_above(uuid) to authenticated;
grant execute on function has_permission(uuid, text) to authenticated;

create or replace function shares_workspace_with(p_profile_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from workspace_members mine
    join workspace_members theirs
      on theirs.workspace_id = mine.workspace_id
     and theirs.status = 'active'
    where mine.profile_id = auth.uid()
      and mine.status = 'active'
      and theirs.profile_id = p_profile_id
  );
$$;

comment on function shares_workspace_with(uuid) is
  'True if the current auth.uid() shares at least one active workspace membership with the given profile. Used so teammates can see each other''s basic profile info.';

grant execute on function shares_workspace_with(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Workspace bootstrap: creates a workspace AND its first member (the
-- creator, as admin) atomically. This is the only way to create a
-- workspace — there is no client-facing INSERT policy on the
-- workspaces table (see 000014_rls_policies.sql), which sidesteps the
-- chicken-and-egg problem of "you need to already be a member to be
-- allowed to insert into workspace_members."
-- ---------------------------------------------------------------------

create or replace function create_workspace(p_name text, p_slug text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_workspace_id uuid;
  v_admin_role_id uuid;
begin
  if auth.uid() is null then
    raise exception 'create_workspace requires an authenticated user';
  end if;

  select id into v_admin_role_id from roles where name = 'admin';

  insert into workspaces (name, slug)
  values (p_name, p_slug)
  returning id into v_workspace_id;

  insert into workspace_members (workspace_id, profile_id, role_id, status, joined_at)
  values (v_workspace_id, auth.uid(), v_admin_role_id, 'active', now());

  return v_workspace_id;
end;
$$;

comment on function create_workspace(text, text) is
  'Atomically creates a workspace and adds the calling user as its first member (role=admin). The only sanctioned way to create a workspace.';

grant execute on function create_workspace(text, text) to authenticated;

-- ---------------------------------------------------------------------
-- Per-workspace default pipeline data. Runs once, right after a
-- workspace is created, so every workspace has a usable set of lead
-- statuses/sources/call outcomes without any application code having to
-- remember to seed them (and it can't be skipped by a client bug).
-- ---------------------------------------------------------------------

create or replace function provision_default_workspace_data()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into lead_statuses (workspace_id, name, code, sort_order, is_won, is_lost, is_default) values
    (new.id, 'New', 'new', 10, false, false, true),
    (new.id, 'Contacted', 'contacted', 20, false, false, false),
    (new.id, 'Qualified', 'qualified', 30, false, false, false),
    (new.id, 'Follow Up', 'follow_up', 40, false, false, false),
    (new.id, 'Converted', 'converted', 50, true, false, false),
    (new.id, 'Lost', 'lost', 60, false, true, false);

  insert into lead_sources (workspace_id, name, code, is_default) values
    (new.id, 'Manual Entry', 'manual', true),
    (new.id, 'Website', 'website', false),
    (new.id, 'Referral', 'referral', false),
    (new.id, 'Cold Call', 'cold_call', false),
    (new.id, 'Campaign', 'campaign', false);

  insert into call_outcomes (workspace_id, name, code, is_positive, is_default) values
    (new.id, 'Connected', 'connected', true, true),
    (new.id, 'Not Connected', 'not_connected', false, false),
    (new.id, 'Busy', 'busy', false, false),
    (new.id, 'No Answer', 'no_answer', false, false),
    (new.id, 'Interested', 'interested', true, false),
    (new.id, 'Not Interested', 'not_interested', false, false),
    (new.id, 'Callback Requested', 'callback_requested', true, false);

  return new;
end;
$$;

comment on function provision_default_workspace_data() is
  'Seeds default lead_statuses/lead_sources/call_outcomes for a newly created workspace. This is why supabase/seed.sql does not contain workspace pipeline data — it is provisioned here, in every environment, not just local dev.';

create trigger workspaces_provision_defaults
  after insert on workspaces
  for each row
  execute function provision_default_workspace_data();

-- ---------------------------------------------------------------------
-- Generic audit trigger. Attached (below) to the specific tables listed
-- in docs/architecture/database.md "Audit Strategy" — not every table,
-- to avoid audit noise on low-stakes/high-volume writes.
-- ---------------------------------------------------------------------

create or replace function log_audit_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_workspace_id uuid;
  v_entity_id uuid;
  v_actor_member_id uuid;
begin
  v_workspace_id := coalesce(new.workspace_id, old.workspace_id);
  v_entity_id := coalesce(new.id, old.id);
  v_actor_member_id := current_member_id(v_workspace_id);

  insert into audit_logs (workspace_id, actor_member_id, action, entity_type, entity_id, before, after)
  values (
    v_workspace_id,
    v_actor_member_id,
    lower(tg_op),
    tg_table_name,
    v_entity_id,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) else null end
  );

  return coalesce(new, old);
end;
$$;

comment on function log_audit_event() is
  'Generic AFTER INSERT/UPDATE/DELETE trigger that records a row in audit_logs. actor_member_id is null for system-driven changes (migrations, triggers, service-role jobs run outside an authenticated session).';

create trigger leads_audit
  after insert or update or delete on leads
  for each row execute function log_audit_event();

create trigger allocations_audit
  after insert or update or delete on allocations
  for each row execute function log_audit_event();

create trigger follow_ups_audit
  after insert or update or delete on follow_ups
  for each row execute function log_audit_event();

create trigger calls_audit
  after insert or update or delete on calls
  for each row execute function log_audit_event();

create trigger workspace_members_audit
  after insert or update or delete on workspace_members
  for each row execute function log_audit_event();

create trigger rep_permissions_audit
  after insert or update or delete on rep_permissions
  for each row execute function log_audit_event();
