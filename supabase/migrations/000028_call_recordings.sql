-- Phase 0 (Admin/App alignment cycle) — Call recording metadata.
--
-- 000009_calls_followups.sql explicitly deferred this: "Recording
-- metadata is deferred to Phase 21". The Admin panel's Call Logs screen
-- needs to play and download recordings; the mobile app (Phase 5, its
-- own project) will capture them on-device and upload. This migration
-- lands only the schema both sides depend on — no capture code here.
--
-- Metadata-only, exactly like lead_documents (000008): the audio bytes
-- live in a private Storage bucket, reached through short-lived signed
-- URLs issued by the FastAPI backend — never a permanent public link.

-- calls has a bare `id` primary key but no unique (workspace_id, id),
-- so the composite FK below (which keeps a recording and its call in
-- the same workspace, structurally) needs this first.
alter table calls add constraint calls_workspace_id_key unique (workspace_id, id);

create table call_recordings (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces (id) on delete cascade,
  call_id uuid not null,

  storage_bucket text not null default 'call-recordings',
  storage_path text not null unique,
  mime_type text,
  size_bytes bigint,
  -- The recorded audio's own length. May differ slightly from
  -- calls.duration_seconds (the generated column off connected/ended
  -- timestamps) — recording can start a beat late or stop a beat early.
  duration_seconds integer,

  uploaded_by_member_id uuid,

  created_at timestamptz not null default now(),

  constraint call_recordings_call_fk
    foreign key (workspace_id, call_id) references calls (workspace_id, id) on delete cascade,
  constraint call_recordings_uploaded_by_fk
    foreign key (workspace_id, uploaded_by_member_id) references workspace_members (workspace_id, id) on delete set null
);

comment on table call_recordings is
  'Metadata for a captured call recording. Audio bytes live in Storage at storage_path (private bucket, workspace/call-scoped path). One call may have zero or one recording; capture is best-effort and unsupported on many Android devices.';

create index call_recordings_workspace_call_idx on call_recordings (workspace_id, call_id);

alter table call_recordings enable row level security;

-- ---------------------------------------------------------------------
-- RLS — a recording is visible exactly when its parent call is
-- (manager-or-above, or the agent who made the call). Insert follows
-- calls_insert's permission (calls.create — recordings arrive with the
-- call log). No UPDATE policy: recordings are immutable, replaced by
-- delete + re-upload. DELETE is manager-or-above only — a rep must not
-- be able to erase the recording of their own call.
-- ---------------------------------------------------------------------
grant select, insert, delete on call_recordings to authenticated;

create policy call_recordings_select on call_recordings
  for select to authenticated
  using (
    is_workspace_member(workspace_id)
    and exists (
      select 1 from calls c
      where c.workspace_id = call_recordings.workspace_id
        and c.id = call_recordings.call_id
    )
  );

create policy call_recordings_insert on call_recordings
  for insert to authenticated
  with check (
    has_permission(workspace_id, 'calls.create')
    and exists (
      select 1 from calls c
      where c.workspace_id = call_recordings.workspace_id
        and c.id = call_recordings.call_id
    )
  );

create policy call_recordings_delete on call_recordings
  for delete to authenticated
  using (is_manager_or_above(workspace_id));

-- ---------------------------------------------------------------------
-- Private Storage bucket — same path convention and policy model as
-- lead-documents (000015_storage.sql):
--   {workspace_id}/{call_id}/{filename}
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('call-recordings', 'call-recordings', false)
on conflict (id) do nothing;

create policy call_recordings_storage_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'call-recordings'
    and is_workspace_member((storage.foldername(name))[1]::uuid)
  );

create policy call_recordings_storage_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'call-recordings'
    and has_permission((storage.foldername(name))[1]::uuid, 'calls.create')
  );

create policy call_recordings_storage_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'call-recordings'
    and is_manager_or_above((storage.foldername(name))[1]::uuid)
  );

comment on policy call_recordings_storage_select on storage.objects is
  'Mirrors call_recordings table RLS at the file-storage level. No public/anon access; no UPDATE policy (files are replaced by delete + re-upload).';
