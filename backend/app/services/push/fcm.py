"""FCM HTTP v1 sender — the one place a Firebase dependency lives.

Mirrors services/ai/provider.py's shape: a single `get_fcm_sender()`
factory that returns `None` when the prerequisites aren't met, and every
caller treats `None` as "push unavailable" and moves on. No Firebase
project is configured for this repository today, so this always returns
`None` — wiring it is a config step, not a code change.
"""

import json
from functools import lru_cache

import httpx

from app.core.config import get_settings
from app.core.logging import get_logger

logger = get_logger(__name__)

_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_ENDPOINT = "https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"


class FcmSender:
    """Sends one data+notification message per device token via FCM
    HTTP v1. Constructed only when a service account and project id are
    both present (see get_fcm_sender)."""

    def __init__(self, project_id: str, credentials):
        self._project_id = project_id
        self._credentials = credentials
        self._url = _ENDPOINT.format(project_id=project_id)

    def _bearer(self) -> str:
        from google.auth.transport.requests import Request  # local import: optional dep

        if not self._credentials.valid:
            self._credentials.refresh(Request())
        return self._credentials.token

    def send(self, *, token: str, title: str, body: str | None, data: dict[str, str]) -> bool:
        """Returns True on a 2xx from FCM. A 404/UNREGISTERED means the
        token is dead — the caller should delete it. Never raises."""
        message = {
            "message": {
                "token": token,
                "notification": {"title": title, **({"body": body} if body else {})},
                # data values must be strings for FCM v1
                "data": {k: str(v) for k, v in data.items()},
                "android": {"priority": "high"},
            }
        }
        try:
            resp = httpx.post(
                self._url,
                headers={"Authorization": f"Bearer {self._bearer()}", "Content-Type": "application/json"},
                json=message,
                timeout=10,
            )
        except httpx.HTTPError as exc:
            logger.warning("FCM send failed (network): %s", exc)
            return False
        if resp.status_code // 100 == 2:
            return True
        if resp.status_code == 404 or "UNREGISTERED" in resp.text:
            logger.info("FCM token no longer registered; caller should prune it")
            return False
        logger.warning("FCM send failed: %s %s", resp.status_code, resp.text[:300])
        return False


@lru_cache
def get_fcm_sender() -> FcmSender | None:
    settings = get_settings()
    if not settings.fcm_project_id or not settings.fcm_service_account_json:
        return None

    try:
        from google.oauth2 import service_account  # optional dep — only needed with FCM configured
    except ImportError:
        logger.warning("fcm_* is set but google-auth is not installed; push disabled")
        return None

    raw = settings.fcm_service_account_json
    try:
        info = json.loads(raw) if raw.lstrip().startswith("{") else json.load(open(raw, encoding="utf-8"))
        credentials = service_account.Credentials.from_service_account_info(info, scopes=[_SCOPE])
    except (json.JSONDecodeError, OSError, ValueError) as exc:
        logger.error("fcm_service_account_json is set but unreadable: %s", exc)
        return None

    return FcmSender(settings.fcm_project_id, credentials)
