-- allocations is the assignment *event* history (manager/admin allocates
-- a lead to a rep, tracked new -> pending -> actioned). leads.assigned_member_id
-- remains the fast, current-owner pointer used by everyday queries/RLS —
-- this is a deliberate, documented denormalization (see
-- docs/architecture/database.md "Allocations vs. leads.assigned_member_id"),
-- not accidental duplication: one is history, the other is current state.

create table allocations (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces (id) on delete cascade,
  lead_id uuid not null,
  assigned_member_id uuid not null,
  assigned_by_member_id uuid not null,

  status text not null default 'new' check (status in ('new', 'pending', 'actioned')),
  assigned_at timestamptz not null default now(),
  actioned_at timestamptz,

  created_at timestamptz not null default now(),

  constraint allocations_lead_fk
    foreign key (workspace_id, lead_id) references leads (workspace_id, id) on delete cascade,
  constraint allocations_assigned_member_fk
    foreign key (workspace_id, assigned_member_id) references workspace_members (workspace_id, id) on delete restrict,
  constraint allocations_assigned_by_member_fk
    foreign key (workspace_id, assigned_by_member_id) references workspace_members (workspace_id, id) on delete restrict
);

comment on table allocations is 'Lead assignment/reassignment event history.';

create index allocations_workspace_assigned_idx on allocations (workspace_id, assigned_member_id, status);
create index allocations_workspace_lead_idx on allocations (workspace_id, lead_id);

alter table allocations enable row level security;

-- Unified, append-only Customer 360 timeline. Stores references +
-- lightweight jsonb context, not copies of the related entity's full
-- data (docs/architecture/database.md "Interactions: What Goes In payload").
create table interactions (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces (id) on delete cascade,
  lead_id uuid not null,
  actor_member_id uuid,

  type text not null check (
    type in ('call', 'note', 'status_change', 'document', 'follow_up', 'message', 'allocation')
  ),
  payload jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),

  constraint interactions_lead_fk
    foreign key (workspace_id, lead_id) references leads (workspace_id, id) on delete cascade,
  constraint interactions_actor_member_fk
    foreign key (workspace_id, actor_member_id) references workspace_members (workspace_id, id) on delete set null
);

comment on table interactions is
  'Append-only Customer 360 timeline. type=''note'' entries ARE the notes feature (docs/architecture/database.md "Notes") — there is no separate notes table.';
comment on column interactions.actor_member_id is
  'Null for system-generated entries (e.g. an automated status change).';

create index interactions_workspace_lead_idx on interactions (workspace_id, lead_id, created_at desc);

alter table interactions enable row level security;
