-- Global RBAC catalog. `roles` and `permissions` are NOT workspace-scoped
-- in Phase 2 — they are a fixed, system-managed catalog shared by every
-- workspace (see docs/architecture/rbac.md for the rationale and the
-- forward-compatible path to per-workspace custom roles later).

create table roles (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  is_system boolean not null default true,
  created_at timestamptz not null default now()
);

comment on table roles is
  'Global role catalog (team_mate, manager, admin, ceo). Managed via migrations only in Phase 2 — no client-facing role management yet.';

create table permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  category text not null,
  description text not null,
  created_at timestamptz not null default now()
);

comment on table permissions is
  'Global permission catalog. Codes are namespaced as "<resource>.<action>", e.g. leads.create.';

create table role_permissions (
  role_id uuid not null references roles (id) on delete cascade,
  permission_id uuid not null references permissions (id) on delete cascade,
  primary key (role_id, permission_id)
);

comment on table role_permissions is 'Baseline permission grants for each role.';

alter table roles enable row level security;
alter table permissions enable row level security;
alter table role_permissions enable row level security;
