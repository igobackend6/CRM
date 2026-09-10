# 08 — Testing Strategy

## 1. Flutter

- **Unit**: use cases, repository implementations (mocked data sources), controllers/notifiers (state transitions, error mapping).
- **Widget**: per-screen loading/empty/error/data states; form validation; permission-based UI hiding.
- **Integration** (`integration_test`): end-to-end critical paths — login → dashboard, create lead → allocate → call → log outcome → follow-up, offline-then-reconnect behavior for cached lists.

## 2. Python Backend

- **Unit**: service-layer business rules with repositories mocked (e.g., allocation logic, rechurn eligibility rules).
- **API tests** (`TestClient`): per endpoint — happy path, validation failure (422), auth failure (401), permission failure (403), not-found (404).
- **Service tests**: multi-step orchestrations (e.g., "allocate lead" writes allocation + interaction + notification atomically; a failure partway rolls back or is compensated, not left half-applied).
- **Security tests**: JWT tampering/expiry rejected; cross-workspace id substitution in request bodies is rejected even before hitting RLS (defense in depth verification).

## 3. Database

- **RLS tests**: for each table, verify a user from workspace A cannot select/insert/update/delete a row in workspace B; verify `team_mate` visibility restrictions vs `manager`+.
- **Permission tests**: `rep_permissions` overrides correctly widen/narrow a role's baseline.
- **Migration tests**: migrations apply cleanly to a fresh DB and are idempotent/reversible where feasible; seed data scripts are separate from schema migrations.

## 4. Android (Native)

- **Call tests**: state machine transitions under simulated telephony events.
- **Permission tests**: behavior when phone/mic/contacts permission is denied — falls back gracefully, never crashes.
- **Background tests**: call state tracked correctly when app backgrounded mid-call.
- **Recording compatibility tests**: capability detection returns correct status across the emulator + at least one representative real-device tier per OEM class available for testing.

## 5. CI Gates (Phase 26 hardens this; groundwork from Phase 1)

- Flutter: `flutter analyze` + `flutter test` must pass before merge.
- Python: `ruff`/`mypy` (or equivalent lint/type check) + `pytest` must pass before merge.
- No direct pushes to main without these gates once CI is wired (Phase 1 sets up the pipeline skeleton; enforcement tightens through later phases).
