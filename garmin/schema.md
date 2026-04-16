# Garmin Health Event Schema

## Bronze Layer: `wearables_zerobus` (VARIANT)

All wearable data — including Garmin, HealthKit, and future sources — lands in the shared `wearables_zerobus` table managed by the `zeroBus/dbxW_zerobus_infra` DABs bundle.

The source of truth for the bronze DDL is [`zeroBus/dbxW_zerobus_infra/src/uc_setup/target-table-ddl.sql`](../zeroBus/dbxW_zerobus_infra/src/uc_setup/target-table-ddl.sql).

### Bronze Table Columns

| Column | Type | Description |
|--------|------|-------------|
| `record_id` | `STRING NOT NULL` | Server-generated GUID for each ingested record (PK) |
| `ingested_at` | `TIMESTAMP` | Server-side ingestion timestamp |
| `body` | `VARIANT` | Raw JSON payload — the full Garmin API response wrapped with source metadata |
| `headers` | `VARIANT` | HTTP request headers as JSON (includes `X-Platform`, `X-Record-Type`, `X-Device-Id`) |
| `record_type` | `STRING` | Category of data (extracted from `X-Record-Type` header) |

### Garmin `record_type` Values

| record_type | Garmin API Method | Description |
|-------------|-------------------|-------------|
| `daily_stats` | `get_stats()` | Daily summary (steps, calories, resting HR, VO2 max, etc.) |
| `heart_rates` | `get_heart_rates()` | Intraday heart rate time series |
| `sleep` | `get_sleep_data()` | Sleep stages, duration, scores |
| `stress` | `get_stress_data()` | Intraday stress time series |
| `hrv` | `get_hrv_data()` | Heart rate variability summary |
| `spo2` | `get_spo2_data()` | Blood oxygen saturation |
| `body_battery` | `get_body_battery()` | Body battery time series |
| `steps` | `get_steps_data()` | Intraday step counts |
| `respiration` | `get_respiration_data()` | Respiration rate |
| `activities` | `get_activities_fordate()` | Workout/activity summaries |
| `samples` | Connect IQ on-device | Real-time sensor readings from watch |

### Bronze `body` Structure (Garmin Connect Pull)

```json
{
  "source": "garmin_connect",
  "device_id": "garmin_forerunner_265",
  "date": "2026-04-15",
  "data": { ... raw Garmin API response ... }
}
```

### Bronze `headers` Structure

```json
{
  "Content-Type": "application/json",
  "X-Platform": "garmin_connect",
  "X-Record-Type": "daily_stats",
  "X-Device-Id": "garmin_forerunner_265",
  "X-Upload-Timestamp": "2026-04-16T02:00:00+00:00"
}
```

### Querying Garmin Data in Bronze

```sql
-- All Garmin records
SELECT * FROM wearables_zerobus
WHERE headers:"X-Platform"::STRING = 'garmin_connect';

-- Specific record type
SELECT body:data FROM wearables_zerobus
WHERE headers:"X-Platform"::STRING = 'garmin_connect'
  AND record_type = 'sleep';

-- Extract nested fields from body VARIANT
SELECT
  body:date::STRING AS data_date,
  body:data:restingHeartRate::INT AS resting_hr,
  body:data:totalSteps::INT AS total_steps
FROM wearables_zerobus
WHERE record_type = 'daily_stats';
```

---

## Silver Layer (Planned): Normalized Typed Events

The silver layer will parse the raw VARIANT body from the bronze table into strongly-typed metric records. This normalization logic is implemented in `garmin/pull/normalizer.py` (the `normalize()` function and `HealthEvent` dataclass) and is ready for use in silver views or Spark Declarative Pipelines.

### Normalized Event Fields

| Field | Type | Description |
|-------|------|-------------|
| `source` | `STRING` | Origin identifier. `"garmin_connect_iq"` for watch-pushed data, `"garmin_connect"` for cloud-pulled data. |
| `device_id` | `STRING` | Unique device identifier. |
| `metric_type` | `STRING` | Metric name from the allowed set below. |
| `value` | `DOUBLE` | Numeric measurement value. |
| `unit` | `STRING` | Unit of measurement (e.g., `bpm`, `count`, `minutes`). |
| `recorded_at` | `TIMESTAMP` | When the measurement was taken on the device. |
| `metadata` | `MAP<STRING, STRING>` | Optional key-value pairs for extra context. |

### Metric Types

#### Vitals

| metric_type | unit | Source | Description |
|-------------|------|--------|-------------|
| `heart_rate_resting` | `bpm` | CIQ, Pull | Resting heart rate for the day |
| `heart_rate_intraday` | `bpm` | CIQ, Pull | Point-in-time heart rate reading |
| `stress_level` | `score` | CIQ, Pull | Stress score (0-100) |
| `stress_avg` | `score` | Pull | Daily average stress level |
| `body_battery_current` | `score` | CIQ | Current body battery level (0-100) |
| `body_battery_high` | `score` | Pull | Daily high body battery |
| `body_battery_low` | `score` | Pull | Daily low body battery |
| `spo2` | `pct` | CIQ, Pull | Blood oxygen saturation percentage |
| `spo2_avg` | `pct` | Pull | Average SpO2 during sleep |
| `respiration_rate` | `brpm` | CIQ, Pull | Breaths per minute |
| `respiration_avg` | `brpm` | Pull | Daily average respiration rate |

