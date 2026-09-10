-- RLS / database security test suite.
--
-- Runs as the Postgres superuser (bypasses RLS) to set up fixtures, then
-- switches to `role authenticated` + a simulated JWT (the same mechanism
-- PostgREST uses) to exercise the actual RLS policies as specific users.
-- A failing assertion raises an exception and aborts the script — clean
-- run to the final NOTICE means every check below passed.
--
-- Usage (local stack only — never point this at a real/shared database):
--   supabase start
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/rls_security_tests.sql
--
-- Everything runs inside one transaction that is rolled back at the end,
-- so this script never leaves fixture data behind.

begin;

create or replace function pg_temp.assert(p_condition boolean, p_message text)
returns void
language plpgsql
as $$
begin
  if not p_condition then
    raise exception 'FAILED: %', p_message;
  else
    raise notice 'PASS: %', p_message;
  end if;
end;
$$;

-- -----------------------------------------------------------------
-- Fixtures: two workspaces, several users, as the superuser (bypasses
-- RLS for setup only — every assertion below runs as `authenticated`).
-- -----------------------------------------------------------------

do $$
declare
  v_user_a_admin uuid := gen_random_uuid();
  v_user_a_manager uuid := gen_random_uuid();
  v_user_a_rep1 uuid := gen_random_uuid();
  v_user_a_rep2 uuid := gen_random_uuid();
  v_user_b_admin uuid := gen_random_uuid();
