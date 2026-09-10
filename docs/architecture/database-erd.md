# Database ERD — Phase 2

See `database.md` for the reasoning behind every decision reflected here.

```mermaid
erDiagram
    WORKSPACES ||--o{ WORKSPACE_MEMBERS : has
    PROFILES ||--o{ WORKSPACE_MEMBERS : "is a member via"
    ROLES ||--o{ WORKSPACE_MEMBERS : grants_role
    ROLES ||--o{ ROLE_PERMISSIONS : baseline
    PERMISSIONS ||--o{ ROLE_PERMISSIONS : included_in
    WORKSPACE_MEMBERS ||--o{ REP_PERMISSIONS : overridden_for
    PERMISSIONS ||--o{ REP_PERMISSIONS : overrides

    WORKSPACES ||--o{ LEAD_STATUSES : configures
    WORKSPACES ||--o{ LEAD_SOURCES : configures
    WORKSPACES ||--o{ CALL_OUTCOMES : configures
    WORKSPACES ||--o{ TAGS : configures

    WORKSPACES ||--o{ LEADS : owns
    LEAD_STATUSES ||--o{ LEADS : current_status
    LEAD_SOURCES ||--o{ LEADS : sourced_from
    WORKSPACE_MEMBERS ||--o{ LEADS : assigned_to
    WORKSPACE_MEMBERS ||--o{ LEADS : created_by

    LEADS ||--o{ LEAD_TAGS : tagged
    TAGS ||--o{ LEAD_TAGS : applied_to
    LEADS ||--o{ LEAD_DOCUMENTS : has
    WORKSPACE_MEMBERS ||--o{ LEAD_DOCUMENTS : uploaded_by

    LEADS ||--o{ CALLS : called
    WORKSPACE_MEMBERS ||--o{ CALLS : made_by
    CALL_OUTCOMES ||--o{ CALLS : resulted_in

    LEADS ||--o{ FOLLOW_UPS : scheduled_for
    WORKSPACE_MEMBERS ||--o{ FOLLOW_UPS : assigned_to

    LEADS ||--o{ ALLOCATIONS : allocated
    WORKSPACE_MEMBERS ||--o{ ALLOCATIONS : assigned_to_rep
    WORKSPACE_MEMBERS ||--o{ ALLOCATIONS : assigned_by_rep

    LEADS ||--o{ INTERACTIONS : timeline
    WORKSPACE_MEMBERS ||--o{ INTERACTIONS : actor

    WORKSPACE_MEMBERS ||--o{ NOTIFICATIONS : receives

    WORKSPACES ||--o{ AUDIT_LOGS : tracks
    WORKSPACE_MEMBERS ||--o{ AUDIT_LOGS : actor
```

## Notes on Reading This ERD

- `PROFILES` connects to the rest of the schema **only** through `WORKSPACE_MEMBERS` — there is no direct `PROFILES ||--o{ LEADS` or similar edge, by design (`database.md` §2–3).
- Every edge from `WORKSPACE_MEMBERS` outward (to `LEADS`, `CALLS`, `FOLLOW_UPS`, `ALLOCATIONS`, `INTERACTIONS`, `NOTIFICATIONS`) is backed by a composite `(workspace_id, id)` foreign key, not shown as a separate edge here for readability — see `database.md` §3.
- `CUSTOMERS` does not appear — a `LEADS` row with `is_customer = true` *is* the customer (`database.md` §4).
- `NOTES` does not appear — a `note`-typed `INTERACTIONS` row *is* a note (`database.md` §5).
