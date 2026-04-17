"""Canonical silver-layer event schema shared across every wearable provider.

Every bronze row in ``wearables_zerobus`` — regardless of source (phone-SDK
client, vendor webhook, Lakeflow pull job) — is projected by the silver
Spark Declarative Pipeline into a ``HealthEvent``. Gold pipelines consume
``silver_health_events`` and never need to know which vendor a given row
came from.

Each provider contributes a ``providers/<name>/silver/normalizer.py`` that
maps the raw VARIANT ``body`` + ``headers`` pair to zero or more
``HealthEvent`` rows.

Extracted from the original per-provider ``providers/garmin/pull/normalizer.py``
so the type is the single source of truth across connectors.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import Any


@dataclass
class HealthEvent:
    """Normalized health event for the silver layer.

    Fields:
        source:       Origin identifier. Examples:
                      ``"garmin_connect"``, ``"garmin_connect_iq"``,
                      ``"fitbit_web_api"``, ``"whoop"``, ``"oura"``,
                      ``"apple_healthkit"``, ``"google_health_connect"``,
                      ``"samsung_health"``.
        user_id:      App-scoped user ID (UUID from ``app_users``).
                      May be empty for legacy single-user demo data.
        device_id:    Device identifier reported by the source.
        metric_type:  Metric name from the shared allow-list
                      (see ``providers/garmin/schema.md``).
        value:        Numeric measurement value.
        unit:         Unit of measurement (``bpm``, ``count``, ``minutes``, ...).
        recorded_at:  When the measurement was taken on the device.
        ingested_at:  When silver processed the row.
        metadata:     Optional string-keyed string-valued extras.
    """

    source: str
    device_id: str
    metric_type: str
    value: float
    unit: str
    recorded_at: datetime
    user_id: str = ""
    ingested_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    metadata: dict[str, str] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["recorded_at"] = self.recorded_at.isoformat()
        d["ingested_at"] = self.ingested_at.isoformat()
        d["metadata"] = {str(k): str(v) for k, v in self.metadata.items()}
        return d
