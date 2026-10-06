-- Fixes a regression from 000031_agent_activity.sql.
--
-- agent_daily_activity had a composite primary key (workspace_id, member_id, day)
-- and foreign keys to BOTH workspaces and workspace_members. PostgREST treats a
-- table whose primary key contains the foreign-key columns of two tables as a
-- many-to-many "junction", so every embed of `workspaces(...)` from
-- `workspace_members` (the mobile app's workspace picker, and any admin-panel
-- query shaped the same way) became ambiguous and failed with PGRST201
-- ("more than one relationship was found for 'workspace_members' and 'workspaces'").
--
-- A surrogate primary key removes the junction shape. The natural key stays
-- enforced (and is still the upsert conflict target) as a unique constraint.
-- Only agent_sessions / agent_breaks already had a surrogate `id`, which is why
-- they never triggered this.

alter table agent_daily_activity drop constraint agent_daily_activity_pkey;

alter table agent_daily_activity add column id uuid not null default gen_random_uuid();
alter table agent_daily_activity add constraint agent_daily_activity_pkey primary key (id);

alter table agent_daily_activity
  add constraint agent_daily_activity_member_day_key unique (workspace_id, member_id, day);

-- Make PostgREST re-read the schema right away instead of on its next refresh.
notify pgrst, 'reload schema';
