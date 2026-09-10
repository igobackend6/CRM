-- Call and follow-up history. Both are treated as append-mostly records
-- (see docs/architecture/database.md "Soft Delete Strategy" — neither
-- gets a deleted_at column; there is no DELETE RLS policy for either,
-- so history can't be erased from the client at all). duration_seconds
-- is derived, not app-supplied, so it can never disagree with the
-- timestamps that produced it.

create table calls (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces (id) on delete cascade,
  lead_id uuid not null,
  agent_member_id uuid not null,

  direction text not null check (direction in ('inbound', 'outbound')),
  state text not null check (
    state in ('IDLE', 'DIALING', 'RINGING', 'CONNECTED', 'ENDED', 'FAILED', 'MISSED', 'CANCELLED')
  ),
  outcome_id uuid,

  started_at timestamptz not null default now(),
  connected_at timestamptz,
  ended_at timestamptz,
  duration_seconds integer generated always as (
    case
      when connected_at is not null and ended_at is not null
        then greatest(extract(epoch from (ended_at - connected_at))::integer, 0)
      else null
    end
  ) stored,

  notes text,
  created_at timestamptz not null default now(),

  constraint calls_lead_fk
    foreign key (workspace_id, lead_id) references leads (workspace_id, id) on delete cascade,
  constraint calls_agent_member_fk
    foreign key (workspace_id, agent_member_id) references workspace_members (workspace_id, id) on delete restrict,
  constraint calls_outcome_fk
    foreign key (workspace_id, outcome_id) references call_outcomes (workspace_id, id) on delete set null
);

comment on table calls is
  'One row per call attempt. state mirrors the native calling state machine (docs/architecture/06-calling-architecture.md). Recording metadata is deferred to Phase 21 — see docs/architecture/database.md "Deferred Entities".';

create index calls_workspace_lead_idx on calls (workspace_id, lead_id, started_at desc);
create index calls_workspace_agent_idx on calls (workspace_id, agent_member_id, started_at desc);

alter table calls enable row level security;

create table follow_ups (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces (id) on delete cascade,
  lead_id uuid not null,
  assigned_member_id uuid not null,
  created_by_member_id uuid,

  type text not null check (type in ('call', 'meeting', 'task')),
  due_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending', 'completed', 'cancelled')),
  notes text,

  completed_at timestamptz,
  cancelled_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint follow_ups_lead_fk
    foreign key (workspace_id, lead_id) references leads (workspace_id, id) on delete cascade,
  constraint follow_ups_assigned_member_fk
    foreign key (workspace_id, assigned_member_id) references workspace_members (workspace_id, id) on delete restrict,
  constraint follow_ups_created_by_member_fk
    foreign key (workspace_id, created_by_member_id) references workspace_members (workspace_id, id) on delete set null
);

comment on table follow_ups is
  'Scheduled follow-up actions. "Overdue" is intentionally not a stored status — it is derived at query time as (status = ''pending'' and due_at < now()), so it can never drift out of sync with the clock.';

create index follow_ups_workspace_assigned_due_idx on follow_ups (workspace_id, assigned_member_id, due_at);
create index follow_ups_workspace_lead_idx on follow_ups (workspace_id, lead_id);

create trigger follow_ups_set_updated_at
  before update on follow_ups
  for each row
  execute function set_updated_at();

alter table follow_ups enable row level security;