begin
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values
    (v_user_a_admin, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a-admin@test.local', '', now(), '{}', '{}', now(), now()),
    (v_user_a_manager, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a-manager@test.local', '', now(), '{}', '{}', now(), now()),
    (v_user_a_rep1, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a-rep1@test.local', '', now(), '{}', '{}', now(), now()),
    (v_user_a_rep2, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a-rep2@test.local', '', now(), '{}', '{}', now(), now()),
    (v_user_b_admin, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b-admin@test.local', '', now(), '{}', '{}', now(), now());

  -- Stash the generated ids somewhere the rest of the script can read
  -- them back without re-deriving uuids.
  create temporary table test_fixture_ids (key text primary key, id uuid not null);
  insert into test_fixture_ids values
    ('user_a_admin', v_user_a_admin),
    ('user_a_manager', v_user_a_manager),
    ('user_a_rep1', v_user_a_rep1),
    ('user_a_rep2', v_user_a_rep2),
    ('user_b_admin', v_user_b_admin);
end $$;

-- Helper to switch the simulated session identity.
create or replace function pg_temp.login_as(p_user_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, true);
  set local role authenticated;
end;
$$;

-- Bootstrap workspace A as its admin, workspace B as its admin (the
-- only sanctioned way to create a workspace — see create_workspace()).
do $$
declare
  v_workspace_a uuid;
  v_workspace_b uuid;
  v_admin_a uuid := (select id from test_fixture_ids where key = 'user_a_admin');
  v_admin_b uuid := (select id from test_fixture_ids where key = 'user_b_admin');
begin
  perform pg_temp.login_as(v_admin_a);
  v_workspace_a := create_workspace('Workspace A', 'workspace-a-' || substr(v_admin_a::text, 1, 8));

  reset role;
  perform pg_temp.login_as(v_admin_b);
  v_workspace_b := create_workspace('Workspace B', 'workspace-b-' || substr(v_admin_b::text, 1, 8));
  reset role;

  insert into test_fixture_ids values ('workspace_a', v_workspace_a), ('workspace_b', v_workspace_b);
end $$;

-- Add manager + two reps to Workspace A (as postgres, bypassing RLS —
-- this is fixture setup, not something under test).
do $$
declare
  v_workspace_a uuid := (select id from test_fixture_ids where key = 'workspace_a');
  v_manager_role uuid := (select id from roles where name = 'manager');
  v_team_mate_role uuid := (select id from roles where name = 'team_mate');
begin
  insert into workspace_members (workspace_id, profile_id, role_id, status, joined_at) values
    (v_workspace_a, (select id from test_fixture_ids where key = 'user_a_manager'), v_manager_role, 'active', now()),
    (v_workspace_a, (select id from test_fixture_ids where key = 'user_a_rep1'), v_team_mate_role, 'active', now()),
    (v_workspace_a, (select id from test_fixture_ids where key = 'user_a_rep2'), v_team_mate_role, 'active', now());
end $$;

-- -----------------------------------------------------------------
-- Test: manager creates a lead in Workspace A assigned to rep1.
-- -----------------------------------------------------------------
do $$
declare
  v_workspace_a uuid := (select id from test_fixture_ids where key = 'workspace_a');
  v_status_id uuid := (select id from lead_statuses where workspace_id = v_workspace_a and is_default limit 1);
  v_rep1_member uuid := (select id from workspace_members where workspace_id = v_workspace_a and profile_id = (select id from test_fixture_ids where key = 'user_a_rep1'));
  v_manager_member uuid := (select id from workspace_members where workspace_id = v_workspace_a and profile_id = (select id from test_fixture_ids where key = 'user_a_manager'));
  v_lead_id uuid;
begin
  perform pg_temp.login_as((select id from test_fixture_ids where key = 'user_a_manager'));

  insert into leads (workspace_id, name, phone, status_id, assigned_member_id, created_by_member_id)
  values (v_workspace_a, 'Rep1''s Lead', '+10000000001', v_status_id, v_rep1_member, v_manager_member)
  returning id into v_lead_id;

  reset role;
  insert into test_fixture_ids values ('lead_rep1', v_lead_id);
end $$;

-- -----------------------------------------------------------------
-- 1. WORKSPACE ISOLATION
-- -----------------------------------------------------------------
do $$
declare
  v_workspace_a uuid := (select id from test_fixture_ids where key = 'workspace_a');
  v_count int;
begin
  perform pg_temp.login_as((select id from test_fixture_ids where key = 'user_b_admin'));

  select count(*) into v_count from leads where workspace_id = v_workspace_a;
  perform pg_temp.assert(v_count = 0, 'Workspace B admin cannot SELECT Workspace A leads');

  select count(*) into v_count from workspaces where id = v_workspace_a;
  perform pg_temp.assert(v_count = 0, 'Workspace B admin cannot SELECT the Workspace A workspace row');

  reset role;
end $$;

do $$
declare
  v_workspace_a uuid := (select id from test_fixture_ids where key = 'workspace_a');
  v_status_id uuid := (select id from lead_statuses where workspace_id = v_workspace_a and is_default limit 1);
  v_failed boolean := false;
begin
  perform pg_temp.login_as((select id from test_fixture_ids where key = 'user_b_admin'));

  begin
    insert into leads (workspace_id, name, status_id) values (v_workspace_a, 'Injected Lead', v_status_id);
  exception when others then
    v_failed := true;
  end;

  perform pg_temp.assert(v_failed, 'Workspace B admin cannot INSERT into Workspace A leads');
  reset role;
end $$;

do $$
declare
  v_lead_rep1 uuid := (select id from test_fixture_ids where key = 'lead_rep1');
  v_updated int;
begin
  perform pg_temp.login_as((select id from test_fixture_ids where key = 'user_b_admin'));

  update leads set name = 'Hijacked' where id = v_lead_rep1;
  get diagnostics v_updated = row_count;
  perform pg_temp.assert(v_updated = 0, 'Workspace B admin cannot UPDATE a Workspace A lead (RLS filters it out of the update target)');

  delete from leads where id = v_lead_rep1;
  get diagnostics v_updated = row_count;
  perform pg_temp.assert(v_updated = 0, 'Workspace B admin cannot DELETE a Workspace A lead');

  reset role;
end $$;

-- -----------------------------------------------------------------
-- 2. USER ISOLATION (team_mate cannot see a teammate's own leads)
-- -----------------------------------------------------------------
do $$
declare
  v_count int;
begin
  perform pg_temp.login_as((select id from test_fixture_ids where key = 'user_a_rep2'));

  select count(*) into v_count
  from leads
  where id = (select id from test_fixture_ids where key = 'lead_rep1');

  perform pg_temp.assert(v_count = 0, 'rep2 (team_mate) cannot see a lead assigned to rep1');
  reset role;
end $$;

-- -----------------------------------------------------------------
-- 3. MANAGER ACCESS (manager sees all workspace leads, including rep1's)
-- -----------------------------------------------------------------
do $$
declare
  v_count int;
begin
  perform pg_temp.login_as((select id from test_fixture_ids where key = 'user_a_manager'));

  select count(*) into v_count
  from leads
  where id = (select id from test_fixture_ids where key = 'lead_rep1');

  perform pg_temp.assert(v_count = 1, 'manager can see a lead assigned to a rep in the same workspace');
  reset role;
end $$;

-- -----------------------------------------------------------------
-- 4. ADMIN ACCESS (admin can read the audit log; a rep cannot)
-- -----------------------------------------------------------------
do $$
declare
  v_count int;
begin
  perform pg_temp.login_as((select id from test_fixture_ids where key = 'user_a_admin'));
  select count(*) into v_count from audit_logs where workspace_id = (select id from test_fixture_ids where key = 'workspace_a');
  perform pg_temp.assert(v_count > 0, 'admin can read the Workspace A audit log and it contains entries from the fixture setup above');
  reset role;

  perform pg_temp.login_as((select id from test_fixture_ids where key = 'user_a_rep1'));
  select count(*) into v_count from audit_logs where workspace_id = (select id from test_fixture_ids where key = 'workspace_a');
  perform pg_temp.assert(v_count = 0, 'team_mate cannot read the audit log (no audit.read permission)');
  reset role;
end $$;

-- -----------------------------------------------------------------
-- 5. PERMISSION DENIAL (leads.update / leads.assign)
-- -----------------------------------------------------------------
do $$
declare
  v_lead_rep1 uuid := (select id from test_fixture_ids where key = 'lead_rep1');
  v_updated int;
begin
  -- rep1 owns this lead and has leads.update by role -> should succeed.
  perform pg_temp.login_as((select id from test_fixture_ids where key = 'user_a_rep1'));
  update leads set city = 'Updated By Owner' where id = v_lead_rep1;
  get diagnostics v_updated = row_count;
  perform pg_temp.assert(v_updated = 1, 'rep1 (owner, has leads.update) can update their own assigned lead');
  reset role;
end $$;

do $$
declare
  v_lead_rep1 uuid := (select id from test_fixture_ids where key = 'lead_rep1');
  v_updated int;
begin
  -- rep2 does not own this lead -> update target filtered to zero rows.
  perform pg_temp.login_as((select id from test_fixture_ids where key = 'user_a_rep2'));
  update leads set city = 'Hijacked By rep2' where id = v_lead_rep1;
  get diagnostics v_updated = row_count;
  perform pg_temp.assert(v_updated = 0, 'rep2 cannot update a lead assigned to rep1 (leads.update permission present, but ownership check fails)');
  reset role;
end $$;

do $$
declare
  v_workspace_a uuid := (select id from test_fixture_ids where key = 'workspace_a');
  v_lead_rep1 uuid := (select id from test_fixture_ids where key = 'lead_rep1');
  v_deleted int;
begin
  -- rep1 has NOT been granted leads.delete by role (only manager+ has it
  -- by default) -> delete should affect 0 rows even on their own lead.
  perform pg_temp.login_as((select id from test_fixture_ids where key = 'user_a_rep1'));
  delete from leads where id = v_lead_rep1;
  get diagnostics v_deleted = row_count;
  perform pg_temp.assert(v_deleted = 0, 'rep1 cannot delete a lead (leads.delete not granted to team_mate by default)');
  reset role;
end $$;

-- Grant rep1 a leads.delete override, verify it now works.
do $$
declare
  v_workspace_a uuid := (select id from test_fixture_ids where key = 'workspace_a');
  v_rep1_member uuid := (select id from workspace_members where workspace_id = v_workspace_a and profile_id = (select id from test_fixture_ids where key = 'user_a_rep1'));
  v_delete_perm uuid := (select id from permissions where code = 'leads.delete');
  v_lead_rep1 uuid := (select id from test_fixture_ids where key = 'lead_rep1');
  v_deleted int;
begin
  insert into rep_permissions (workspace_id, workspace_member_id, permission_id, granted)
  values (v_workspace_a, v_rep1_member, v_delete_perm, true);

  perform pg_temp.login_as((select id from test_fixture_ids where key = 'user_a_rep1'));
  delete from leads where id = v_lead_rep1;
  get diagnostics v_deleted = row_count;
  perform pg_temp.assert(v_deleted = 1, 'rep1 CAN delete their own lead after an explicit rep_permissions grant override');
  reset role;
end $$;

-- -----------------------------------------------------------------
-- 6. CROSS-WORKSPACE REFERENCES (database constraint, not RLS)
-- -----------------------------------------------------------------
do $$
declare
  v_workspace_a uuid := (select id from test_fixture_ids where key = 'workspace_a');
  v_workspace_b uuid := (select id from test_fixture_ids where key = 'workspace_b');
  v_status_a uuid := (select id from lead_statuses where workspace_id = v_workspace_a and is_default limit 1);
  v_tag_b uuid;
  v_lead_a uuid;
  v_failed boolean := false;
begin
  insert into tags (workspace_id, name) values (v_workspace_b, 'cross-workspace-tag') returning id into v_tag_b;
  insert into leads (workspace_id, name, status_id) values (v_workspace_a, 'Cross-ref test lead', v_status_a) returning id into v_lead_a;

  begin
    insert into lead_tags (workspace_id, lead_id, tag_id) values (v_workspace_a, v_lead_a, v_tag_b);
  exception when foreign_key_violation then
    v_failed := true;
  end;

  perform pg_temp.assert(v_failed, 'A Workspace A lead cannot reference a Workspace B tag (composite FK rejects it at the database level)');
end $$;

do $$
declare
  v_workspace_a uuid := (select id from test_fixture_ids where key = 'workspace_a');
  v_workspace_b uuid := (select id from test_fixture_ids where key = 'workspace_b');
  v_status_a uuid := (select id from lead_statuses where workspace_id = v_workspace_a and is_default limit 1);
  v_member_b uuid := (select id from workspace_members where workspace_id = v_workspace_b limit 1);
  v_lead_a uuid;
  v_failed boolean := false;
begin
  insert into leads (workspace_id, name, status_id) values (v_workspace_a, 'Cross-ref call test lead', v_status_a) returning id into v_lead_a;

  begin
    insert into calls (workspace_id, lead_id, agent_member_id, direction, state)
    values (v_workspace_a, v_lead_a, v_member_b, 'outbound', 'ENDED');
  exception when foreign_key_violation then
    v_failed := true;
  end;

  perform pg_temp.assert(v_failed, 'A Workspace A call cannot reference a Workspace B member (composite FK rejects it)');
end $$;

do $$
declare
  v_workspace_a uuid := (select id from test_fixture_ids where key = 'workspace_a');
  v_workspace_b uuid := (select id from test_fixture_ids where key = 'workspace_b');
  v_status_a uuid := (select id from lead_statuses where workspace_id = v_workspace_a and is_default limit 1);
  v_member_a uuid := (select id from workspace_members where workspace_id = v_workspace_a and profile_id = (select id from test_fixture_ids where key = 'user_a_manager'));
  v_member_b uuid := (select id from workspace_members where workspace_id = v_workspace_b limit 1);
  v_lead_a uuid;
  v_failed boolean := false;
begin
  insert into leads (workspace_id, name, status_id) values (v_workspace_a, 'Cross-ref allocation test lead', v_status_a) returning id into v_lead_a;

  begin
    insert into allocations (workspace_id, lead_id, assigned_member_id, assigned_by_member_id)
    values (v_workspace_a, v_lead_a, v_member_b, v_member_a);
  exception when foreign_key_violation then
    v_failed := true;
  end;

  perform pg_temp.assert(v_failed, 'A Workspace A allocation cannot reference a Workspace B member (composite FK rejects it)');
end $$;

-- -----------------------------------------------------------------
-- 7. STORAGE ACCESS
-- -----------------------------------------------------------------
do $$
declare
  v_workspace_a uuid := (select id from test_fixture_ids where key = 'workspace_a');
  v_workspace_b uuid := (select id from test_fixture_ids where key = 'workspace_b');
  v_failed boolean := false;
  v_count int;
begin
  -- Workspace A admin uploads a file under the Workspace A path -> allowed.
  perform pg_temp.login_as((select id from test_fixture_ids where key = 'user_a_admin'));
  insert into storage.objects (bucket_id, name, owner)
  values ('lead-documents', v_workspace_a::text || '/some-lead-id/contract.pdf', (select id from test_fixture_ids where key = 'user_a_admin'));
  reset role;

  -- Workspace B admin tries to read it -> should see nothing.
  perform pg_temp.login_as((select id from test_fixture_ids where key = 'user_b_admin'));
  select count(*) into v_count from storage.objects where bucket_id = 'lead-documents' and name like v_workspace_a::text || '/%';
  perform pg_temp.assert(v_count = 0, 'Workspace B admin cannot SELECT a Workspace A document from Storage');

  -- Workspace B admin tries to upload under Workspace A''s path -> rejected.
  begin
    insert into storage.objects (bucket_id, name, owner)
    values ('lead-documents', v_workspace_a::text || '/some-lead-id/injected.pdf', (select id from test_fixture_ids where key = 'user_b_admin'));
  exception when others then
    v_failed := true;
  end;
  perform pg_temp.assert(v_failed, 'Workspace B admin cannot INSERT a Storage object under Workspace A''s path');
  reset role;

  -- A rep without documents.delete cannot delete the admin''s upload.
  perform pg_temp.login_as((select id from test_fixture_ids where key = 'user_a_rep1'));
  delete from storage.objects where bucket_id = 'lead-documents' and name = v_workspace_a::text || '/some-lead-id/contract.pdf';
  get diagnostics v_count = row_count;
  perform pg_temp.assert(v_count = 0, 'team_mate without documents.delete cannot delete a Workspace A document');
  reset role;
end $$;

-- -----------------------------------------------------------------
-- 8. LEAD ASSIGNMENT PERMISSION (Phase 6 —
--    enforce_lead_assignment_permission trigger, 000017)
-- -----------------------------------------------------------------
do $$
declare
  v_workspace_a uuid := (select id from test_fixture_ids where key = 'workspace_a');
  v_lead_rep1 uuid := (select id from test_fixture_ids where key = 'lead_rep1');
  v_rep2_member uuid := (select id from workspace_members where workspace_id = v_workspace_a and profile_id = (select id from test_fixture_ids where key = 'user_a_rep2'));
  v_failed boolean := false;
begin
  -- rep1 owns this lead and has leads.update by role, but NOT
  -- leads.assign (team_mate isn't granted it — 000013_reference_data.sql).
  -- Before 000017's trigger, leads_update RLS alone would have allowed
  -- this (ownership + leads.update is all it checks); the trigger adds
  -- the missing leads.assign gate specifically for this column.
  perform pg_temp.login_as((select id from test_fixture_ids where key = 'user_a_rep1'));

  begin
    update leads set assigned_member_id = v_rep2_member where id = v_lead_rep1;
  exception when insufficient_privilege then
    v_failed := true;
  end;

  perform pg_temp.assert(v_failed, 'rep1 (owner, has leads.update but not leads.assign) cannot reassign their own lead — enforce_lead_assignment_permission trigger blocks it');
  reset role;
end $$;

do $$
declare
  v_workspace_a uuid := (select id from test_fixture_ids where key = 'workspace_a');
  v_lead_rep1 uuid := (select id from test_fixture_ids where key = 'lead_rep1');
  v_rep2_member uuid := (select id from workspace_members where workspace_id = v_workspace_a and profile_id = (select id from test_fixture_ids where key = 'user_a_rep2'));
  v_updated int;
begin
  -- manager has leads.assign (granted by role) -> reassignment succeeds.
  perform pg_temp.login_as((select id from test_fixture_ids where key = 'user_a_manager'));

  update leads set assigned_member_id = v_rep2_member where id = v_lead_rep1;
  get diagnostics v_updated = row_count;
  perform pg_temp.assert(v_updated = 1, 'manager (has leads.assign) CAN reassign a lead');

  -- Unassign (set to null) is also gated the same way, and still
  -- succeeds for a manager.
  update leads set assigned_member_id = null where id = v_lead_rep1;
  get diagnostics v_updated = row_count;
  perform pg_temp.assert(v_updated = 1, 'manager (has leads.assign) CAN unassign a lead (assigned_member_id = null)');

  reset role;
end $$;

do $$
declare
  v_lead_rep1 uuid := (select id from test_fixture_ids where key = 'lead_rep1');
  v_updated int;
begin
  -- Changing an unrelated column is unaffected by the new trigger —
  -- still governed purely by leads_update (ownership + leads.update).
  perform pg_temp.login_as((select id from test_fixture_ids where key = 'user_a_manager'));

  update leads set priority = 'high' where id = v_lead_rep1;
  get diagnostics v_updated = row_count;
  perform pg_temp.assert(v_updated = 1, 'updating a non-assignment field is unaffected by the leads.assign trigger');

  reset role;
end $$;

raise notice '=================================================';
raise notice 'ALL RLS / DATABASE SECURITY TESTS PASSED';
raise notice '=================================================';

rollback;
