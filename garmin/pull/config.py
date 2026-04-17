from __future__ import annotations

import json
import logging
from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

logger = logging.getLogger(__name__)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # Databricks connectivity (ZeroBus service principal)
    databricks_workspace_url: str = ""
    zerobus_server_endpoint: str = ""
    databricks_client_id: str = ""
    databricks_client_secret: str = ""

    # Unity Catalog target — supplied via env vars (see env.example).
    # DATABRICKS_CATALOG is required; schema/table have sensible defaults.
    databricks_catalog: str = ""
    databricks_schema: str = "wearables"
    databricks_bronze_table: str = "wearables_zerobus"

    # Garmin credentials
    garmin_email: str = ""
    garmin_password: str = ""
    garmin_tokenstore: Path = Path.home() / ".garminconnect"

    # Garmin device identifier (for the device_id field in events)
    garmin_device_id: str = "garmin_forerunner_265"

    # Databricks Secrets — shared scope provisioned by infra bundle
    secret_scope: str = "dbxw_zerobus_credentials"
    garmin_token_secret_key: str = "garmin_oauth_tokens"

    @property
    def bronze_table_fqn(self) -> str:
        return f"{self.databricks_catalog}.{self.databricks_schema}.{self.databricks_bronze_table}"

    @property
    def zerobus_configured(self) -> bool:
        return bool(
            self.zerobus_server_endpoint
            and self.databricks_workspace_url
            and self.databricks_client_id
            and self.databricks_client_secret
        )

    @property
    def garmin_configured(self) -> bool:
        return bool(self.garmin_email and self.garmin_password)

    @property
    def garmin_tokens_exist(self) -> bool:
        token_file = self.garmin_tokenstore / "garmin_tokens.json"
        return token_file.is_file()

    def load_garmin_tokens_from_secret(self, secret_json: str) -> None:
        """Write Garmin tokens from a Databricks Secret to the local tokenstore.

        Called from notebooks where tokens are stored in Databricks Secrets
        rather than on disk.
        """
        self.garmin_tokenstore.mkdir(parents=True, exist_ok=True)
        token_path = self.garmin_tokenstore / "garmin_tokens.json"
        token_path.write_text(secret_json)
        logger.info("Wrote Garmin tokens to %s", token_path)

    def save_garmin_tokens_to_json(self) -> str:
        """Read the current tokens from disk and return as a JSON string.

        Used to write refreshed tokens back to Databricks Secrets.
        """
        token_path = self.garmin_tokenstore / "garmin_tokens.json"
        if not token_path.is_file():
            return ""
        return token_path.read_text()


@lru_cache
def get_settings() -> Settings:
    return Settings()
