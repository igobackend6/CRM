-- Calls from / to numbers that are not leads.
--
-- Until now a call row always belonged to a lead (calls.lead_id NOT NULL), so call-sync dropped every
-- call from the phone whose number matched no lead. The mobile Calls page now lists every call of the
-- employee's selected SIM (like the phone's own call log), so a call may have no lead:
--
--   * lead_id becomes optional. The composite foreign key (workspace_id, lead_id) -> leads keeps
--     checking every call that DOES have a lead (a foreign key with a NULL column is not checked), so
--     a lead call can still never point into another workspace.
--   * contact_name holds the name to show when there is no lead: the phone's saved contact name, or
--     'Unknown'. A call with a lead keeps showing the lead's own name (it can change), so it is NULL.
--
-- Additive and backward compatible: no existing row changes, no policy changes (calls_select / insert /
-- update never looked at lead_id), and call_recordings still attaches to calls.id, so an unknown
-- number's recording is stored on its own call row exactly like a lead's.
--
-- Admin panel: anything that joins calls to leads must now treat a missing lead as "unknown caller" and
-- show calls.contact_name and calls.phone_number instead.

alter table calls alter column lead_id drop not null;

alter table calls add column if not exists contact_name text;

comment on column calls.lead_id is
  'The lead this call was with. NULL for a call to/from a number that is not a lead (device_sync only); see contact_name / phone_number.';
comment on column calls.contact_name is
  'Caller name when there is no lead: the phone''s saved contact name, or ''Unknown''. NULL for calls that have a lead.';

-- "All calls of this number" (the app's per-number call history) and the admin's lookup by number.
create index if not exists calls_workspace_phone_idx on calls (workspace_id, phone_number, started_at desc);
