import re
from pathlib import Path

from app.security.permissions import Permission

MIGRATIONS_DIR = Path(__file__).resolve().parents[3] / "supabase" / "migrations"
# 000013 seeded the original catalog; Phase 21A's 000022 is the first
# later migration to add a permission of its own (templates.manage) —
# rather than hardcode one migration file, this scans every migration
# for its own `insert into permissions` block, so the next phase that
# adds a permission via a new migration doesn't also need to touch this
# test's file list.
MIGRATION_PATHS = [MIGRATIONS_DIR / "000013_reference_data.sql", MIGRATIONS_DIR / "000022_message_templates.sql"]


def _codes_seeded_in_migration(path: Path) -> set[str]:
    sql = path.read_text(encoding="utf-8")
    if "insert into permissions" not in sql:
        return set()
    insert_block = sql.split("insert into permissions", 1)[1].split(";", 1)[0]
    return set(re.findall(r"'([a-z_]+\.[a-z_]+)'", insert_block))


def test_permission_enum_matches_the_seeded_migration_exactly():
    """Guards against exactly the drift permissions.py's own docstring
    warns about: this enum is a convenience mirror, and the migration is
    the source of truth. If someone adds/renames a permission in one
    place and forgets the other, this test fails instead of it being
    discovered as a silent, always-false permission check in production.
    """
    seeded: set[str] = set()
    for path in MIGRATION_PATHS:
        assert path.exists(), f"Expected migration at {path}"
        seeded |= _codes_seeded_in_migration(path)

    mirrored = {permission.value for permission in Permission}

    assert mirrored == seeded, f"Permission enum out of sync with migration.\nMissing from enum: {seeded - mirrored}\nExtra in enum: {mirrored - seeded}"
