from functools import lru_cache
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Centralized backend configuration, sourced from environment
    variables / a local .env file. Never hardcode secrets here — this
    class only declares the *shape* of configuration.
    """

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    environment: Literal["development", "staging", "production"] = "development"
    log_level: str = "INFO"

    api_v1_prefix: str = "/api/v1"

    supabase_url: str | None = None
    supabase_service_role_key: str | None = None
    supabase_anon_key: str | None = None
    supabase_jwt_secret: str | None = None

    # Phase 20 — AI Call Insights. Both unset in every environment today
    # (no AI provider is configured in this repository — see the Phase 20
    # completion report's dependency note); `services/ai/provider.py`
    # treats "either is missing" as "no provider available" and never
    # fabricates a result. Never hardcode a real value here or in
    # .env.example — only ever sourced from a real deployment's own
    # environment/secret store.
    ai_provider: str | None = None
    ai_provider_api_key: str | None = None

    # Phase 4 — FCM push on lead assignment. All unset in every
    # environment today (no Firebase project is configured for this
    # repository). `services/push/service.py` treats "any of these
    # missing" as "push unavailable" and no-ops silently — the in-app
    # notification (notifications table + Realtime) is unaffected.
    # Never hardcode real values here or in .env.example.
    #   fcm_project_id            — the Firebase project id
    #   fcm_service_account_json  — path to, OR inline JSON of, a service
    #                               account key with the FCM send scope
    fcm_project_id: str | None = None
    fcm_service_account_json: str | None = None

    # Shared secret a Supabase Database Webhook presents when calling the
    # internal push endpoint (POST /internal/push/notification), so an
    # admin-panel-initiated assignment can trigger a push too. Unset =
    # the internal endpoint 404s.
    internal_webhook_secret: str | None = None

    @property
    def is_production(self) -> bool:
        return self.environment == "production"


@lru_cache
def get_settings() -> Settings:
    return Settings()
