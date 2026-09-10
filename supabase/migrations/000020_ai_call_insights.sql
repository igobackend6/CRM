-- Phase 20 — AI Call Insights. One evolving row per call, holding the
-- AI-derived transcript/summary/sentiment/action items/score plus an
-- explicit processing-state lifecycle (pending/processing/completed/
-- failed). This needs a genuinely new, small, stateful table rather
-- than reuse of `interactions` (append-only history, no
-- update/lifecycle path — see its own comment in
-- 000010_allocations_interactions.sql) or a jsonb column bolted onto
-- `calls` (that would mix a call's own factual record with a derived,
-- retriable analysis result, and `calls` intentionally has no
-- lifecycle/status-machine columns of its own beyond `state`, which
-- means something different — see docs/architecture/06-calling-architecture.md).
--
-- IMPORTANT DEPENDENCY (see the Phase 20 completion report for the
-- full audit): this project's own master plan defers actual Call
-- Recording to a later phase (docs/architecture/database.md §9:
-- "`call_recordings` | Deferred to Phase 21") and AI integration to
-- after that (docs/architecture/07-ai-architecture.md: "Phase 23,
-- post core-stability"). `calls` has no recording_url/storage_path
-- column, and no AI provider is configured anywhere in this repo
-- (app/core/config.py's ai_provider/ai_provider_api_key are both
-- unset). This table and its pipeline (app/services/ai/) are wired
-- end-to-end and fully tested against a fake provider, but a real
-- request in this environment deterministically resolves to
-- status='failed' with a clear, honest error_message — never a
-- fabricated transcript/summary.

-- `calls` (000009_calls_followups.sql) was never given a `unique
-- (workspace_id, id)` constraint the way `leads`/`follow_ups` were —
-- nothing before this migration ever needed to reference it via the
-- composite-FK pattern (docs/architecture/database.md "Composite
-- Foreign Key Pattern"). ai_call_insights_call_fk below is the first,
-- so it's added here rather than editing 000009 (never edit an
-- existing, already-applied migration) — purely additive, no existing
-- column/data touched, and `id` is already globally unique (primary
-- key) so this can never reject real data.
alter table calls add constraint calls_workspace_id_unique unique (workspace_id, id);

create table ai_call_insights (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces (id) on delete cascade,
  call_id uuid not null,
  requested_by_member_id uuid,

  status text not null default 'pending' check (status in ('pending', 'processing', 'completed', 'failed')),
  provider text,
  transcript text,
  summary text,
  sentiment text check (sentiment is null or sentiment in ('positive', 'neutral', 'negative')),
  action_items jsonb not null default '[]'::jsonb,
  call_score integer check (call_score is null or (call_score between 0 and 100)),
  error_message text,

  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (call_id),

  constraint ai_call_insights_call_fk
    foreign key (workspace_id, call_id) references calls (workspace_id, id) on delete cascade,
  constraint ai_call_insights_requested_by_fk
    foreign key (workspace_id, requested_by_member_id) references workspace_members (workspace_id, id) on delete set null
);

comment on table ai_call_insights is
  'Phase 20 — AI-derived call analysis, one evolving row per call (never a duplicate of `calls`). Requires both a real recording source and a configured AI provider to ever leave status=''pending''/''failed'' in this environment; see the Phase 20 completion report.';
comment on column ai_call_insights.action_items is
  'A plain jsonb array of short strings (e.g. ["Send pricing sheet", "Follow up Tuesday"]) — not a relational table, since these are AI-suggested text, never independently queried/joined.';

create index ai_call_insights_workspace_call_idx on ai_call_insights (workspace_id, call_id);
create index ai_call_insights_workspace_status_idx on ai_call_insights (workspace_id, status);

create trigger ai_call_insights_set_updated_at
  before update on ai_call_insights
  for each row
  execute function set_updated_at();

alter table ai_call_insights enable row level security;

-- Mirrors calls_select/calls_update exactly (manager-or-self), joined
-- back to the owning call since agent_member_id lives on `calls`, not
-- here — an AI insight is never visible/writable to anyone who
-- couldn't already see/update the call it analyzes. No DELETE policy,
-- same as `calls` itself (permanent history).

create policy ai_call_insights_select on ai_call_insights
  for select to authenticated
  using (
    has_permission(workspace_id, 'calls.read')
    and (
      is_manager_or_above(workspace_id)
      or exists (
        select 1 from calls c
        where c.workspace_id = ai_call_insights.workspace_id
          and c.id = ai_call_insights.call_id
          and c.agent_member_id = current_member_id(workspace_id)
      )
    )
  );

create policy ai_call_insights_insert on ai_call_insights
  for insert to authenticated
  with check (
    has_permission(workspace_id, 'calls.update')
    and (
      is_manager_or_above(workspace_id)
      or exists (
        select 1 from calls c
        where c.workspace_id = ai_call_insights.workspace_id
          and c.id = ai_call_insights.call_id
          and c.agent_member_id = current_member_id(workspace_id)
      )
    )
  );

create policy ai_call_insights_update on ai_call_insights
  for update to authenticated
  using (
    has_permission(workspace_id, 'calls.update')
    and (
      is_manager_or_above(workspace_id)
      or exists (
        select 1 from calls c
        where c.workspace_id = ai_call_insights.workspace_id
          and c.id = ai_call_insights.call_id
          and c.agent_member_id = current_member_id(workspace_id)
      )
    )
  )
  with check (
    has_permission(workspace_id, 'calls.update')
    and (
      is_manager_or_above(workspace_id)
      or exists (
        select 1 from calls c
        where c.workspace_id = ai_call_insights.workspace_id
          and c.id = ai_call_insights.call_id
          and c.agent_member_id = current_member_id(workspace_id)
      )
    )
  );
