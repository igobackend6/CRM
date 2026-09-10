-- Phase 4 (Admin/App alignment cycle) — FCM device token registry.
--
-- Push-on-assignment: the in-app notification (the `notifications` row +
-- Realtime badge) already lands via the on_lead_assignment trigger
-- (000027). This adds the OS-level push so a rep is pinged when the app
-- is backgrounded or closed.
--
-- A device token belongs to a PROFILE, not a workspace membership — one
-- phone, one FCM token, regardless of how many workspaces the user is in.
-- `PushService.send_to_member(workspace_id, member_id)` resolves
-- member -> workspace_members.profile_id -> every device_tokens row for
-- that profile. So this table is user infrastructure (like `profiles`),
-- not workspace-scoped, and its RLS is a plain "your own rows" check.
--
-- No explicit service_role grant needed: 000029's ALTER DEFAULT
-- PRIVILEGES already covers tables created after it.

create table device_tokens (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles (id) on delete cascade,

  token text not null,
  platform text not null check (platform in ('android', 'ios', 'web')),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- One row per physical device: the same FCM token is re-registered
  -- (last_seen bump) rather than duplicated. A token can migrate between
  -- profiles (shared device, re-login) — the unique is on token alone.
  unique (token)
);

comment on table device_tokens is
  'FCM registration tokens per profile. Written by the mobile app on login / token refresh, deleted on logout. Read only by the backend (service_role) when dispatching a push.';

create index device_tokens_profile_idx on device_tokens (profile_id);

create trigger device_tokens_set_updated_at
  before update on device_tokens
  for each row
  execute function set_updated_at();

alter table device_tokens enable row level security;

grant select, insert, update, delete on device_tokens to authenticated;

-- A user sees and manages only their own device's tokens. The backend
-- reads across profiles via service_role (bypasses RLS).
create policy device_tokens_select on device_tokens
  for select to authenticated
  using (profile_id = auth.uid());

create policy device_tokens_insert on device_tokens
  for insert to authenticated
  with check (profile_id = auth.uid());

create policy device_tokens_update on device_tokens
  for update to authenticated
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

create policy device_tokens_delete on device_tokens
  for delete to authenticated
  using (profile_id = auth.uid());
