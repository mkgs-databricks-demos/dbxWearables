"""Python mirror of the AppKit ``WearableConnector`` interface.

The AppKit Node gateway hosts per-provider plugins that implement the
TypeScript ``WearableConnector`` interface (in
``app/plugins/wearable-core/src/connector.ts``) for the webhook / OAuth
paths. The Lakeflow fanout notebook cannot import TypeScript, so every
provider that supports the pull-based path also exposes a Python class
that satisfies ``ConnectorProtocol`` below. The two contracts cover the
same concepts — webhook handling lives on the TS side, pull_batch lives
on the Python side, OAuth start/callback lives only on TS.

Registering a connector
-----------------------

Each ``providers/<name>/pull/__init__.py`` registers its implementation:

    from providers.common.connector_protocol import register_connector
    from providers.garmin.pull.connector import GarminPullConnector

    register_connector(GarminPullConnector())

The fanout notebook then calls ``get_connector(provider_name).pull_batch(...)``.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from typing import Any, Protocol, runtime_checkable


@dataclass(frozen=True)
class DateRange:
    start: date
    end: date


@dataclass
class BronzeRow:
    """Canonical bronze row shape emitted by every connector.

    Mirrors the shape produced by ``AppKit.wearableCore.bronzeWriter`` on
    the TS side, so the fanout job and the webhook path write identical
    rows to the ``wearables_zerobus`` bronze table.
    """

    record_id: str
    ingested_at: str  # ISO 8601 UTC
    body: str         # JSON string — ZeroBus SDK ingests as VARIANT
    headers: str      # JSON string — VARIANT
    record_type: str


@runtime_checkable
class ConnectorProtocol(Protocol):
    """Every provider's Python pull implementation must satisfy this."""

    provider: str  # e.g. "garmin", "fitbit"

    def record_types(self) -> list[str]:
        """Return the record_type values this connector can produce."""

    def pull_batch(
        self,
        user_id: str,
        provider_user_id: str,
        range: DateRange,
        **kwargs: Any,
    ) -> list[BronzeRow]:
        """Extract data for a user over a date range and return bronze rows.

        Implementations must:
        - Look up OAuth tokens via the ``CredentialStore`` (do not accept raw tokens).
        - Respect the vendor's rate limits — this method is called inside the
          fanout notebook which manages per-provider QPS.
        - Raise ``ProviderRateLimitError`` on HTTP 429 so the fanout can back off.
        - Return an empty list when the user has no new data (never None).
        """


class ProviderRateLimitError(RuntimeError):
    """Raised when a provider responds with HTTP 429 or equivalent."""


_REGISTRY: dict[str, ConnectorProtocol] = {}


def register_connector(connector: ConnectorProtocol) -> None:
    _REGISTRY[connector.provider] = connector


def get_connector(provider: str) -> ConnectorProtocol:
    if provider not in _REGISTRY:
        raise KeyError(
            f"No pull connector registered for provider '{provider}'. "
            f"Check providers/{provider}/pull/__init__.py."
        )
    return _REGISTRY[provider]


def list_registered() -> list[str]:
    return sorted(_REGISTRY.keys())
