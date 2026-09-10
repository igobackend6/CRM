"""Phase 21A — source-level guard mirroring test_rls_actor_identity_hardening.py's
own established pattern (parsing a migration file directly, since this
repository has no live Postgres to execute policies against — see that
file's docstring for the full rationale). Proves the RLS/permission
shape 000022 is supposed to have is actually present in the file, not a
substitute for live-Postgres/RLS validation."""

from pathlib import Path

MIGRATION_PATH = Path(__file__).resolve().parents[3] / "supabase" / "migrations" / "000022_message_templates.sql"


def _sql() -> str:
    return MIGRATION_PATH.read_text(encoding="utf-8")


def test_migration_file_exists():
    assert MIGRATION_PATH.exists(), f"Expected migration at {MIGRATION_PATH}"


def test_message_templates_table_is_workspace_scoped_with_rls_enabled():
    sql = _sql()
    assert "workspace_id uuid not null references workspaces" in sql
    assert "alter table message_templates enable row level security" in sql


def test_select_policy_only_requires_workspace_membership():
    sql = _sql()
    assert "create policy message_templates_select" in sql
    assert "is_workspace_member(workspace_id)" in sql


def test_write_policies_require_templates_manage_permission():
    sql = _sql()
    for policy in ("message_templates_insert", "message_templates_update", "message_templates_delete"):
        assert f"create policy {policy}" in sql
    assert sql.count("has_permission(workspace_id, 'templates.manage')") >= 3


def test_insert_policy_enforces_actor_identity_like_phase_21s_hardening_pass():
    """Same rule 000021_rls_actor_identity_hardening.sql established for
    every other actor-column INSERT policy — this table must not ship
    with the gap that migration closed elsewhere."""
    sql = _sql()
    assert "created_by_member_id is null or created_by_member_id = current_member_id(workspace_id)" in sql


def test_unique_index_prevents_duplicate_names_per_workspace():
    sql = _sql()
    assert "create unique index message_templates_workspace_name_idx on message_templates (workspace_id, lower(name))" in sql


def test_templates_manage_permission_is_seeded_and_granted_to_every_role():
    sql = _sql()
    assert "'templates.manage'" in sql
    assert "r.name in ('team_mate', 'manager', 'admin', 'ceo')" in sql
