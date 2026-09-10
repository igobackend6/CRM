-- workspace_members is THE tenant boundary table: it is what "belonging to
-- a workspace" actually means, and every other workspace-scoped table's
-- "who owns/is-assigned-to this row" columns point here (not directly at
-- profiles), so that a cross-workspace assignment is structurally
-- impossible to represent, not just RLS-blocked. See
-- docs/architecture/database.md "Composite Foreign Key Pattern".

create table workspace_members (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces (id) on delete cascade,
  profile_id uuid not null references profiles (id) on delete restrict,
  role_id uuid not null references roles (id) on delete restrict,
  status text not null default 'active' check (status in ('active', 'invited', 'suspended', 'removed')),
  invited_by uuid references profiles (id) on delete set null,
  joined_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (workspace_id, id),
  unique (workspace_id, profile_id)
);

comment on table workspace_members is
  'Tenant membership: a profile''s participation in a workspace, with a role. Deactivate via status = ''removed'' rather than deleting the row, to preserve historical foreign-key references (calls, allocations, audit_logs, ...).';
comment on column workspace_members.status is
  'active = normal; invited = provisioned but not yet accepted; suspended = temporarily blocked; removed = soft-removed, preserved for history.';

create index workspace_members_workspace_id_idx on workspace_members (workspace_id);
create index workspace_members_profile_id_idx on workspace_members (profile_id);
create index workspace_members_workspace_status_idx on workspace_members (workspace_id, status);

create trigger workspace_members_set_updated_at
  before update on workspace_members
  for each row
  execute function set_updated_at();

alter table workspace_members enable row level security;

-- Per-user, per-workspace permission overrides layered on top of the
-- member's role. granted = true widens access beyond the role baseline;
-- granted = false narrows it (an explicit revoke). Scoped to a specific
-- workspace_members row (not profile_id directly) so an override in one
-- workspace never leaks into another workspace the same person belongs to.
create table rep_permissions (
  id uuid not null default gen_random_uuid(),
  workspace_id uuid not null references workspaces (id) on delete cascade,
  workspace_member_id uuid not null,
  permission_id uuid not null references permissions (id) on delete cascade,
  granted boolean not null,
  granted_by uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (workspace_member_id, permission_id),

  constraint rep_permissions_member_fk
    foreign key (workspace_id, workspace_member_id) references workspace_members (workspace_id, id) on delete cascade
);

comment on table rep_permissions is
  'Per-membership permission overrides on top of the role baseline (role_permissions). granted=true grants beyond the role; granted=false revokes a role-granted permission for this member specifically. workspace_id is denormalized from the member row (enforced by the composite FK) so audit logging and RLS don''t need an extra join. The natural key (workspace_member_id, permission_id) is the primary key; id is a surrogate carried only so the generic log_audit_event() trigger (which reads NEW.id/OLD.id) works uniformly across every audited table.';

create unique index rep_permissions_id_idx on rep_permissions (id);

create index rep_permissions_workspace_idx on rep_permissions (workspace_id);

alter table rep_permissions enable row level security;
