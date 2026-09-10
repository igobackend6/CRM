-- Core lead/prospect record. A lead becomes a "customer" by setting
-- is_customer = true (with converted_at stamped) rather than migrating
-- its data into a separate customers table — see
-- docs/architecture/database.md "Lead -> Customer Conversion" for why:
-- a separate table with lead_id/customer_id cross-references was
-- evaluated and rejected as unnecessary circular ownership, and it would
-- have split a single continuous interaction history across two tables.
--
-- All references from leads to other workspace-scoped tables use the
-- composite (workspace_id, id) foreign key pattern, so a lead can never
-- structurally reference another workspace's status/source/member even
-- if application code has a bug — the database rejects it outright.

create table leads (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces (id) on delete cascade,

  name text not null,
  phone text,
  email text,

  source_id uuid,
  status_id uuid not null,
  priority text not null default 'medium' check (priority in ('low', 'medium', 'high', 'urgent')),

  assigned_member_id uuid,
  created_by_member_id uuid,

  is_customer boolean not null default false,
  converted_at timestamptz,

  address_line text,
  city text,
  state_region text,
  country text,
  latitude numeric(9, 6),
  longitude numeric(9, 6),

  metadata jsonb not null default '{}'::jsonb,

  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (workspace_id, id),

  constraint leads_source_fk
    foreign key (workspace_id, source_id) references lead_sources (workspace_id, id) on delete set null,
  constraint leads_status_fk
    foreign key (workspace_id, status_id) references lead_statuses (workspace_id, id) on delete restrict,
  constraint leads_assigned_member_fk
    foreign key (workspace_id, assigned_member_id) references workspace_members (workspace_id, id) on delete set null,
  constraint leads_created_by_member_fk
    foreign key (workspace_id, created_by_member_id) references workspace_members (workspace_id, id) on delete set null,

  constraint leads_converted_at_requires_customer
    check (not is_customer or converted_at is not null)
);

comment on table leads is
  'Core lead/prospect record. is_customer=true + converted_at marks conversion; the row (and its full interaction history) is preserved unchanged, not copied elsewhere.';
comment on column leads.metadata is
  'Freeform jsonb escape hatch pending a proper custom_fields/custom_field_values design, deferred until the Leads UI phase actually needs it (see docs/architecture/database.md "Deferred Entities").';
comment on column leads.deleted_at is
  'Soft delete: leads are never physically removed by the application, so pipeline history, interactions, and audit trails referencing a lead stay intact. Physical deletion (e.g. GDPR erasure) is an explicit admin/data-operations action, not exposed through normal CRUD.';

create index leads_workspace_status_idx on leads (workspace_id, status_id);
create index leads_workspace_assigned_idx on leads (workspace_id, assigned_member_id);
create index leads_workspace_created_at_idx on leads (workspace_id, created_at desc);
create index leads_workspace_phone_idx on leads (workspace_id, phone);
create index leads_workspace_email_idx on leads (workspace_id, email);

-- Enables fast partial-name search via the trigram index below.
create extension if not exists pg_trgm;
create index leads_name_trgm_idx on leads using gin (name gin_trgm_ops);

create trigger leads_set_updated_at
  before update on leads
  for each row
  execute function set_updated_at();

alter table leads enable row level security;

create table lead_tags (
  workspace_id uuid not null references workspaces (id) on delete cascade,
  lead_id uuid not null,
  tag_id uuid not null,
  created_at timestamptz not null default now(),

  primary key (lead_id, tag_id),
  constraint lead_tags_lead_fk
    foreign key (workspace_id, lead_id) references leads (workspace_id, id) on delete cascade,
  constraint lead_tags_tag_fk
    foreign key (workspace_id, tag_id) references tags (workspace_id, id) on delete cascade
);

comment on table lead_tags is 'Lead <-> tag assignments. Composite FKs guarantee the lead and tag belong to the same workspace.';

create index lead_tags_workspace_idx on lead_tags (workspace_id);
create index lead_tags_tag_idx on lead_tags (tag_id);

alter table lead_tags enable row level security;

create table lead_documents (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces (id) on delete cascade,
  lead_id uuid not null,
  uploaded_by_member_id uuid,

  storage_bucket text not null default 'lead-documents',
  storage_path text not null unique,
  file_name text not null,
  mime_type text,
  size_bytes bigint,

  deleted_at timestamptz,
  created_at timestamptz not null default now(),

  constraint lead_documents_lead_fk
    foreign key (workspace_id, lead_id) references leads (workspace_id, id) on delete cascade,
  constraint lead_documents_uploaded_by_fk
    foreign key (workspace_id, uploaded_by_member_id) references workspace_members (workspace_id, id) on delete set null
);

comment on table lead_documents is
  'Metadata only — file bytes live in Supabase Storage at storage_path (private bucket, workspace/lead-scoped path). Soft-deleted via deleted_at so the audit trail survives a "delete".';

create index lead_documents_workspace_lead_idx on lead_documents (workspace_id, lead_id);

alter table lead_documents enable row level security;
