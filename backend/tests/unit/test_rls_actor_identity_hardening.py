"""Phase 21 — Security Hardening regression test.

This is a SOURCE-level guard, not a live-Postgres/RLS execution test —
mirrors test_permissions.py's own established pattern of parsing a
migration file directly, since this repository has no live Postgres to
actually execute policies against (Docker unavailable; see every prior
phase's own "no live Postgres/RLS validation" note). It proves the
policy text a P1 finding required is present and can't be silently
reverted by a future migration edit — it does NOT prove Postgres would
enforce it correctly at runtime.
"""

from pathlib import Path

MIGRATION_PATH = (
    Path(__file__).resolve().parents[3] / "supabase" / "migrations" / "000021_rls_actor_identity_hardening.sql"
)


def _sql() -> str:
    return MIGRATION_PATH.read_text(encoding="utf-8")


def test_migration_file_exists():
    assert MIGRATION_PATH.exists(), f"Expected migration at {MIGRATION_PATH}"


def _policy_body(sql: str, policy_name: str) -> str:
    """The `create policy <name> ...` statement's own text, up to the
    next `drop policy` or end of file — good enough to assert the
    expected WITH CHECK fragment appears within the right policy, not
    just somewhere in the file."""
    marker = f"create policy {policy_name} "
    assert marker in sql, f"Expected to find '{marker}' in the migration"
    start = sql.index(marker)
    rest = sql[start + len(marker) :]
    next_drop = rest.find("\ndrop policy")
    return rest[: next_drop if next_drop != -1 else len(rest)]


def test_leads_insert_requires_the_actor_to_be_the_declared_creator_and_assignee():
    body = _policy_body(_sql(), "leads_insert")
    assert "created_by_member_id = current_member_id(workspace_id)" in body
    assert "assigned_member_id = current_member_id(workspace_id)" in body


def test_follow_ups_insert_requires_the_actor_to_be_the_declared_creator():
    body = _policy_body(_sql(), "follow_ups_insert")
    assert "created_by_member_id = current_member_id(workspace_id)" in body


def test_allocations_insert_requires_the_actor_to_be_the_declared_assigner():
    body = _policy_body(_sql(), "allocations_insert")
    assert "assigned_by_member_id = current_member_id(workspace_id)" in body


def test_interactions_insert_requires_the_actor_to_be_the_declared_author():
    body = _policy_body(_sql(), "interactions_insert")
    assert "actor_member_id = current_member_id(workspace_id)" in body


def test_lead_documents_insert_requires_the_actor_to_be_the_declared_uploader():
    body = _policy_body(_sql(), "lead_documents_insert")
    assert "uploaded_by_member_id = current_member_id(workspace_id)" in body


def test_ai_call_insights_insert_requires_the_actor_to_be_the_declared_requester():
    body = _policy_body(_sql(), "ai_call_insights_insert")
    assert "requested_by_member_id = current_member_id(workspace_id)" in body


def test_workspace_members_insert_restricts_which_roles_invite_only_can_grant():
    body = _policy_body(_sql(), "workspace_members_insert")
    assert "members.manage" in body
    assert "'team_mate', 'manager'" in body


def test_every_hardened_policy_is_reproduced_as_a_full_drop_and_recreate():
    """Never edit an existing, already-applied migration (000014/000019/
    000020) — this phase's fix is a NEW migration that drops and
    recreates each affected policy in full."""
    sql = _sql()
    for policy in (
        "leads_insert",
        "follow_ups_insert",
        "allocations_insert",
        "interactions_insert",
        "lead_documents_insert",
        "ai_call_insights_insert",
        "workspace_members_insert",
    ):
        assert f"drop policy {policy} on" in sql
        assert f"create policy {policy} " in sql