#### Activity

| metric_type | unit | Source | Description |
|-------------|------|--------|-------------|
| `steps_daily` | `count` | CIQ, Pull | Total steps for the day |
| `steps_intraday` | `count` | CIQ | Steps in the current interval |
| `calories_active` | `kcal` | Pull | Active calories burned |
| `calories_total` | `kcal` | Pull | Total calories (active + BMR) |
| `floors_climbed` | `count` | Pull | Floors climbed |
| `intensity_minutes` | `minutes` | Pull | Moderate + vigorous intensity minutes |
| `vo2_max` | `ml/kg/min` | Pull | VO2 max estimate |

#### Sleep

| metric_type | unit | Source | Description |
|-------------|------|--------|-------------|
| `sleep_duration` | `minutes` | Pull | Total sleep time |
| `sleep_deep` | `minutes` | Pull | Deep sleep duration |
| `sleep_light` | `minutes` | Pull | Light sleep duration |
| `sleep_rem` | `minutes` | Pull | REM sleep duration |
| `sleep_awake` | `minutes` | Pull | Awake time during sleep |
| `sleep_score` | `score` | Pull | Overall sleep score (0-100) |

#### Heart Rate Variability

| metric_type | unit | Source | Description |
|-------------|------|--------|-------------|
| `hrv_weekly_avg` | `ms` | Pull | 7-day rolling HRV average |
| `hrv_last_night` | `ms` | Pull | Last night 5-min high HRV |
| `hrv_status` | `score` | Pull | HRV status (balanced/low/unbalanced) encoded as numeric |

#### Workouts / Activities

| metric_type | unit | Source | Description |
|-------------|------|--------|-------------|
| `workout_duration` | `seconds` | Pull | Workout elapsed time |
| `workout_distance` | `meters` | Pull | Distance covered |
| `workout_calories` | `kcal` | Pull | Calories burned during workout |
| `workout_avg_hr` | `bpm` | Pull | Average heart rate during workout |
| `workout_max_hr` | `bpm` | Pull | Max heart rate during workout |

Workout events include `metadata` with:
- `activity_type`: Garmin activity type name (e.g., `running`, `cycling`, `swimming`)
- `activity_name`: User-given workout name
- `activity_id`: Garmin activity ID

### Garmin Raw Field Mappings (for Silver Parsing)

#### From `get_stats()` (daily summary) — `record_type = 'daily_stats'`

| Garmin Field | metric_type | Unit |
|--------------|-------------|------|
| `restingHeartRate` | `heart_rate_resting` | `bpm` |
| `totalSteps` | `steps_daily` | `count` |
| `activeKilocalories` | `calories_active` | `kcal` |
| `totalKilocalories` | `calories_total` | `kcal` |
| `vO2MaxValue` | `vo2_max` | `ml/kg/min` |
| `floorsAscended` | `floors_climbed` | `count` |
| `moderateIntensityMinutes` + `vigorousIntensityMinutes` | `intensity_minutes` | `minutes` |
| `averageStressLevel` | `stress_avg` | `score` |

#### From `get_sleep_data()` -> `dailySleepDTO` — `record_type = 'sleep'`

| Garmin Field | metric_type | Divisor | Unit |
|--------------|-------------|---------|------|
| `sleepTimeSeconds` | `sleep_duration` | 60 | `minutes` |
| `deepSleepSeconds` | `sleep_deep` | 60 | `minutes` |
| `lightSleepSeconds` | `sleep_light` | 60 | `minutes` |
| `remSleepSeconds` | `sleep_rem` | 60 | `minutes` |
| `awakeSleepSeconds` | `sleep_awake` | 60 | `minutes` |
| `sleepScores.overall.value` | `sleep_score` | 1 | `score` |
| `averageSpO2Value` | `spo2_avg` | 1 | `pct` |
| `averageRespirationValue` | `respiration_avg` | 1 | `brpm` |

#### From `get_hrv_data()` -> `hrvSummary` — `record_type = 'hrv'`

| Garmin Field | metric_type | Unit |
|--------------|-------------|------|
| `weeklyAvg` | `hrv_weekly_avg` | `ms` |
| `lastNight5MinHigh` | `hrv_last_night` | `ms` |
| `status` | `hrv_status` | `score` |

#### From Connect IQ `SensorHistory` — `record_type = 'samples'`

| API Method | metric_type | Unit |
|------------|-------------|------|
| `getHeartRateHistory()` | `heart_rate_intraday` | `bpm` |
| `getStressHistory()` | `stress_level` | `score` |
| `getBodyBatteryHistory()` | `body_battery_current` | `score` |
| `getOxygenSaturationHistory()` | `spo2` | `pct` |
| `ActivityMonitor.getInfo().steps` | `steps_intraday` | `count` |
