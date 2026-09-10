import re
import uuid
from pathlib import PurePosixPath
from uuid import UUID

from app.core.exceptions import ValidationError

# Phase 21A §2/§"Security". A conservative, explicit allowlist (not a
# denylist) for both the file extension and the client-reported MIME
# type — the two are checked independently (§2 "Validate MIME type" /
# "Validate extension" are listed as separate steps) so a renamed
# executable can't slip through on a spoofed extension alone, or vice
# versa. Deliberately small: covers what a sales team actually attaches
# to a lead (contracts, ids, spreadsheets, photos), not a general
# file-sharing surface.
ALLOWED_EXTENSIONS = {".pdf", ".doc", ".docx", ".xls", ".xlsx", ".png", ".jpg", ".jpeg", ".txt", ".csv"}
ALLOWED_MIME_TYPES = {
    "application/pdf",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.ms-excel",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "image/png",
    "image/jpeg",
    "text/plain",
    "text/csv",
}

MAX_SIZE_BYTES = 25 * 1024 * 1024  # 25MB — generous for scanned contracts/ids, small enough to keep the bucket sane.

_UNSAFE_CHARS = re.compile(r"[^A-Za-z0-9 ._-]")
_MAX_FILENAME_LENGTH = 150


def validate_upload(*, file_name: str, mime_type: str | None, size_bytes: int) -> None:
    """Raises ValidationError (422) on the first failed check. Called
    before anything touches Storage or the database — an invalid upload
    never reaches either."""
    if size_bytes <= 0:
        raise ValidationError("File is empty.", error_code="empty_file")
    if size_bytes > MAX_SIZE_BYTES:
        raise ValidationError("File exceeds the 25MB size limit.", error_code="file_too_large")

    extension = PurePosixPath(file_name).suffix.lower()
    if extension not in ALLOWED_EXTENSIONS:
        raise ValidationError(f"File extension {extension or '(none)'} is not allowed.", error_code="invalid_extension")

    if mime_type not in ALLOWED_MIME_TYPES:
        raise ValidationError(f"File type {mime_type or '(unknown)'} is not allowed.", error_code="invalid_mime_type")


def sanitize_filename(file_name: str) -> str:
    """Never trusts the client-supplied name as a path. `PurePosixPath(...).name`
    strips any directory component (so "../../etc/passwd" becomes just
    "passwd") and any embedded ".." segment is neutralized the same way —
    there is no path separator left in the result for one to hide in.
    The remaining name is then limited to a safe character set, so
    nothing in it can be (mis)interpreted as a path segment, control
    character, or shell-meaningful token once it becomes part of a
    Storage object path."""
    name = PurePosixPath(file_name.replace("\\", "/")).name or "file"
    name = name.replace("..", "_")
    name = _UNSAFE_CHARS.sub("_", name).strip()
    name = re.sub(r"\s+", " ", name).strip(" ._") or "file"
    if len(name) > _MAX_FILENAME_LENGTH:
        stem, _, ext = name.rpartition(".")
        ext = f".{ext}" if stem else ""
        name = (stem or name)[: _MAX_FILENAME_LENGTH - len(ext)] + ext
    return name


def build_storage_path(workspace_id: UUID, lead_id: UUID, safe_file_name: str) -> str:
    """Server-derived only — the client never supplies or influences a
    storage path (§"Never trust client-provided workspace/member
    identity" / "no client-controlled storage path"). The
    `{workspace_id}/{lead_id}/...` prefix matches storage.objects RLS's
    own assumption (000015_storage.sql: `storage.foldername(name)[1]` is
    the workspace_id); a random prefix on the filename itself guarantees
    uniqueness against `lead_documents.storage_path`'s own `unique`
    constraint even when the same file is uploaded twice."""
    return f"{workspace_id}/{lead_id}/{uuid.uuid4().hex}_{safe_file_name}"
