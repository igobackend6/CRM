from typing import Any

from supabase import Client

BUCKET = "lead-documents"


class DocumentStorage:
    """Thin wrapper over the Supabase Storage API for the private
    `lead-documents` bucket (supabase/migrations/000015_storage.sql).
    Always constructed with a request-scoped, user-authenticated
    `Client` (never the service-role client) — `storage.objects` RLS
    (the same migration's 3 policies) is the real access boundary, not
    this class; every call here still goes through it exactly as if
    Flutter had called Supabase Storage directly.

    `path` is always the object's path *within* the bucket (e.g.
    "{workspace_id}/{lead_id}/{uuid}_{filename}", see
    services/documents/validation.py.build_storage_path) — never
    prefixed with the bucket id, matching this SDK's own
    `from_(bucket).upload(path, ...)` convention.
    """

    def __init__(self, client: Client):
        # Lazily resolves `.storage.from_(...)` on first actual use
        # rather than at construction — DocumentService builds one of
        # these per request regardless of which method (if any) a given
        # request ends up calling, and test doubles standing in for
        # `Client` (e.g. FakeSupabaseClient) have no `.storage` attribute
        # at all, only the real Storage-calling paths need it.
        self._client = client

    @property
    def _bucket(self):
        return self._client.storage.from_(BUCKET)

    def upload(self, path: str, content: bytes, *, mime_type: str) -> None:
        self._bucket.upload(path, content, {"content-type": mime_type})

    def create_signed_url(self, path: str, *, expires_in: int) -> str:
        result: dict[str, Any] = self._bucket.create_signed_url(path, expires_in)
        url = result.get("signedURL") or result.get("signedUrl")
        if not url:
            raise RuntimeError(f"Storage did not return a signed URL for {path!r}.")
        return url

    def remove(self, path: str) -> None:
        self._bucket.remove([path])
