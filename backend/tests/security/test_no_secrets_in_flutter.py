"""Phase 21 — Security Hardening §"Secrets": locks in "the Flutter app
never receives service-role credentials" as a permanent regression
check, not just a one-time audit finding. Scans the actual `mobile/`
source tree (not this backend's own files, which legitimately reference
"service_role" as a config/variable name) for the literal terms a
leaked secret would use.
"""

from pathlib import Path

MOBILE_LIB_DIR = Path(__file__).resolve().parents[3] / "mobile" / "lib"

_FORBIDDEN_TERMS = ("service_role", "SERVICE_ROLE", "SUPABASE_SERVICE_ROLE_KEY")

# Files that legitimately mention the *name* "service role" in prose
# (a comment explaining why it must never appear here) without ever
# containing a real key — reviewed by hand, not a blanket exemption.
_ALLOWED_MENTIONS = {"supabase_service.dart"}


def _dart_files() -> list[Path]:
    assert MOBILE_LIB_DIR.exists(), f"Expected {MOBILE_LIB_DIR} to exist"
    return list(MOBILE_LIB_DIR.rglob("*.dart"))


def test_flutter_source_never_references_the_service_role_key():
    offenders = []
    for path in _dart_files():
        if path.name in _ALLOWED_MENTIONS:
            continue
        text = path.read_text(encoding="utf-8")
        if any(term in text for term in _FORBIDDEN_TERMS):
            offenders.append(str(path))
    assert offenders == [], f"Flutter source references a service-role term: {offenders}"


def test_flutter_env_files_only_ever_declare_the_anon_key_not_a_service_role_key():
    env_dir = MOBILE_LIB_DIR.parent / "env"
    if not env_dir.exists():
        return
    for path in env_dir.glob(".env.*"):
        text = path.read_text(encoding="utf-8")
        assert "SERVICE_ROLE" not in text.upper(), f"{path} must never declare a service-role key"


def test_supabase_service_dart_only_ever_initializes_with_the_anon_key():
    """The one file allowed to mention "service role" in prose (to
    document why it never appears) must still never actually configure
    one — asserts the real initialize() call uses the anon key."""
    target = MOBILE_LIB_DIR / "services" / "supabase" / "supabase_service.dart"
    assert target.exists()
    text = target.read_text(encoding="utf-8")
    assert "supabaseAnonKey" in text
    assert "SERVICE_ROLE" not in text.upper()
