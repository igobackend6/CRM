"""
Real Postgres/RLS validation against a live Supabase project — the
actual end-to-end check every phase report since Phase 2 had to flag as
outstanding (no Docker locally; run this once a real project is
connected and supabase/migrations/*.sql have been applied to it).

Exercises:
  1. Real user creation + sign-in (Supabase Auth) for two independent
     test users (via the Admin API, pre-confirmed — avoids depending on
     the project's email-confirmation/deliverability settings).
  2. handle_new_user() trigger -> profiles row auto-created
     (000004_profiles.sql).
  3. create_workspace() RPC -> workspace + workspace_members(admin) row,
     atomically, via SECURITY DEFINER (000012_security_functions.sql).
  4. RLS: the creating member can see their own workspace.
  5. RLS: workspace isolation — a second, unrelated user can NOT see the
     first user's workspace.
  6. RBAC: has_permission()/is_workspace_member() RPCs resolve correctly
     for a real admin member, and correctly deny a non-member.
  7. RLS (not just GRANTs) is what blocks an unauthenticated `anon`
     caller: a bare anon-key SELECT returns zero rows and an anon INSERT
     is rejected, even though Supabase Cloud's default per-schema ACL
     actually grants `anon` full table-level privileges (a real finding
     from the first live run of this script, 2026-09-03 — see the
     `000014_rls_policies.sql` policies' `to authenticated` scoping,
     which is what actually keeps anon out; the migration's own
     `grant ... to authenticated` statements are not the enforcement
     layer on Supabase Cloud, RLS is).
  8. Cleanup: deletes every test workspace/member/auth user this run
     created, so nothing is left behind in the real project.

Reads SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY from
backend/.env (never commit that file — see backend/.env.example).
Prints PASS/FAIL for each check; exits non-zero if any check fails.

Usage (from backend/, with the venv active):
    python scripts/validate_rls.py
"""

import sys
import time
from pathlib import Path

import httpx

ENV_PATH = Path(__file__).resolve().parent.parent / ".env"


def load_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            values[k.strip()] = v.strip()
    return values


env = load_env(ENV_PATH)
URL = env.get("SUPABASE_URL", "")
ANON_KEY = env.get("SUPABASE_ANON_KEY", "")
SERVICE_KEY = env.get("SUPABASE_SERVICE_ROLE_KEY", "")

if not (URL and ANON_KEY and SERVICE_KEY):
    print(f"SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY must be set in {ENV_PATH}")
    sys.exit(2)

results: list[tuple[str, str, str]] = []


def check(name: str, condition: bool, detail: str = "") -> bool:
    status = "PASS" if condition else "FAIL"
    results.append((status, name, detail))
    print(f"[{status}] {name}" + (f" — {detail}" if detail and status == "FAIL" else ""))
    return condition


def rest(path: str, *, token: str, method: str = "GET", json_body=None, params=None) -> httpx.Response:
    headers = {"apikey": ANON_KEY, "Authorization": f"Bearer {token}"}
    with httpx.Client(base_url=URL, timeout=15) as client:
        return client.request(method, f"/rest/v1/{path}", headers=headers, json=json_body, params=params)


def admin_create_confirmed_user(email: str, password: str) -> httpx.Response:
    """Uses the service-role Admin API to create an already-confirmed
    test user directly — independent of the project's own
    email-confirmation requirement or signup rate limits."""
    with httpx.Client(base_url=URL, timeout=15) as client:
        return client.post(
            "/auth/v1/admin/users",
            headers={"apikey": SERVICE_KEY, "Authorization": f"Bearer {SERVICE_KEY}"},
            json={"email": email, "password": password, "email_confirm": True},
        )


def sign_in(email: str, password: str) -> httpx.Response:
    with httpx.Client(base_url=URL, timeout=15) as client:
        return client.post(
            "/auth/v1/token",
            params={"grant_type": "password"},
            headers={"apikey": ANON_KEY},
            json={"email": email, "password": password},
        )


