from __future__ import annotations

import json
import logging
import uuid
from dataclasses import asdict, dataclass, field
from datetime import date, datetime, timezone
from typing import Any

from garmin.pull.config import get_settings

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Bronze layer: raw VARIANT format for wearables_zerobus table
# ---------------------------------------------------------------------------

GARMIN_RECORD_TYPES = [
    "daily_stats",
    "heart_rates",
    "sleep",
    "stress",
    "hrv",
    "spo2",
    "body_battery",
    "steps",
    "respiration",
    "activities",
]


def to_bronze_row(
    raw_data: dict | list,
    record_type: str,
    device_id: str,
    target_date_iso: str,
) -> dict[str, Any]:
    """Wrap a raw Garmin API response into the wearables_zerobus VARIANT schema.

    Returns a dict with keys matching the bronze table columns:
    record_id, ingested_at, body, headers, record_type.
    The body and headers values are JSON strings suitable for ZeroBus
    RecordType.JSON ingestion (the SDK serializes them as VARIANT).
    """
    now = datetime.now(timezone.utc).isoformat()
    body = {
        "source": "garmin_connect",
        "device_id": device_id,
        "date": target_date_iso,
        "data": raw_data,
    }
    headers = {
        "Content-Type": "application/json",
        "X-Platform": "garmin_connect",
        "X-Record-Type": record_type,
        "X-Device-Id": device_id,
        "X-Upload-Timestamp": now,
    }
    return {
        "record_id": str(uuid.uuid4()),
        "ingested_at": now,
        "body": json.dumps(body, default=str),
        "headers": json.dumps(headers),
        "record_type": record_type,
    }


def to_bronze_rows(raw: dict, device_id: str | None = None) -> list[dict[str, Any]]:
    """Convert a full day extraction dict into a list of bronze rows.

    The input ``raw`` is the dict returned by ``extractor.extract_daily()``,
    keyed by Garmin API category with a ``date`` key for the target date.
    Each non-null category becomes one bronze row.
    """
    if device_id is None:
        device_id = get_settings().garmin_device_id

    target_date_iso = raw.get("date", "")
    rows: list[dict[str, Any]] = []

    category_map = {
        "stats": "daily_stats",
        "heart_rates": "heart_rates",
        "sleep": "sleep",
        "stress": "stress",
        "hrv": "hrv",
        "spo2": "spo2",
        "body_battery": "body_battery",
        "steps": "steps",
        "respiration": "respiration",
        "activities": "activities",
    }

    for extract_key, record_type in category_map.items():
        data = raw.get(extract_key)
        if data is not None:
            rows.append(to_bronze_row(data, record_type, device_id, target_date_iso))

    logger.info("Built %d bronze rows for %s", len(rows), target_date_iso)
    return rows


# ---------------------------------------------------------------------------
# Silver layer: normalized typed events (for future silver views/pipelines)
# ---------------------------------------------------------------------------


@dataclass
class HealthEvent:
    """Normalized health event for the silver layer.

    This typed, flat representation is used by silver-layer views and
    pipelines that parse the raw VARIANT body from the bronze table
    into strongly-typed metric records.
    """

    source: str
    device_id: str
    metric_type: str
    value: float
    unit: str
    recorded_at: datetime
    ingested_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    metadata: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["recorded_at"] = self.recorded_at.isoformat()
        d["ingested_at"] = self.ingested_at.isoformat()
        d["metadata"] = {str(k): str(v) for k, v in self.metadata.items()}
        return d


def _safe_float(val: object, default: float = 0.0) -> float:
    if val is None:
        return default
    try:
        return float(val)
    except (TypeError, ValueError):
        return default


def _day_timestamp(recorded_date: date) -> datetime:
    return datetime.combine(recorded_date, datetime.min.time(), tzinfo=timezone.utc)


def normalize(raw: dict) -> list[HealthEvent]:
    """Convert a raw Garmin daily extraction to a list of HealthEvents.

    This silver-layer normalization parses the raw API responses into
    strongly-typed metric events. Kept for use in silver pipelines
    and for dry-run / local file output workflows.
    """
    events: list[HealthEvent] = []
    settings = get_settings()
    device_id = settings.garmin_device_id
    recorded_date = date.fromisoformat(raw["date"])
    ts = _day_timestamp(recorded_date)

    _normalize_stats(raw.get("stats"), events, ts, device_id)
    _normalize_heart_rates(raw.get("heart_rates"), events, recorded_date, device_id)
    _normalize_sleep(raw.get("sleep"), events, ts, device_id)
    _normalize_stress(raw.get("stress"), events, recorded_date, device_id)
    _normalize_hrv(raw.get("hrv"), events, ts, device_id)
    _normalize_spo2(raw.get("spo2"), events, ts, device_id)
    _normalize_body_battery(raw.get("body_battery"), events, recorded_date, device_id)
    _normalize_respiration(raw.get("respiration"), events, ts, device_id)
    _normalize_activities(raw.get("activities"), events, device_id)

    logger.info("Normalized %d events for %s", len(events), recorded_date)
    return events


