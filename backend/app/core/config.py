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

    @property
    def is_production(self) -> bool:
        return self.environment == "production"


@lru_cache
def get_settings() -> Settings:
    return Settings()
