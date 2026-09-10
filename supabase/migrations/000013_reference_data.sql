-- Global RBAC reference data. This lives in a migration, not
-- supabase/seed.sql, because every environment (including production)
-- needs these rows for the permission system to function at all — they
-- are not development-only convenience data. See
-- docs/architecture/rbac.md "Why Reference Data Is a Migration".
-- Idempotent via ON CONFLICT so this migration is safe to review/re-run.

insert into roles (name, description, is_system) values
  ('team_mate', 'Field sales rep. Sees and acts on their own assigned/created records.', true),
  ('manager', 'Team-level oversight. Sees and manages all records within the workspace.', true),
  ('admin', 'Workspace administration: members, permissions, pipeline configuration.', true),
  ('ceo', 'Organization-level access. Currently equivalent to admin''s grants; kept as a distinct role for future org-wide/multi-workspace reporting.', true)
on conflict (name) do nothing;

insert into permissions (code, category, description) values
  ('workspace.manage', 'workspace', 'Manage workspace settings and pipeline configuration (statuses, sources, outcomes).'),
  ('members.invite', 'members', 'Invite a new member to the workspace.'),
  ('members.manage', 'members', 'Change a member''s role, status, or permission overrides.'),
  ('members.remove', 'members', 'Remove (soft-remove) a member from the workspace.'),
  ('leads.read', 'leads', 'View leads.'),
  ('leads.create', 'leads', 'Create leads.'),
  ('leads.update', 'leads', 'Edit leads.'),
  ('leads.delete', 'leads', 'Soft-delete leads.'),
  ('leads.assign', 'leads', 'Assign or reassign a lead to a rep.'),
  ('calls.read', 'calls', 'View call history.'),
  ('calls.create', 'calls', 'Log a call.'),
  ('calls.update', 'calls', 'Edit a call''s outcome/notes after logging.'),
  ('followups.read', 'followups', 'View follow-ups.'),
  ('followups.create', 'followups', 'Create follow-ups.'),
  ('followups.update', 'followups', 'Edit, complete, or cancel follow-ups.'),
  ('allocations.read', 'allocations', 'View allocation history.'),
  ('allocations.manage', 'allocations', 'Create allocations (assign leads to reps).'),
  ('documents.read', 'documents', 'View/download lead documents.'),
  ('documents.upload', 'documents', 'Upload a lead document.'),
  ('documents.delete', 'documents', 'Soft-delete a lead document.'),
  ('notifications.read', 'notifications', 'View own notifications.'),
  ('reports.read', 'reports', 'View reports.'),
  ('audit.read', 'audit', 'View the audit log.')
on conflict (code) do nothing;

-- team_mate: day-to-day individual-contributor actions.
insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r, permissions p
where r.name = 'team_mate'
  and p.code in (
    'leads.read', 'leads.create', 'leads.update',
    'calls.read', 'calls.create', 'calls.update',
    'followups.read', 'followups.create', 'followups.update',
    'documents.read', 'documents.upload',
    'notifications.read'
  )
on conflict do nothing;

-- manager: everything team_mate has, plus workspace-wide oversight actions.
insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r, permissions p
where r.name = 'manager'
  and p.code in (
    'leads.read', 'leads.create', 'leads.update', 'leads.delete', 'leads.assign',
    'calls.read', 'calls.create', 'calls.update',
    'followups.read', 'followups.create', 'followups.update',
    'allocations.read', 'allocations.manage',
    'documents.read', 'documents.upload', 'documents.delete',
    'notifications.read',
    'reports.read'
  )
on conflict do nothing;

-- admin: everything manager has, plus workspace/member administration.
insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r, permissions p
where r.name = 'admin'
  and p.code in (
    'workspace.manage',
    'members.invite', 'members.manage', 'members.remove',
    'leads.read', 'leads.create', 'leads.update', 'leads.delete', 'leads.assign',
    'calls.read', 'calls.create', 'calls.update',
    'followups.read', 'followups.create', 'followups.update',
    'allocations.read', 'allocations.manage',
    'documents.read', 'documents.upload', 'documents.delete',
    'notifications.read',
    'reports.read', 'audit.read'
  )
on conflict do nothing;

-- ceo: same baseline as admin in Phase 2 — see the roles.description note above.
insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r, permissions p
where r.name = 'ceo'
  and p.code in (
    'workspace.manage',
    'members.invite', 'members.manage', 'members.remove',
    'leads.read', 'leads.create', 'leads.update', 'leads.delete', 'leads.assign',
    'calls.read', 'calls.create', 'calls.update',
    'followups.read', 'followups.create', 'followups.update',
    'allocations.read', 'allocations.manage',
    'documents.read', 'documents.upload', 'documents.delete',
    'notifications.read',
    'reports.read', 'audit.read'
  )
on conflict do nothing;