def admin_delete_user(user_id: str) -> httpx.Response:
    with httpx.Client(base_url=URL, timeout=15) as client:
        return client.delete(
            f"/auth/v1/admin/users/{user_id}",
            headers={"apikey": SERVICE_KEY, "Authorization": f"Bearer {SERVICE_KEY}"},
        )


def main() -> int:
    ts = int(time.time())
    email_a = f"rls-validation-a-{ts}@example.com"
    email_b = f"rls-validation-b-{ts}@example.com"
    password = "ValidationPass123!"
    user_a_id = user_b_id = workspace_id = None

    try:
        print("=== 1. Create + sign in user A ===")
        resp = admin_create_confirmed_user(email_a, password)
        ok_a = check("Admin-create user A succeeds", resp.status_code in (200, 201), f"{resp.status_code}: {resp.text[:200]}")
        user_a_id = resp.json().get("id") if ok_a else None
        resp = sign_in(email_a, password)
        ok_a_token = check("Sign in as user A succeeds", resp.status_code == 200, f"{resp.status_code}: {resp.text[:200]}")
        token_a = resp.json().get("access_token") if ok_a_token else None

        print("=== 2. Create + sign in user B ===")
        resp = admin_create_confirmed_user(email_b, password)
        ok_b = check("Admin-create user B succeeds", resp.status_code in (200, 201), f"{resp.status_code}: {resp.text[:200]}")
        user_b_id = resp.json().get("id") if ok_b else None
        resp = sign_in(email_b, password)
        ok_b_token = check("Sign in as user B succeeds", resp.status_code == 200, f"{resp.status_code}: {resp.text[:200]}")
        token_b = resp.json().get("access_token") if ok_b_token else None

        if not (token_a and token_b):
            print("Cannot continue without both user tokens.")
            return 2

        print("=== 3. profiles row auto-created by handle_new_user() trigger ===")
        resp = rest("profiles", token=token_a, params={"id": f"eq.{user_a_id}"})
        profiles = resp.json() if resp.status_code == 200 else []
        check("Profile row exists for user A", resp.status_code == 200 and len(profiles) == 1, f"{resp.status_code}: {resp.text[:200]}")

        print("=== 4. create_workspace() RPC ===")
        resp = rest(
            "rpc/create_workspace", token=token_a, method="POST",
            json_body={"p_name": "RLS Validation Workspace", "p_slug": f"rls-validation-{ts}"},
        )
        ok_ws = check("create_workspace RPC succeeds", resp.status_code in (200, 201), f"{resp.status_code}: {resp.text[:300]}")
        workspace_id = resp.json() if ok_ws else None
        check("create_workspace returned a workspace id", isinstance(workspace_id, str) and len(workspace_id) > 10)

        print("=== 5. RLS: creator (admin) can see their own workspace ===")
        resp = rest("workspaces", token=token_a, params={"id": f"eq.{workspace_id}"})
        rows = resp.json() if resp.status_code == 200 else []
        check("Workspace visible to its creator", resp.status_code == 200 and len(rows) == 1, f"{resp.status_code}: {resp.text[:200]}")

        print("=== 6. RLS: workspace_members has the creator as admin ===")
        resp = rest("workspace_members", token=token_a, params={"workspace_id": f"eq.{workspace_id}"})
        members = resp.json() if resp.status_code == 200 else []
        check("Exactly one member (the creator)", resp.status_code == 200 and len(members) == 1, f"{resp.status_code}: {resp.text[:200]}")

        print("=== 7. RLS: workspace isolation — user B cannot see user A's workspace ===")
        resp = rest("workspaces", token=token_b, params={"id": f"eq.{workspace_id}"})
        rows_b = resp.json() if resp.status_code == 200 else None
        check(
            "User B sees zero rows for user A's workspace (RLS isolation)",
            resp.status_code == 200 and rows_b == [],
            f"{resp.status_code}: {resp.text[:200]}",
        )

        print("=== 8. RBAC RPCs resolve correctly for a real admin member ===")
        resp = rest("rpc/is_workspace_member", token=token_a, method="POST", json_body={"p_workspace_id": workspace_id})
        check("is_workspace_member(true) for the creator", resp.status_code == 200 and resp.json() is True, f"{resp.status_code}: {resp.text[:200]}")

        resp = rest(
            "rpc/has_permission", token=token_a, method="POST",
            json_body={"p_workspace_id": workspace_id, "p_permission_code": "leads.create"},
        )
        check("has_permission('leads.create') is true for admin", resp.status_code == 200 and resp.json() is True, f"{resp.status_code}: {resp.text[:200]}")

        resp = rest("rpc/is_workspace_member", token=token_b, method="POST", json_body={"p_workspace_id": workspace_id})
        check("is_workspace_member(false) for non-member user B", resp.status_code == 200 and resp.json() is False, f"{resp.status_code}: {resp.text[:200]}")

        print("=== 9. anon SELECT on a protected table returns zero rows (RLS is the real boundary) ===")
        with httpx.Client(base_url=URL, timeout=15) as client:
            resp = client.get("/rest/v1/leads", headers={"apikey": ANON_KEY, "Authorization": f"Bearer {ANON_KEY}"})
        anon_rows = resp.json() if resp.status_code == 200 else None
        check("Anon SELECT on /leads returns zero rows", resp.status_code == 200 and anon_rows == [], f"{resp.status_code}: {resp.text[:300]}")

        print("=== 10. anon INSERT on a protected table is rejected by RLS ===")
        with httpx.Client(base_url=URL, timeout=15) as client:
            resp = client.post(
                "/rest/v1/leads",
                headers={"apikey": ANON_KEY, "Authorization": f"Bearer {ANON_KEY}"},
                json={
                    "workspace_id": workspace_id or "00000000-0000-0000-0000-000000000000",
                    "name": "anon should not be able to insert this",
                    "status_id": "00000000-0000-0000-0000-000000000000",
                },
            )
        check("Anon INSERT into /leads is rejected", resp.status_code in (401, 403), f"{resp.status_code}: {resp.text[:300]}")

    finally:
        print("=== Cleanup: remove test fixtures ===")
        if workspace_id:
            with httpx.Client(base_url=URL, timeout=15) as client:
                headers = {"apikey": SERVICE_KEY, "Authorization": f"Bearer {SERVICE_KEY}"}
                # audit_logs FIRST, before workspace_members: audit_logs
                # has a composite FK (workspace_id, actor_member_id) ->
                # workspace_members(workspace_id, id) with
                # `on delete set null` (000011_notifications_audit.sql),
                # but audit_logs.workspace_id is NOT NULL — deleting
                # workspace_members first makes Postgres's own cascade
                # action try to null a NOT NULL column and fail with a
                # 23502 error. Deleting the audit_logs rows outright
                # first avoids ever triggering that cascade. This is a
                # real schema finding from this script's first live run
                # (2026-09-03) — see the Phase 8/9 handoff report.
                client.delete("/rest/v1/audit_logs", headers=headers, params={"workspace_id": f"eq.{workspace_id}"})
                client.delete("/rest/v1/workspace_members", headers=headers, params={"workspace_id": f"eq.{workspace_id}"})
                client.delete("/rest/v1/workspaces", headers=headers, params={"id": f"eq.{workspace_id}"})
        if user_a_id:
            admin_delete_user(user_a_id)
        if user_b_id:
            admin_delete_user(user_b_id)
        print("Cleanup done.")

    print("\n=== SUMMARY ===")
    failed = [r for r in results if r[0] == "FAIL"]
    for status, name, _detail in results:
        print(f"{status}: {name}")
    print(f"\n{len(results) - len(failed)}/{len(results)} checks passed.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
