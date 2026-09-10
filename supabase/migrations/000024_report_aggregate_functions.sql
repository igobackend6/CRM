-- Phase 21C — Complete Reports & Analytics. One new DB-side aggregate:
-- total/average call talk-time. Every other report metric (counts,
-- breakdowns by status/outcome/source/priority) reuses the existing
-- `count="exact"` PostgREST pattern already used throughout
-- DashboardService (bounded, small-cardinality loops) — SUM/AVG has no
-- equivalent in the PostgREST query builder, which is the only reason
-- this function exists at all.
--
-- Deliberately NOT `security definer` (unlike is_workspace_member/
-- has_permission in 000012_security_functions.sql, which must bypass
-- RLS to break the workspace_members chicken-and-egg problem) — this
-- runs as the calling role, so `calls_select`'s existing RLS
-- (000014_rls_policies.sql: a team_mate sees only their own calls, a
-- manager/admin/ceo sees the whole workspace) applies transparently
-- inside the function body. No authorization logic is duplicated here.

create or replace function report_call_duration_stats(
  p_workspace_id uuid,
  p_agent_member_id uuid default null,
  p_since timestamptz default null,
  p_until timestamptz default null
)
returns table (total_talk_seconds bigint, average_call_seconds numeric)
language sql
stable
as $$
  select
    coalesce(sum(duration_seconds), 0)::bigint as total_talk_seconds,
    coalesce(avg(duration_seconds), 0)::numeric as average_call_seconds
  from calls
  where workspace_id = p_workspace_id
    and (p_agent_member_id is null or agent_member_id = p_agent_member_id)
    and (p_since is null or started_at >= p_since)
    and (p_until is null or started_at < p_until)
    and duration_seconds is not null;
$$;

comment on function report_call_duration_stats(uuid, uuid, timestamptz, timestamptz) is
  'Phase 21C: total/average talk-time (seconds) for calls that actually connected (duration_seconds is only ever populated after connected_at+ended_at — see calls table comment). Runs as the caller''s own role so RLS still scopes the result.';

grant execute on function report_call_duration_stats(uuid, uuid, timestamptz, timestamptz) to authenticated;
