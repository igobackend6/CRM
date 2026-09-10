-- Phase 0 (Admin/App alignment cycle) — Status -> Stage.
--
-- Confirmed from the Runo screens (Implementation Plan §4.2): Stage is a
-- FIXED four-value list — Start, In Progress, Closed Won, Closed Lost —
-- not a workspace-configurable table. Every lead_status maps to exactly
-- one of them.
--
-- This also fixes the canonical model rather than bolting onto it.
-- lead_statuses carried is_won and is_lost as two independent booleans,
-- which:
--   * allowed the contradictory state is_won = true AND is_lost = true, and
--   * could not express Start vs In Progress at all.
-- A single `stage` column replaces both, makes the four states mutually
-- exclusive by construction, and matches Runo. Both codebases (this
-- backend and the React admin panel) move their is_won/is_lost reads to
-- `stage` — agreed as a coordinated change, not unilateral.
--
-- Stage is load-bearing: it drives the Pipeline board columns, the
-- reporting conversion rate (closed_won / total), and the Rechurn queue
-- (leads sitting in a closed_lost status).

alter table lead_statuses add column stage text
  check (stage in ('start', 'in_progress', 'closed_won', 'closed_lost'));

-- Backfill from the existing booleans + ordering. A no-op on a fresh
-- migration run (no lead_statuses rows exist until a workspace is
-- created and provision_default_workspace_data() seeds them, already
-- with `stage` set — see below); correct if this migration is ever
-- applied to a database that already holds 000007-shaped data.
update lead_statuses ls set stage = case
  when ls.is_won  then 'closed_won'
  when ls.is_lost then 'closed_lost'
  when ls.sort_order = (
    select min(sort_order) from lead_statuses s where s.workspace_id = ls.workspace_id
  ) then 'start'
  else 'in_progress'
end
where stage is null;

alter table lead_statuses alter column stage set not null;

alter table lead_statuses drop column is_won;
alter table lead_statuses drop column is_lost;

comment on column lead_statuses.stage is
  'Fixed pipeline stage: start | in_progress | closed_won | closed_lost. Mutually exclusive by construction (replaced the is_won/is_lost boolean pair). Drives the pipeline board, reporting conversion rate, and the Rechurn queue.';

-- ---------------------------------------------------------------------
-- Rewrite provision_default_workspace_data() (originally 000012, last
-- touched here) so every NEW workspace's default statuses seed `stage`
-- directly. CREATE OR REPLACE needs the whole body — the lead_sources
-- and call_outcomes blocks are reproduced verbatim.
-- ---------------------------------------------------------------------
create or replace function provision_default_workspace_data()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into lead_statuses (workspace_id, name, code, sort_order, is_default, stage) values
    (new.id, 'New', 'new', 10, true, 'start'),
    (new.id, 'Contacted', 'contacted', 20, false, 'in_progress'),
    (new.id, 'Qualified', 'qualified', 30, false, 'in_progress'),
    (new.id, 'Follow Up', 'follow_up', 40, false, 'in_progress'),
    (new.id, 'Converted', 'converted', 50, false, 'closed_won'),
    (new.id, 'Lost', 'lost', 60, false, 'closed_lost');

  insert into lead_sources (workspace_id, name, code, is_default) values
    (new.id, 'Manual Entry', 'manual', true),
    (new.id, 'Website', 'website', false),
    (new.id, 'Referral', 'referral', false),
    (new.id, 'Cold Call', 'cold_call', false),
    (new.id, 'Campaign', 'campaign', false);

  insert into call_outcomes (workspace_id, name, code, is_positive, is_default) values
    (new.id, 'Connected', 'connected', true, true),
    (new.id, 'Not Connected', 'not_connected', false, false),
    (new.id, 'Busy', 'busy', false, false),
    (new.id, 'No Answer', 'no_answer', false, false),
    (new.id, 'Interested', 'interested', true, false),
    (new.id, 'Not Interested', 'not_interested', false, false),
    (new.id, 'Callback Requested', 'callback_requested', true, false);

  return new;
end;
$$;
