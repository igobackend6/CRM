-- notifications is a strictly personal inbox (see rls policies) —
-- notification "type" is a small, code-controlled set, not something a
-- workspace admin configures, so it's a CHECK constraint rather than a
-- notification_types lookup table (docs/architecture/database.md
-- "Configurable vs. Hardcoded").

create table notifications (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces (id) on delete cascade,
  recipient_member_id uuid not null,

  type text not null check (
    type in ('lead_assigned', 'followup_reminder', 'followup_overdue', 'lead_reassigned', 'system')
  ),
  title text not null,
  body text,

  related_entity_type text,
  related_entity_id uuid,

  is_read boolean not null default false,
  read_at timestamptz,

  created_at timestamptz not null default now(),

  constraint notifications_recipient_member_fk
    foreign key (workspace_id, recipient_member_id) references workspace_members (workspace_id, id) on delete cascade
);

comment on table notifications is
  'Per-user notification inbox. related_entity_type/id are an intentionally unconstrained polymorphic reference (no FK possible across varying target tables) — validated by the writer (backend/service-role), not the database.';

create index notifications_recipient_unread_idx on notifications (workspace_id, recipient_member_id, is_read, created_at desc);

alter table notifications enable row level security;

-- Client applications never write directly to notifications (see RLS:
-- no INSERT policy for `authenticated`). Only backend code using the
-- service-role key, or a future SECURITY DEFINER function, creates
-- notification rows. This trigger is a second line of defense: even a
-- service-role write can only ever toggle is_read/read_at once the row
-- exists in the hands of a client that somehow gained UPDATE access.
create or replace function prevent_notification_content_edit()
returns trigger
language plpgsql
as $$
begin
  if new.title is distinct from old.title
    or new.body is distinct from old.body
    or new.type is distinct from old.type
    or new.workspace_id is distinct from old.workspace_id
    or new.recipient_member_id is distinct from old.recipient_member_id
  then
    raise exception 'Only is_read/read_at may be updated on notifications';
  end if;
  return new;
end;
$$;

create trigger notifications_protect_content
  before update on notifications
  for each row
  execute function prevent_notification_content_edit();

-- Immutable mutation trail. Insert-only from the client's perspective —
-- see 000014_rls_policies.sql (no INSERT/UPDATE/DELETE policy for
-- `authenticated`; rows are written exclusively by SECURITY DEFINER
-- audit trigger functions, defined in 000012_security_functions.sql).
create table audit_logs (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces (id) on delete cascade,
  actor_member_id uuid,

  action text not null,
  entity_type text not null,
  entity_id uuid not null,

  before jsonb,
  after jsonb,

  created_at timestamptz not null default now(),

  constraint audit_logs_actor_member_fk
    foreign key (workspace_id, actor_member_id) references workspace_members (workspace_id, id) on delete set null
);

comment on table audit_logs is
  'Immutable mutation trail for sensitive tables (leads, allocations, follow_ups, calls, workspace_members, rep_permissions). entity_id is intentionally not a real FK: entity_type varies per row (polymorphic), and a hard FK could block deleting/archiving old data the audit trail must still describe.';
comment on column audit_logs.actor_member_id is
  'Null when the change was made by the system (a trigger-driven default, a migration, a service-role job) rather than an authenticated member action.';

create index audit_logs_workspace_created_idx on audit_logs (workspace_id, created_at desc);
create index audit_logs_workspace_entity_idx on audit_logs (workspace_id, entity_type, entity_id);

alter table audit_logs enable row level security;
