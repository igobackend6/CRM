from pydantic import BaseModel

# DocumentOut/DocumentListResponse already exist (schemas/customer360.py,
# Phase 8) and are reused verbatim here — same metadata-only shape, same
# reason to omit storage_path (see that module's docstring). No new
# schema duplicates them; this module only adds what Phase 8 never
# needed: a signed-URL response for preview/download.


class SignedUrlResponse(BaseModel):
    """A short-lived, authorized download/preview URL (§3 "Preview"/
    "Download"). Never a permanent or public URL — see
    DocumentService.SIGNED_URL_EXPIRES_IN_SECONDS."""

    url: str
    expires_in: int
