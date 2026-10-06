-- Agent activity (Login Analytics): login sessions, breaks, and a stored
-- per-day rollup.
--
-- What Runo calls "Login Duration / Wrap up / Break / Idle / Talk time"
-- has three inputs the schema did not record until now:
--   * agent_sessions        - how long a member had the app signed in
--                             (foreground OR background — the app sends a
--                             heartbeat while its process is alive)
--   * agent_breaks          - explicit "Take a break" intervals
--   * agent_daily_activity  - the computed per-day totals, stored so the
--                             admin panel can simply SELECT them
-- Talk time comes from `calls` (duration_seconds) and wrap-up is derived
-- from `calls.ended_at`, so neither needs a table of its own. The maths
-- lives in the backend (backend/app/services/activity), which recomputes
-- and upserts today's agent_daily_activity row as the app reports in.
--
-- Same access rule as `calls`: a member reads and writes their OWN rows;
-- manager-or-above can read everyone's in the workspace (that is what the
-- admin panel uses). Nobody can delete: like calls, this is history.
--
-- No explicit service_role grant needed: 000029's ALTER DEFAULT
-- PRIVILEGES covers tables created after it.

-- ---------------------------------------------------------------------
-- agent_sessions: one row per continuous login span.
--   started_at   when the span began
--   last_seen_at bumped by every heartbeat (~1/min while the app is alive)
--   ended_at     set on sign-out, or by the backend when it notices the
--                heartbeats stopped (then ended_at = last_seen_at)
-- ---------------------------------------------------------------------
create table agent_sessions (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces (id) on delete cascade,
  member_id uuid not null,

  started_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  ended_at timestamptz,
  created_at timestamptz not null default now(),

  constraint agent_sessions_member_fk
    foreign key (workspace_id, member_id) references workspace_members (workspace_id, id) on delete cascade,
  constraint agent_sessions_span_chk
    check (last_seen_at >= started_at and (ended_at is null or ended_at >= started_at))
);

comment on table agent_sessions is
  'One row per continuous app login span for a workspace member. Written by the mobile app (via the backend) as heartbeats; login duration = sum of (coalesce(ended_at, last_seen_at) - started_at).';

create index agent_sessions_member_started_idx on agent_sessions (workspace_id, member_id, started_at desc);

-- At most one open session per member: a second device / a retry cannot
-- create a duplicate that double-counts the same time.
create unique index agent_sessions_one_open_idx
  on agent_sessions (workspace_id, member_id)
  where ended_at is null;

-- ---------------------------------------------------------------------
-- agent_breaks: explicit break intervals ("Take a break" / "End break").
-- ---------------------------------------------------------------------
create table agent_breaks (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces (id) on delete cascade,
  member_id uuid not null,

  started_at timestamptz not null default now(),
  ended_at timestamptz,
  created_at timestamptz not null default now(),

  constraint agent_breaks_member_fk
    foreign key (workspace_id, member_id) references workspace_members (workspace_id, id) on delete cascade,
  constraint agent_breaks_span_chk
    check (ended_at is null or ended_at >= started_at)
);

comment on table agent_breaks is
  'Break intervals a member started/ended in the app. An open break (ended_at null) is closed by the backend on sign-out or when the session times out.';

create index agent_breaks_member_started_idx on agent_breaks (workspace_id, member_id, started_at desc);

create unique index agent_breaks_one_open_idx
  on agent_breaks (workspace_id, member_id)
  where ended_at is null;

-- ---------------------------------------------------------------------
-- agent_daily_activity: the stored per-day totals (all in seconds).
--   day                 the member's LOCAL calendar day
--   utc_offset_minutes  the offset that day boundary was computed with
--                       (the schema stores no per-user timezone, so the
--                       app sends its offset with each heartbeat)
-- Recomputed from the raw rows by the backend; safe to recompute at any
-- time. login = talk + wrap_up + break + idle (+ time spent ringing).
-- ---------------------------------------------------------------------
create table agent_daily_activity (
  workspace_id uuid not null references workspaces (id) on delete cascade,
  member_id uuid not null,
  day date not null,

  utc_offset_minutes integer not null default 0 check (utc_offset_minutes between -840 and 840),
  login_seconds integer not null default 0 check (login_seconds >= 0),
  talk_seconds integer not null default 0 check (talk_seconds >= 0),
  wrap_up_seconds integer not null default 0 check (wrap_up_seconds >= 0),
  break_seconds integer not null default 0 check (break_seconds >= 0),
  idle_seconds integer not null default 0 check (idle_seconds >= 0),

  updated_at timestamptz not null default now(),

  primary key (workspace_id, member_id, day),
  constraint agent_daily_activity_member_fk
    foreign key (workspace_id, member_id) references workspace_members (workspace_id, id) on delete cascade
);

comment on table agent_daily_activity is
  'Per-member per-local-day login / talk / wrap-up / break / idle seconds. Read directly by the admin panel; written by the backend.';

create index agent_daily_activity_day_idx on agent_daily_activity (workspace_id, day desc);

create trigger agent_daily_activity_set_updated_at
  before update on agent_daily_activity
  for each row
  execute function set_updated_at();

-- ---------------------------------------------------------------------
-- RLS — own rows, or everything for manager-or-above. No DELETE policy.
-- ---------------------------------------------------------------------
alter table agent_sessions enable row level security;
alter table agent_breaks enable row level security;
alter table agent_daily_activity enable row level security;

grant select, insert, update on agent_sessions to authenticated;
grant select, insert, update on agent_breaks to authenticated;
grant select, insert, update on agent_daily_activity to authenticated;

create policy agent_sessions_select on agent_sessions
  for select to authenticated
  using (
    is_workspace_member(workspace_id)
    and (is_manager_or_above(workspace_id) or member_id = current_member_id(workspace_id))
  );

create policy agent_sessions_insert on agent_sessions
  for insert to authenticated
  with check (is_workspace_member(workspace_id) and member_id = current_member_id(workspace_id));

create policy agent_sessions_update on agent_sessions
  for update to authenticated
  using (is_workspace_member(workspace_id) and member_id = current_member_id(workspace_id))
  with check (is_workspace_member(workspace_id) and member_id = current_member_id(workspace_id));

create policy agent_breaks_select on agent_breaks
  for select to authenticated
  using (
    is_workspace_member(workspace_id)
    and (is_manager_or_above(workspace_id) or member_id = current_member_id(workspace_id))
  );

create policy agent_breaks_insert on agent_breaks
  for insert to authenticated
  with check (is_workspace_member(workspace_id) and member_id = current_member_id(workspace_id));

create policy agent_breaks_update on agent_breaks
  for update to authenticated
  using (is_workspace_member(workspace_id) and member_id = current_member_id(workspace_id))
  with check (is_workspace_member(workspace_id) and member_id = current_member_id(workspace_id));

create policy agent_daily_activity_select on agent_daily_activity
  for select to authenticated
  using (
    is_workspace_member(workspace_id)
    and (is_manager_or_above(workspace_id) or member_id = current_member_id(workspace_id))
  );

create policy agent_daily_activity_insert on agent_daily_activity
  for insert to authenticated
  with check (is_workspace_member(workspace_id) and member_id = current_member_id(workspace_id));

create policy agent_daily_activity_update on agent_daily_activity
  for update to authenticated
  using (is_workspace_member(workspace_id) and member_id = current_member_id(workspace_id))
  with check (is_workspace_member(workspace_id) and member_id = current_member_id(workspace_id));
