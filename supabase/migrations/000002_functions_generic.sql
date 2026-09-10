-- Generic, table-agnostic helper functions. Security/permission-aware
-- helpers that depend on CRM tables are added later, in
-- 000012_security_functions.sql, once those tables exist.

create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

comment on function set_updated_at() is
  'Generic BEFORE UPDATE trigger: stamps updated_at = now() on every row update.';
