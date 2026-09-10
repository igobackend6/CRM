-- The tenant root. Every workspace-scoped table carries a workspace_id
-- that ultimately traces back here. RLS policies are added in
-- 000014_rls_policies.sql, after all tables and helper functions exist;
-- RLS is enabled immediately below so the table defaults to closed
-- (no policies yet = no access) rather than briefly open.

create table workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  status text not null default 'active' check (status in ('active', 'suspended', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table workspaces is 'Tenant root. One row per company/organization using the CRM.';
comment on column workspaces.slug is 'URL/identifier-safe unique handle for the workspace.';

create trigger workspaces_set_updated_at
  before update on workspaces
  for each row
  execute function set_updated_at();

alter table workspaces enable row level security;
