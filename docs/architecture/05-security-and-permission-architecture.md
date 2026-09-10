# 05 — Authentication, RBAC & Security Model

## 1. Authentication Architecture

```
Splash -> session restore attempt (secure storage / Supabase session)
  -> valid session -> load profile + role + permissions -> Dashboard
  -> no/expired session -> Login
Login (phone+password, or email where enabled)
  -> Supabase Auth sign-in
  -> fetch profile (workspace, role)
  -> fetch effective permissions (role_permissions + rep_permissions overrides)
  -> route to Dashboard
Logout -> Supabase sign-out -> clear secure storage -> clear local cache of sensitive data -> Login
Session expiry -> silent refresh via Supabase SDK; on refresh failure, force re-login
Account status (suspended/inactive) -> checked on session restore and login; blocks app entry with explicit message
```

Workspace selection: v1 assumes **one workspace per user** (typical field-sales rep). Multi-workspace-per-user is not built in v1; the schema (`profiles.workspace_id`) doesn't preclude it later but no switcher UI is built now.

## 2. RBAC Model

Roles (system-defined, extendable): `team_mate`, `manager`, `admin`, `ceo`.

- **Coarse grant**: `role_permissions` maps each role to a baseline permission set.
- **Fine override**: `rep_permissions` grants/revokes specific permissions per user, layered on top of their role — so "give this one team_mate access to Reports" doesn't require a new role.
- Permission codes are namespaced strings, e.g. `lead.create`, `lead.delete`, `lead.reassign`, `report.view.team`, `call.recording.delete`, `rep.permission.manage`.

Adding a new permission = insert a row in `permissions` + wire the check in the 3 enforcement layers below. No redesign needed.

## 3. Three-Layer Enforcement (defense in depth)

1. **Database / RLS** — the real boundary. Even a compromised client or backend bug cannot read/write outside what RLS allows.
2. **API (FastAPI)** — `require_permission(...)` dependency rejects unauthorized calls before touching business logic; prevents leaking existence/error details to unauthorized callers even when RLS would also catch it.
3. **Flutter UI** — hides/disables actions the user can't perform, for UX clarity only. UI checks are **never** the sole enforcement — assume a modified client always exists.

## 4. Security Controls

| Control | Where |
|---|---|
| RLS on every table | Supabase |
| JWT validation on every backend request | FastAPI dependency |
| Secure token storage | `flutter_secure_storage` |
| No service-role key in Flutter | enforced by review; key only in backend `.env` |
| Signed URLs, short expiry | Storage access |
| Input validation | Pydantic (backend), form validation (Flutter) |
| SQL safety | parameterized queries only via Supabase client / SQLAlchemy — no string-built SQL |
| Rate limiting | login-adjacent + bulk-write endpoints in FastAPI |
| Audit logging | DB triggers on sensitive tables (§ERD doc) + backend event logs |
| Secret management | `.env` (backend, git-ignored), platform secret store for CI/CD (Phase 3/26) |

## 5. Threat Model Highlights

- **Cross-workspace data leak** → mitigated primarily by RLS; API-layer checks as second line.
- **Privilege escalation via client-side role spoofing** → role/permissions are read from `profiles`/`role_permissions` server-side (RLS + backend), never trusted from a client-supplied field.
- **Recording/document exfiltration** → signed URLs, short TTL, workspace-scoped Storage paths.
- **Auto-dialer misuse to bypass allocation rules** → dialer queue is built server-side (or RLS-filtered) from leads the user is actually permitted to call; the client cannot dial arbitrary leads outside their allocation.
- **Replay/stale JWT** → standard Supabase JWT expiry + refresh; backend rejects expired tokens outright.

## 6. Compliance Notes

Call recording, being sensitive, needs a documented consent/notice mechanism (jurisdiction-dependent) — flagged as a Phase 21 requirement, not solved here, but the architecture (recording status enum, workspace-scoped storage, audit trail) is built to support it.
