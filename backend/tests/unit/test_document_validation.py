from uuid import uuid4

import pytest

from app.core.exceptions import ValidationError
from app.services.documents.validation import build_storage_path, sanitize_filename, validate_upload

WORKSPACE_ID = uuid4()
LEAD_ID = uuid4()


# ---- validate_upload ----


def test_accepts_an_allowed_pdf():
    validate_upload(file_name="contract.pdf", mime_type="application/pdf", size_bytes=1024)  # must not raise


def test_rejects_a_disallowed_extension():
    with pytest.raises(ValidationError) as exc:
        validate_upload(file_name="script.exe", mime_type="application/pdf", size_bytes=1024)
    assert exc.value.error_code == "invalid_extension"


def test_rejects_a_disallowed_mime_type_even_with_an_allowed_extension():
    """Extension and MIME type are checked independently — a
    `.pdf`-named file claiming an executable MIME type must still be
    rejected, and vice versa (test_rejects_a_disallowed_extension)."""
    with pytest.raises(ValidationError) as exc:
        validate_upload(file_name="contract.pdf", mime_type="application/x-msdownload", size_bytes=1024)
    assert exc.value.error_code == "invalid_mime_type"


def test_rejects_zero_byte_files():
    with pytest.raises(ValidationError) as exc:
        validate_upload(file_name="contract.pdf", mime_type="application/pdf", size_bytes=0)
    assert exc.value.error_code == "empty_file"


def test_rejects_files_over_the_size_limit():
    with pytest.raises(ValidationError) as exc:
        validate_upload(file_name="contract.pdf", mime_type="application/pdf", size_bytes=25 * 1024 * 1024 + 1)
    assert exc.value.error_code == "file_too_large"


def test_accepts_a_file_exactly_at_the_size_limit():
    validate_upload(file_name="contract.pdf", mime_type="application/pdf", size_bytes=25 * 1024 * 1024)  # must not raise


# ---- sanitize_filename ----


def test_strips_directory_components():
    assert sanitize_filename("../../etc/passwd") == "passwd"
    assert sanitize_filename("a/b/c/report.pdf") == "report.pdf"


def test_strips_windows_style_path_separators_too():
    assert sanitize_filename("..\\..\\windows\\system32\\evil.pdf") == "evil.pdf"


def test_neutralizes_embedded_double_dot_segments():
    result = sanitize_filename("weird..name.pdf")
    assert ".." not in result


def test_replaces_unsafe_characters():
    result = sanitize_filename('a<script>alert(1)</script>.pdf')
    assert "<" not in result and ">" not in result and "(" not in result


def test_falls_back_to_a_default_name_when_nothing_safe_remains():
    assert sanitize_filename("../../../") == "file"


def test_truncates_very_long_filenames_while_preserving_the_extension():
    long_name = ("a" * 300) + ".pdf"
    result = sanitize_filename(long_name)
    assert len(result) <= 150
    assert result.endswith(".pdf")


# ---- build_storage_path ----


def test_build_storage_path_is_namespaced_by_workspace_and_lead():
    path = build_storage_path(WORKSPACE_ID, LEAD_ID, "report.pdf")
    assert path.startswith(f"{WORKSPACE_ID}/{LEAD_ID}/")
    assert path.endswith("report.pdf")


def test_build_storage_path_is_unique_across_calls_for_the_same_filename():
    first = build_storage_path(WORKSPACE_ID, LEAD_ID, "report.pdf")
    second = build_storage_path(WORKSPACE_ID, LEAD_ID, "report.pdf")
    assert first != second