def _normalize_stats(
    stats: dict | None, events: list[HealthEvent], ts: datetime, device_id: str
) -> None:
    if not stats:
        return

    direct_mappings: list[tuple[str, str, str]] = [
        ("restingHeartRate", "heart_rate_resting", "bpm"),
        ("totalSteps", "steps_daily", "count"),
        ("activeKilocalories", "calories_active", "kcal"),
        ("totalKilocalories", "calories_total", "kcal"),
        ("vO2MaxValue", "vo2_max", "ml/kg/min"),
        ("floorsAscended", "floors_climbed", "count"),
        ("averageStressLevel", "stress_avg", "score"),
    ]

    for garmin_key, metric_type, unit in direct_mappings:
        val = stats.get(garmin_key)
        if val is not None:
            events.append(HealthEvent(
                source="garmin_connect",
                device_id=device_id,
                metric_type=metric_type,
                value=_safe_float(val),
                unit=unit,
                recorded_at=ts,
            ))

    moderate = _safe_float(stats.get("moderateIntensityMinutes"))
    vigorous = _safe_float(stats.get("vigorousIntensityMinutes"))
    if moderate > 0 or vigorous > 0:
        events.append(HealthEvent(
            source="garmin_connect",
            device_id=device_id,
            metric_type="intensity_minutes",
            value=moderate + vigorous,
            unit="minutes",
            recorded_at=ts,
            metadata={"moderate": str(int(moderate)), "vigorous": str(int(vigorous))},
        ))


def _normalize_heart_rates(
    hr_data: dict | None, events: list[HealthEvent], recorded_date: date, device_id: str
) -> None:
    if not hr_data:
        return

    heart_rate_values = hr_data.get("heartRateValues") or []
    for entry in heart_rate_values:
        if not isinstance(entry, (list, tuple)) or len(entry) < 2:
            continue
        ts_millis, hr_val = entry[0], entry[1]
        if hr_val is None or hr_val <= 0:
            continue
        try:
            ts = datetime.fromtimestamp(ts_millis / 1000.0, tz=timezone.utc)
        except (OSError, ValueError):
            continue
        events.append(HealthEvent(
            source="garmin_connect",
            device_id=device_id,
            metric_type="heart_rate_intraday",
            value=_safe_float(hr_val),
            unit="bpm",
            recorded_at=ts,
        ))


def _normalize_sleep(
    sleep_data: dict | None, events: list[HealthEvent], ts: datetime, device_id: str
) -> None:
    if not sleep_data:
        return

    dto = sleep_data.get("dailySleepDTO") or {}

    sleep_mappings: list[tuple[str, str, float, str]] = [
        ("sleepTimeSeconds", "sleep_duration", 60.0, "minutes"),
        ("deepSleepSeconds", "sleep_deep", 60.0, "minutes"),
        ("lightSleepSeconds", "sleep_light", 60.0, "minutes"),
        ("remSleepSeconds", "sleep_rem", 60.0, "minutes"),
        ("awakeSleepSeconds", "sleep_awake", 60.0, "minutes"),
        ("averageSpO2Value", "spo2_avg", 1.0, "pct"),
        ("averageRespirationValue", "respiration_avg", 1.0, "brpm"),
    ]

    for garmin_key, metric_type, divisor, unit in sleep_mappings:
        val = dto.get(garmin_key)
        if val is not None:
            events.append(HealthEvent(
                source="garmin_connect",
                device_id=device_id,
                metric_type=metric_type,
                value=_safe_float(val) / divisor,
                unit=unit,
                recorded_at=ts,
            ))

    sleep_scores = dto.get("sleepScores") or {}
    overall = sleep_scores.get("overall") or {}
    score_val = overall.get("value")
    if score_val is not None:
        events.append(HealthEvent(
            source="garmin_connect",
            device_id=device_id,
            metric_type="sleep_score",
            value=_safe_float(score_val),
            unit="score",
            recorded_at=ts,
        ))


def _normalize_stress(
    stress_data: dict | None, events: list[HealthEvent], recorded_date: date, device_id: str
) -> None:
    if not stress_data:
        return

    body_stress = stress_data.get("stressValuesArray") or []
    for entry in body_stress:
        if not isinstance(entry, (list, tuple)) or len(entry) < 2:
            continue
        ts_millis, stress_val = entry[0], entry[1]
        if stress_val is None or stress_val < 0:
            continue
        try:
            ts = datetime.fromtimestamp(ts_millis / 1000.0, tz=timezone.utc)
        except (OSError, ValueError):
            continue
        events.append(HealthEvent(
            source="garmin_connect",
            device_id=device_id,
            metric_type="stress_level",
            value=_safe_float(stress_val),
            unit="score",
            recorded_at=ts,
        ))


