-- Phase 16 — Internal CRM Messaging & Conversation Foundation.
--
-- Two new tables, minimum viable schema (see the Phase 16 spec's STEP 1/
-- STEP 2): `conversations` is the single internal-messaging thread
-- attached to one lead — not a new chat-user/contact model, since every
-- party who could message already exists as a `workspace_members` row,
-- and not a group/thread system (one conversation per (workspace, lead),
-- enforced below by a unique constraint, not just application logic).
-- `messages` is the append-only message log within a conversation.
--
-- Same composite-workspace-FK pattern as every other workspace-scoped
-- table (docs/architecture/database.md "Composite Foreign Key Pattern"):
-- conversations -> leads via (workspace_id, lead_id), messages ->
-- conversations via (workspace_id, conversation_id) — a cross-workspace
-- reference is structurally impossible, not just RLS-blocked.

create table conversations (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces (id) on delete cascade,
  lead_id uuid not null,
  created_by_member_id uuid not null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (workspace_id, id),
  -- One conversation per lead per workspace (Phase 16 "do NOT allow
  -- duplicate conversations for the same workspace + lead") — enforced
  -- here, not only by the service layer's get-or-create logic.
  unique (workspace_id, lead_id),

  constraint conversations_lead_fk
    foreign key (workspace_id, lead_id) references leads (workspace_id, id) on delete cascade,
  constraint conversations_created_by_member_fk
    foreign key (workspace_id, created_by_member_id) references workspace_members (workspace_id, id) on delete restrict
);

comment on table conversations is
  'One internal-messaging conversation per (workspace_id, lead_id) — no groups, no threads, no separate chat-user model. created_by_member_id is whoever first opened the conversation (the get-or-create caller), not a "recipient" concept (Phase 16 has none — see messages/notify integration notes below).';

create index conversations_workspace_lead_idx on conversations (workspace_id, lead_id);
-- Powers the conversation list's "most recently active first" ordering
-- without a second query — see api/v1/messages.py / MessagingService.
create index conversations_workspace_updated_idx on conversations (workspace_id, updated_at desc);

create trigger conversations_set_updated_at
  before update on conversations
  for each row
  execute function set_updated_at();

alter table conversations enable row level security;

create table messages (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces (id) on delete cascade,
  conversation_id uuid not null,
  sender_member_id uuid not null,

  body text not null check (char_length(btrim(body)) > 0 and char_length(body) <= 4000),

  created_at timestamptz not null default now(),
  read_at timestamptz,

  constraint messages_conversation_fk
    foreign key (workspace_id, conversation_id) references conversations (workspace_id, id) on delete cascade,
  constraint messages_sender_member_fk
    foreign key (workspace_id, sender_member_id) references workspace_members (workspace_id, id) on delete restrict
);

comment on table messages is
  'Append-only messages within a conversation. sender_member_id is always current_member_id() server-side, never client-supplied (Phase 16 §"sender derived from authenticated member, never trusted from client"). read_at is a single per-message "seen" timestamp — a documented simplification, not true per-member read state (Phase 16 §"if the existing schema cannot support per-member read state correctly, use the simplest safe implementation and document the limitation"): marking a conversation read stamps read_at on every unread message not sent by the caller, so in the common case of a lead owner + manager(s) messaging about one lead, a message reads as "read" once any other participant has seen it, not per individual viewer.';

create index messages_workspace_conversation_created_idx on messages (workspace_id, conversation_id, created_at);
-- Partial index for the unread-count query (`read_at is null`), scoped
-- per conversation — see MessageRepository.count_unread_for_conversations.
create index messages_conversation_unread_idx on messages (conversation_id, read_at) where read_at is null;

alter table messages enable row level security;

-- Second line of defense (same pattern as
-- prevent_notification_content_edit, 000011_notifications_audit.sql):
-- even a caller who somehow gained UPDATE access can only ever toggle
-- read_at, never rewrite message content/authorship after the fact.
create or replace function prevent_message_content_edit()
returns trigger
language plpgsql
as $$
begin
  if new.body is distinct from old.body
    or new.workspace_id is distinct from old.workspace_id
    or new.conversation_id is distinct from old.conversation_id
    or new.sender_member_id is distinct from old.sender_member_id
    or new.created_at is distinct from old.created_at
  then
    raise exception 'Only read_at may be updated on messages';
  end if;
  return new;
end;
$$;

create trigger messages_protect_content
  before update on messages
  for each row
  execute function prevent_message_content_edit();

-- ---------------------------------------------------------------------
-- RLS: conversation/message visibility mirrors the underlying lead's
-- visibility (leads_select in 000014_rls_policies.sql) — a manager sees
-- every conversation in the workspace; a team_mate sees a conversation
-- only for a lead they're assigned to or created, same rule
-- interactions/calls/follow_ups already use for their own lead-scoped
-- rows. No dedicated messages.read/messages.create permission — see
-- api/v1/messages.py for why the API layer reuses leads.read/leads.update.
-- ---------------------------------------------------------------------

grant select, insert on conversations to authenticated;

create policy conversations_select on conversations
  for select to authenticated
  using (
    is_manager_or_above(workspace_id)
    or exists (
      select 1 from leads l
      where l.id = conversations.lead_id
        and l.workspace_id = conversations.workspace_id
        and (l.assigned_member_id = current_member_id(conversations.workspace_id)
             or l.created_by_member_id = current_member_id(conversations.workspace_id))
    )
  );

create policy conversations_insert on conversations
  for insert to authenticated
  with check (
    created_by_member_id = current_member_id(workspace_id)
    and (
      is_manager_or_above(workspace_id)
      or exists (
        select 1 from leads l
        where l.id = conversations.lead_id
          and l.workspace_id = conversations.workspace_id
          and (l.assigned_member_id = current_member_id(conversations.workspace_id)
               or l.created_by_member_id = current_member_id(conversations.workspace_id))
      )
    )
  );

-- No UPDATE/DELETE policy: conversations are never edited by clients in
-- this phase (updated_at exists for a future "last activity" write path
-- but nothing here triggers it yet — see the table comment).

grant select, insert, update on messages to authenticated;

create policy messages_select on messages
  for select to authenticated
  using (
    is_manager_or_above(workspace_id)
    or exists (
      select 1 from conversations c
      join leads l on l.id = c.lead_id and l.workspace_id = c.workspace_id
      where c.id = messages.conversation_id
        and c.workspace_id = messages.workspace_id
        and (l.assigned_member_id = current_member_id(messages.workspace_id)
             or l.created_by_member_id = current_member_id(messages.workspace_id))
    )
  );

create policy messages_insert on messages
  for insert to authenticated
  with check (
    sender_member_id = current_member_id(workspace_id)
    and (
      is_manager_or_above(workspace_id)
      or exists (
        select 1 from conversations c
        join leads l on l.id = c.lead_id and l.workspace_id = c.workspace_id
        where c.id = messages.conversation_id
          and c.workspace_id = messages.workspace_id
          and (l.assigned_member_id = current_member_id(messages.workspace_id)
               or l.created_by_member_id = current_member_id(messages.workspace_id))
      )
    )
  );

-- Mark-as-read (POST .../read): only read_at actually changes
-- (messages_protect_content enforces this even if this policy is ever
-- loosened), gated by the same conversation visibility as messages_select.
create policy messages_mark_read on messages
  for update to authenticated
  using (
    is_manager_or_above(workspace_id)
    or exists (
      select 1 from conversations c
      join leads l on l.id = c.lead_id and l.workspace_id = c.workspace_id
      where c.id = messages.conversation_id
        and c.workspace_id = messages.workspace_id
        and (l.assigned_member_id = current_member_id(messages.workspace_id)
             or l.created_by_member_id = current_member_id(messages.workspace_id))
    )
  )
  with check (
    is_manager_or_above(workspace_id)
    or exists (
      select 1 from conversations c
      join leads l on l.id = c.lead_id and l.workspace_id = c.workspace_id
      where c.id = messages.conversation_id
        and c.workspace_id = messages.workspace_id
        and (l.assigned_member_id = current_member_id(messages.workspace_id)
             or l.created_by_member_id = current_member_id(messages.workspace_id))
    )
  );

-- Extend the existing Phase 8/15 unified-timeline vocabulary so a sent
-- message can also be recorded as an interaction (api/v1/messages.py ->
-- MessagingService.send_message): 'message' is already an allowed
-- interactions.type value (000010_allocations_interactions.sql), so no
-- CHECK-constraint change is needed here — this comment documents that
-- fact rather than altering anything.
