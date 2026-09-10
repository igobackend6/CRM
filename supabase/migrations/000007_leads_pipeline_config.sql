-- Workspace-configurable lookup tables. These are records (not hardcoded
-- enums) because the Admin app is expected to let a workspace manage its
-- own pipeline stages, lead sources and call outcomes (see
-- docs/architecture/database.md "Configurable vs. Hardcoded" for the
-- criteria used to decide this per entity). Every workspace gets a
-- sensible default set automatically — see provision_default_workspace_data()
-- in 000012_security_functions.sql — so nothing here needs manual seeding.

create table lead_statuses (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces (id) on delete cascade,
  name text not null,
  code text not null,
  sort_order integer not null default 0,
  is_won boolean not null default false,
  is_lost boolean not null default false,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  unique (workspace_id, id),
  unique (workspace_id, code)
);

comment on table lead_statuses is 'Workspace-configurable pipeline stages for leads.';

create table lead_sources (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces (id) on delete cascade,
  name text not null,
  code text not null,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  unique (workspace_id, id),
  unique (workspace_id, code)
);

comment on table lead_sources is 'Workspace-configurable lead origin catalogue (referral, website, cold_call, ...).';

create table call_outcomes (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces (id) on delete cascade,
  name text not null,
  code text not null,
  is_positive boolean not null default false,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  unique (workspace_id, id),
  unique (workspace_id, code)
);

comment on table call_outcomes is 'Workspace-configurable call result catalogue (connected, no_answer, interested, ...).';

create table tags (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces (id) on delete cascade,
  name text not null,
  color text,
  created_at timestamptz not null default now(),
  unique (workspace_id, id),
  unique (workspace_id, name)
);

comment on table tags is 'Workspace-scoped, freeform label catalogue applied to leads.';

create index lead_statuses_workspace_id_idx on lead_statuses (workspace_id);
create index lead_sources_workspace_id_idx on lead_sources (workspace_id);
create index call_outcomes_workspace_id_idx on call_outcomes (workspace_id);
create index tags_workspace_id_idx on tags (workspace_id);

alter table lead_statuses enable row level security;
alter table lead_sources enable row level security;
alter table call_outcomes enable row level security;
alter table tags enable row level security;