def _normalize_hrv(
    hrv_data: dict | None, events: list[HealthEvent], ts: datetime, device_id: str
) -> None:
    if not hrv_data:
        return

    summary = hrv_data.get("hrvSummary") or {}

    weekly_avg = summary.get("weeklyAvg")
    if weekly_avg is not None:
        events.append(HealthEvent(
            source="garmin_connect",
            device_id=device_id,
            metric_type="hrv_weekly_avg",
            value=_safe_float(weekly_avg),
            unit="ms",
            recorded_at=ts,
        ))

    last_night = summary.get("lastNight5MinHigh")
    if last_night is not None:
        events.append(HealthEvent(
            source="garmin_connect",
            device_id=device_id,
            metric_type="hrv_last_night",
            value=_safe_float(last_night),
            unit="ms",
            recorded_at=ts,
        ))

    status = summary.get("status")
    if status is not None:
        status_map = {"BALANCED": 2.0, "UNBALANCED": 1.0, "LOW": 0.0}
        status_val = status_map.get(str(status).upper(), -1.0)
        events.append(HealthEvent(
            source="garmin_connect",
            device_id=device_id,
            metric_type="hrv_status",
            value=status_val,
            unit="score",
            recorded_at=ts,
            metadata={"status_label": str(status)},
        ))


def _normalize_spo2(
    spo2_data: dict | None, events: list[HealthEvent], ts: datetime, device_id: str
) -> None:
    if not spo2_data:
        return

    avg_val = None
    if isinstance(spo2_data, dict):
        avg_val = spo2_data.get("averageSpO2") or spo2_data.get("averageSpO2Value")

    if avg_val is not None:
        events.append(HealthEvent(
            source="garmin_connect",
            device_id=device_id,
            metric_type="spo2",
            value=_safe_float(avg_val),
            unit="pct",
            recorded_at=ts,
        ))


def _normalize_body_battery(
    bb_data: list | dict | None, events: list[HealthEvent], recorded_date: date, device_id: str
) -> None:
    if not bb_data:
        return

    ts = _day_timestamp(recorded_date)

    if isinstance(bb_data, list):
        charged_vals = []
        for entry in bb_data:
            if not isinstance(entry, (list, tuple)) or len(entry) < 2:
                continue
            _, val = entry[0], entry[1]
            if val is not None and val > 0:
                charged_vals.append(float(val))

        if charged_vals:
            events.append(HealthEvent(
                source="garmin_connect",
                device_id=device_id,
                metric_type="body_battery_high",
                value=max(charged_vals),
                unit="score",
                recorded_at=ts,
            ))
            events.append(HealthEvent(
                source="garmin_connect",
                device_id=device_id,
                metric_type="body_battery_low",
                value=min(charged_vals),
                unit="score",
                recorded_at=ts,
            ))

    elif isinstance(bb_data, dict):
        for garmin_key, metric_type in [
            ("bodyBatteryHighestValue", "body_battery_high"),
            ("bodyBatteryLowestValue", "body_battery_low"),
        ]:
            val = bb_data.get(garmin_key)
            if val is not None:
                events.append(HealthEvent(
                    source="garmin_connect",
                    device_id=device_id,
                    metric_type=metric_type,
                    value=_safe_float(val),
                    unit="score",
                    recorded_at=ts,
                ))


def _normalize_respiration(
    resp_data: dict | None, events: list[HealthEvent], ts: datetime, device_id: str
) -> None:
    if not resp_data:
        return

    avg_val = None
    if isinstance(resp_data, dict):
        avg_val = resp_data.get("avgWakingRespirationValue") or resp_data.get("avgSleepRespirationValue")

    if avg_val is not None:
        events.append(HealthEvent(
            source="garmin_connect",
            device_id=device_id,
            metric_type="respiration_rate",
            value=_safe_float(avg_val),
            unit="brpm",
            recorded_at=ts,
        ))


def _normalize_activities(
    activities: list | None, events: list[HealthEvent], device_id: str
) -> None:
    if not activities:
        return

    for activity in activities:
        if not isinstance(activity, dict):
            continue

        activity_id = activity.get("activityId", "")
        activity_type = activity.get("activityType", {})
        type_key = activity_type.get("typeKey", "unknown") if isinstance(activity_type, dict) else "unknown"
        activity_name = activity.get("activityName", "")

        start_time_str = activity.get("startTimeLocal") or activity.get("startTimeGMT")
        try:
            ts = datetime.fromisoformat(str(start_time_str).replace("Z", "+00:00"))
        except (ValueError, TypeError):
            ts = datetime.now(timezone.utc)

        base_meta = {
            "activity_type": type_key,
            "activity_name": str(activity_name),
            "activity_id": str(activity_id),
        }

        metric_mappings: list[tuple[str, str, str]] = [
            ("duration", "workout_duration", "seconds"),
            ("distance", "workout_distance", "meters"),
            ("calories", "workout_calories", "kcal"),
            ("averageHR", "workout_avg_hr", "bpm"),
            ("maxHR", "workout_max_hr", "bpm"),
        ]

        for garmin_key, metric_type, unit in metric_mappings:
            val = activity.get(garmin_key)
            if val is not None:
                events.append(HealthEvent(
                    source="garmin_connect",
                    device_id=device_id,
                    metric_type=metric_type,
                    value=_safe_float(val),
                    unit=unit,
                    recorded_at=ts,
                    metadata=base_meta.copy(),
                ))
