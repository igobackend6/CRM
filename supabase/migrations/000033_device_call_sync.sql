-- Settings > Sync Call History / Call Recordings — phone call-log sync.
--
-- The mobile app reads the phone's own call log (business SIM only) and
-- sends the calls whose number matches a lead to the `call-sync` Edge
-- Function, which inserts them into `calls` with the caller's own JWT
-- (so every existing RLS policy still applies). Recordings found in the
-- folder the employee picked are uploaded to the existing private
-- `call-recordings` bucket and registered in `call_recordings` (000028).
--
-- Additive only: new nullable/defaulted columns, indexes and one
-- read-only function. No existing row or policy changes.

-- ---------------------------------------------------------------------
-- calls: where a row came from, and the phone's own id for it.
-- ---------------------------------------------------------------------
alter table calls
  add column if not exists source text not null default 'manual',
  -- "<device install id>:<Android CallLog _ID>". The install id is a
  -- random per-install value (no hardware identifier). Makes re-syncing
  -- the same call log a no-op.
  add column if not exists device_call_key text,
  -- The number as dialled/received, E.164 (+91...). Kept so an admin can
  -- see which number a synced call used.
  add column if not exists phone_number text;

-- A plain (not partial) unique constraint so the Edge Function's
-- upsert(onConflict: workspace_id,device_call_key) can target it.
-- Manually logged calls have a NULL key, and NULLs never collide.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'calls_source_check') then
    alter table calls add constraint calls_source_check check (source in ('manual', 'device_sync'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'calls_workspace_device_call_key_key') then
    alter table calls add constraint calls_workspace_device_call_key_key unique (workspace_id, device_call_key);
  end if;
end $$;

comment on column calls.source is
  '''manual'' = logged in the app/backend; ''device_sync'' = imported from the agent''s phone call log by the call-sync Edge Function.';
comment on column calls.device_call_key is
  'For device_sync rows: <random install id>:<Android CallLog _ID>. Unique per workspace so a re-sync never duplicates a call.';

-- ---------------------------------------------------------------------
-- call_recordings: one recording per call (000028's comment already
-- says "zero or one"; nothing used the table yet, so this cannot fail on
-- existing data unless someone inserted duplicates by hand).
-- ---------------------------------------------------------------------
create unique index if not exists call_recordings_call_id_key on call_recordings (call_id);

alter table call_recordings
  -- The file's name on the agent's phone, for display ("Call_2026...m4a").
  add column if not exists original_file_name text;

-- ---------------------------------------------------------------------
-- Matching a phone number to a lead. Lead phones are stored as typed
-- (spaces, +91, leading 0...), so match on the last 10 digits.
-- ---------------------------------------------------------------------
create index if not exists leads_workspace_phone_last10_idx
  on leads (workspace_id, (right(regexp_replace(coalesce(phone, ''), '\D', '', 'g'), 10)))
  where deleted_at is null;

-- SECURITY INVOKER: runs with the caller's RLS, so an agent only ever
-- matches leads they are allowed to see. Returns at most one lead per
-- number: the caller's own assigned lead first, then the newest.
create or replace function match_call_leads(p_workspace_id uuid, p_phones text[])
returns table (phone_key text, lead_id uuid)
language sql
stable
security invoker
set search_path = public
as $$
  with wanted as (
    select distinct right(regexp_replace(p, '\D', '', 'g'), 10) as phone_key
    from unnest(p_phones) as p
    where length(regexp_replace(p, '\D', '', 'g')) >= 10
  )
  select distinct on (w.phone_key) w.phone_key, l.id
  from wanted w
  join leads l
    on l.workspace_id = p_workspace_id
   and l.deleted_at is null
   and right(regexp_replace(coalesce(l.phone, ''), '\D', '', 'g'), 10) = w.phone_key
  order by w.phone_key,
           (l.assigned_member_id is not distinct from current_member_id(p_workspace_id)) desc,
           l.created_at desc;
$$;

revoke all on function match_call_leads(uuid, text[]) from public;
grant execute on function match_call_leads(uuid, text[]) to authenticated;

comment on function match_call_leads(uuid, text[]) is
  'Phone numbers -> lead ids (last-10-digit match), under the caller''s RLS. Used by the call-sync Edge Function.';
