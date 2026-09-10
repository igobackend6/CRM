from typing import Any
from uuid import UUID

from app.core.logging import get_logger
from app.core.supabase_client import get_supabase_client
from app.repositories.device_tokens import DeviceTokenRepository
from app.services.push.fcm import get_fcm_sender

logger = get_logger(__name__)


def push_to_member(
    workspace_id: UUID,
    member_id: str,
    *,
    title: str,
    body: str | None = None,
    data: dict[str, Any] | None = None,
) -> None:
    """Send an OS-level push to every device the given workspace member
    has registered. A side channel alongside `notify()` — the in-app
    notification row is written separately (by the on_lead_assignment
    trigger, or notify()); this only adds the push.

    Never raises: a failed or unavailable push must not break the
    operation that triggered it. No-ops (with a log line) when:
      * no Firebase project is configured (get_fcm_sender() -> None)
      * the service-role client is unavailable
      * the member has no registered devices

    Uses the service-role client because it reads device_tokens across
    profiles (device_tokens RLS only lets a user see their own).
    """
    sender = get_fcm_sender()
    if sender is None:
        logger.debug("Push not configured; skipping push to member %s", member_id)
        return

    client = get_supabase_client()
    if client is None:
        logger.warning("Service-role client unavailable; skipping push")
        return

    repo = DeviceTokenRepository(client)
    try:
        rows = repo.list_for_member(workspace_id, member_id)
    except Exception:  # noqa: BLE001 — a push must never break the caller
        logger.exception("Could not load device tokens for member %s", member_id)
        return

    payload = {k: str(v) for k, v in (data or {}).items()}
    dead: list[str] = []
    for row in rows:
        token = row["token"]
        try:
            ok = sender.send(token=token, title=title, body=body, data=payload)
        except Exception:  # noqa: BLE001
            logger.exception("Push send raised for one token; continuing")
            continue
        if not ok:
            dead.append(token)

    if dead:
        try:
            repo.delete_tokens(dead)
        except Exception:  # noqa: BLE001
            logger.warning("Could not prune %d dead device token(s)", len(dead))
