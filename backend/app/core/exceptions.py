class AppError(Exception):
    """Base type for every handled application error. Feature services
    raise one of the typed subclasses below (or a further subclass added
    alongside a later feature) rather than a bare AppError, so the error
    handler in core/errors.py can map it to the right HTTP status without
    each route guessing status codes itself.
    """

    status_code: int = 500
    error_code: str = "internal_error"

    def __init__(self, message: str, *, error_code: str | None = None):
        super().__init__(message)
        self.message = message
        if error_code is not None:
            self.error_code = error_code


class ValidationError(AppError):
    """Input failed a business-rule check that Pydantic's schema
    validation can't express (e.g. a cross-field constraint)."""

    status_code = 422
    error_code = "validation_error"


class UnauthorizedError(AppError):
    """No valid authenticated identity (missing/invalid/expired token)."""

    status_code = 401
    error_code = "unauthorized"


class PermissionDeniedError(AppError):
    """Authenticated, but not permitted to perform this action — the
    has_permission()/RLS check on the database failed. Kept generic here
    (no leads/calls-specific subclass) since Phase 3 has no CRM features
    yet; feature phases raise this directly, passing a specific message.
    """

    status_code = 403
    error_code = "permission_denied"


class NotFoundError(AppError):
    """The requested resource doesn't exist, or isn't visible to the
    caller under RLS — deliberately the same response either way, so a
    caller can't distinguish "doesn't exist" from "exists in a workspace
    you can't see" by probing.
    """

    status_code = 404
    error_code = "not_found"


class ConflictError(AppError):
    """The request conflicts with current state (e.g. a unique
    constraint violation surfaced from the database)."""

    status_code = 409
    error_code = "conflict"
