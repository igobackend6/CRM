-- Phase 21A — Secure Lead Documents + WhatsApp Templates. This
-- migration adds only the one piece of new persistent state the phase
-- actually needs: reusable, workspace-scoped WhatsApp/CRM message
-- templates (planned in docs/architecture/01-database-erd.md's ERD but
-- never created by any earlier migration — confirmed by grep across
-- supabase/migrations/*.sql before writing this file). Documents
-- themselves need NO schema change at all: `lead_documents`
-- (000008_leads.sql), its RLS (000014_rls_policies.sql, hardened by
-- 000021), and the `lead-documents` Storage bucket/policies
-- (000015_storage.sql) already exist in full — this phase only adds the
-- backend/Flutter code that actually uses them (upload/list/signed-url/
-- delete), see DocumentRepository/DocumentService.
--
-- WhatsApp deep-link messaging itself introduces no new table: it is a
-- client-initiated `wa.me` URL open, not a stored message (§"Do NOT
-- implement... message delivery tracking" — there is nothing to
-- persist per send).

create table message_templates (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces (id) on delete cascade,
  name text not null,
  body text not null,
  created_by_member_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint message_templates_created_by_fk
    foreign key (workspace_id, created_by_member_id) references workspace_members (workspace_id, id) on delete set null,
  constraint message_templates_name_length check (char_length(name) between 1 and 100),
  constraint message_templates_body_length check (char_length(body) between 1 and 2000)
);

-- One template name per workspace (case-insensitive) — a small,
-- deliberate constraint that avoids a confusing picker full of
-- near-duplicate entries; not asked for explicitly, but "indexes and
-- constraints" was, and an unbounded, unnamed list of templates a rep
-- has to scroll through to find the right one is a real usability trap
-- with only reps ever creating them (see role_permissions below).
create unique index message_templates_workspace_name_idx on message_templates (workspace_id, lower(name));
create index message_templates_workspace_idx on message_templates (workspace_id);

alter table message_templates enable row level security;
grant select, insert, update, delete on message_templates to authenticated;

-- Read: plain workspace membership, same as lead_statuses/lead_sources/
-- tags (reference-ish data every member needs to see to do their job,
-- not a permission-gated resource) — see leads.py's list_tags/
-- list_lead_statuses routes for the identical precedent.
create policy message_templates_select on message_templates
  for select to authenticated
  using (is_workspace_member(workspace_id));

-- Write: gated on the one new permission this phase adds
-- (templates.manage, seeded below) and, per Phase 21's actor-identity
-- hardening precedent (000021_rls_actor_identity_hardening.sql), the
-- inserted `created_by_member_id` must actually be the caller's own
-- membership row (or null) — never a value attributing a template to
-- someone else.
create policy message_templates_insert on message_templates
  for insert to authenticated
  with check (
    has_permission(workspace_id, 'templates.manage')
    and (created_by_member_id is null or created_by_member_id = current_member_id(workspace_id))
  );

create policy message_templates_update on message_templates
  for update to authenticated
  using (has_permission(workspace_id, 'templates.manage'))
  with check (has_permission(workspace_id, 'templates.manage'));

create policy message_templates_delete on message_templates
  for delete to authenticated
  using (has_permission(workspace_id, 'templates.manage'));

-- Reference data: the new permission, granted to every seeded role.
-- Templates are a day-to-day communication tool every rep uses (like
-- tags), not a manager-only configuration surface, so this is granted
-- alongside team_mate's other day-to-day permissions, not held back for
-- manager/admin/ceo the way allocations.manage/reports.read are.
insert into permissions (code, category, description) values
  ('templates.manage', 'messaging', 'Create, edit, and delete WhatsApp/CRM message templates.')
on conflict (code) do nothing;

insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r, permissions p
where r.name in ('team_mate', 'manager', 'admin', 'ceo')
  and p.code = 'templates.manage'
on conflict do nothing;
