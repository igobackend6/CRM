from enum import Enum


class Permission(str, Enum):
    """Typed mirror of the `permissions.code` catalog seeded by
    supabase/migrations/000013_reference_data.sql. The database is the
    actual source of truth and the only thing actually enforced
    (authorization.py always calls the DB's has_permission() RPC, never
    checks this enum's membership on its own) — this exists so feature
    code writes `Permission.LEADS_READ` instead of the string literal
    "leads.read", catching a typo at import time instead of as a
    silent-always-false permission check at runtime. If this drifts from
    the migration, the migration wins; update this enum to match it, not
    the other way around.
    """

    WORKSPACE_MANAGE = "workspace.manage"

    MEMBERS_INVITE = "members.invite"
    MEMBERS_MANAGE = "members.manage"
    MEMBERS_REMOVE = "members.remove"

    LEADS_READ = "leads.read"
    LEADS_CREATE = "leads.create"
    LEADS_UPDATE = "leads.update"
    LEADS_DELETE = "leads.delete"
    LEADS_ASSIGN = "leads.assign"

    CALLS_READ = "calls.read"
    CALLS_CREATE = "calls.create"
    CALLS_UPDATE = "calls.update"

    FOLLOWUPS_READ = "followups.read"
    FOLLOWUPS_CREATE = "followups.create"
    FOLLOWUPS_UPDATE = "followups.update"

    ALLOCATIONS_READ = "allocations.read"
    ALLOCATIONS_MANAGE = "allocations.manage"

    DOCUMENTS_READ = "documents.read"
    DOCUMENTS_UPLOAD = "documents.upload"
    DOCUMENTS_DELETE = "documents.delete"

    NOTIFICATIONS_READ = "notifications.read"

    # Phase 21A — Secure Lead Documents + WhatsApp Templates
    # (supabase/migrations/000022_message_templates.sql).
    TEMPLATES_MANAGE = "templates.manage"

    REPORTS_READ = "reports.read"

    AUDIT_READ = "audit.read"
