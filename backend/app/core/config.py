from functools import lru_cache
from typing import Optional
from pydantic import Field, HttpUrl
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime settings loaded from environment variables.

    The repo root `.env` is supported for local development, but secrets must be
    provided by deployment secret storage in production.
    """

    app_name: str = "CamGuard API"
    api_v1_prefix: str = "/api/v1"
    supabase_url: HttpUrl = Field(alias="NEXT_PUBLIC_SUPABASE_URL")
    supabase_publishable_key: str = Field(alias="NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY")
    supabase_secret_key: Optional[str] = Field(default=None, alias="SUPABASE_SECRET_KEY")
    auth_email_redirect_to: Optional[str] = Field(default=None, alias="CAMGUARD_AUTH_EMAIL_REDIRECT_TO")
    request_timeout_seconds: float = 15.0

    model_config = SettingsConfigDict(
        env_file=("../.env", ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    @property
    def supabase_auth_url(self) -> str:
        return f"{str(self.supabase_url).rstrip('/')}/auth/v1"

    @property
    def supabase_rest_url(self) -> str:
        return f"{str(self.supabase_url).rstrip('/')}/rest/v1"


@lru_cache
def get_settings() -> Settings:
    return Settings()
