-- Phase 0 (Admin/App alignment cycle) — Custom Lead Fields.
--
-- The canonical schema has always deferred this: leads.metadata is
-- documented (000008_leads.sql) as a freeform jsonb stopgap "pending a
-- proper custom_fields/custom_field_values design". The Admin panel's
-- "CRM Fields" screen is that need — an admin defines a field once and
-- it appears in the mobile app's lead form on next load, no app release.
--
-- Field types and controls are taken directly from the Runo screens
-- (Implementation Plan §4.1), not inferred. Five types:
--   text, number, date, options (single select), multi_options.
-- Four controls: auto_fill (pre-fill the value on the next interaction
-- form — on by default), is_filterable, is_readonly, is_mandatory.
--
-- Same "workspace-configurable lookup" shape as lead_statuses/
-- lead_sources/call_outcomes (000007): every row carries workspace_id,
-- a unique (workspace_id, id) for composite FKs, and a unique
-- (workspace_id, code) for stable client references. Write access is
-- workspace.manage (admin config); read is any member.

create table custom_fields (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces (id) on delete cascade,

  name text not null,
  code text not null,
  field_type text not null check (
    field_type in ('text', 'number', 'date', 'options', 'multi_options')
  ),
  -- Choice list for options / multi_options: [{code, label, sort_order}].
  -- Ignored (and expected empty) for the scalar types. Kept inline as
  -- jsonb rather than a child table for the same reason lead_statuses
  -- keeps its config inline: a handful of options per field, edited as
  -- a set from one admin form.
  options jsonb not null default '[]'::jsonb,

  auto_fill boolean not null default true,
  is_filterable boolean not null default false,
  is_readonly boolean not null default false,
  is_mandatory boolean not null default false,
  sort_order integer not null default 0,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (workspace_id, id),
  unique (workspace_id, code)
);

comment on table custom_fields is
  'Workspace-defined extra fields on a lead. Rendered dynamically by the mobile app''s lead form and by the Admin lead list''s filters (is_filterable). Replaces the leads.metadata stopgap.';
comment on column custom_fields.options is
  'options/multi_options choice list: [{"code": "...", "label": "...", "sort_order": 0}]. Empty for scalar types.';
comment on column custom_fields.auto_fill is
  'App behaviour: pre-populate this field on the next interaction form (e.g. the log-call form) from the lead''s current value.';

create index custom_fields_workspace_idx on custom_fields (workspace_id, sort_order);

create trigger custom_fields_set_updated_at
  before update on custom_fields
  for each row
  execute function set_updated_at();

alter table custom_fields enable row level security;

-- One value per (lead, field). value is jsonb so a single column holds
-- every field_type: "text", 42, "2026-09-10", "opt_a", ["opt_a","opt_b"].
-- Per-lead (not per-interaction — Implementation Plan §4.1): the history
-- a per-interaction model would buy is already in audit_logs (every
-- field change, before + after) and the activity timeline. The composite
-- FKs guarantee the lead and the field definition both belong to the
-- same workspace as the value row.
create table custom_field_values (
  workspace_id uuid not null references workspaces (id) on delete cascade,
  lead_id uuid not null,
  custom_field_id uuid not null,

  value jsonb,
  updated_at timestamptz not null default now(),

  primary key (lead_id, custom_field_id),

  constraint cfv_lead_fk
    foreign key (workspace_id, lead_id) references leads (workspace_id, id) on delete cascade,
  constraint cfv_field_fk
    foreign key (workspace_id, custom_field_id) references custom_fields (workspace_id, id) on delete cascade
);

comment on table custom_field_values is
  'Per-lead current value for each custom_field. value is jsonb-typed to hold every field_type in one column; the writer coerces per the field definition.';

create index cfv_workspace_field_idx on custom_field_values (workspace_id, custom_field_id);

create trigger custom_field_values_set_updated_at
  before update on custom_field_values
  for each row
  execute function set_updated_at();

alter table custom_field_values enable row level security;

-- ---------------------------------------------------------------------
-- RLS — custom_fields: read for any member, write for workspace.manage
-- (identical shape to lead_statuses_* in 000014_rls_policies.sql).
-- ---------------------------------------------------------------------
grant select, insert, update, delete on custom_fields to authenticated;

create policy custom_fields_select on custom_fields
  for select to authenticated
  using (is_workspace_member(workspace_id));

create policy custom_fields_insert on custom_fields
  for insert to authenticated
  with check (has_permission(workspace_id, 'workspace.manage'));

create policy custom_fields_update on custom_fields
  for update to authenticated
  using (has_permission(workspace_id, 'workspace.manage'))
  with check (has_permission(workspace_id, 'workspace.manage'));

create policy custom_fields_delete on custom_fields
  for delete to authenticated
  using (has_permission(workspace_id, 'workspace.manage'));

-- ---------------------------------------------------------------------
-- RLS — custom_field_values: visible when the underlying lead is
-- visible; writable when the underlying lead is writable. Defer to
-- leads' own ownership-or-manager rule via an EXISTS against leads
-- (whose own RLS the subquery still applies), same shape as lead_tags
-- RLS in 000014.
-- ---------------------------------------------------------------------
grant select, insert, update, delete on custom_field_values to authenticated;

create policy cfv_select on custom_field_values
  for select to authenticated
  using (
    is_workspace_member(workspace_id)
    and exists (
      select 1 from leads l
      where l.workspace_id = custom_field_values.workspace_id
        and l.id = custom_field_values.lead_id
    )
  );

create policy cfv_insert on custom_field_values
  for insert to authenticated
  with check (
    has_permission(workspace_id, 'leads.update')
    and exists (
      select 1 from leads l
      where l.workspace_id = custom_field_values.workspace_id
        and l.id = custom_field_values.lead_id
    )
  );

create policy cfv_update on custom_field_values
  for update to authenticated
  using (has_permission(workspace_id, 'leads.update'))
  with check (has_permission(workspace_id, 'leads.update'));

create policy cfv_delete on custom_field_values
  for delete to authenticated
  using (has_permission(workspace_id, 'leads.update'));
