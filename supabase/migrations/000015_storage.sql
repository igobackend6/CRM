-- Private Storage bucket for lead documents. Path convention:
--   {workspace_id}/{lead_id}/{filename}
-- storage.foldername(name)[1] is therefore always the workspace_id, which
-- is what every policy below checks against — the same
-- is_workspace_member/has_permission helpers used by table RLS, so
-- storage access follows the exact same permission model as the
-- lead_documents metadata table it backs.

insert into storage.buckets (id, name, public)
values ('lead-documents', 'lead-documents', false)
on conflict (id) do nothing;

create policy lead_documents_storage_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'lead-documents'
    and is_workspace_member((storage.foldername(name))[1]::uuid)
  );

create policy lead_documents_storage_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'lead-documents'
    and has_permission((storage.foldername(name))[1]::uuid, 'documents.upload')
  );

create policy lead_documents_storage_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'lead-documents'
    and has_permission((storage.foldername(name))[1]::uuid, 'documents.delete')
  );

comment on policy lead_documents_storage_select on storage.objects is
  'Mirrors lead_documents table RLS at the file-storage level. No public/anon access; no UPDATE policy (files are replaced by delete+re-upload, not mutated in place).';
