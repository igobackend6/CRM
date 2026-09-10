-- Application-level identity, 1:1 with auth.users. Deliberately NOT
-- workspace-scoped: a profile is a person, independent of which
-- workspace(s) they belong to. Workspace membership (and therefore CRM
-- tenant access) is modeled separately in workspace_members
-- (000006_workspace_members_permissions.sql) so one person can belong to
-- more than one workspace without redesigning this table.

create table profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  phone text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table profiles is
  'Application identity for an authenticated user. No passwords or auth secrets here — those live in auth.users, owned by Supabase Auth.';

create trigger profiles_set_updated_at
  before update on profiles
  for each row
  execute function set_updated_at();

alter table profiles enable row level security;

-- Auto-provision a profile row whenever a new Supabase Auth user is
-- created, so the app never has to remember to do this itself (and it
-- can't be skipped by a client bug). Does NOT create any workspace
-- membership — joining a workspace is a separate, deliberate action.
create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (
    new.id,
    new.raw_user_meta_data ->> 'full_name',
    new.phone
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

comment on function handle_new_user() is
  'Provisions a profiles row for every new auth.users row. SECURITY DEFINER because it must write to profiles regardless of the (nonexistent, at signup time) caller session.';

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function handle_new_user();
