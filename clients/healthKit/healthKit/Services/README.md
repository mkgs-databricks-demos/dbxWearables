# Services — Business Logic and Data Processing

Contains the core business logic for querying HealthKit, mapping raw samples to models, serializing data, and communicating with the REST API.

## Core Services

| File | Description |
|---|---|
| `HealthKitManager.swift` | Central manager for `HKHealthStore`. Handles HealthKit authorization, registers observer queries for background delivery, and triggers sync when new data arrives. Publishes authorization state for the UI. |
| `HealthKitQueryService.swift` | Executes HealthKit queries. Uses anchored object queries for incremental fetching (samples, workouts, sleep, deletes) and date-range queries for activity summaries. Returns raw `HKSample` arrays along with updated anchors. |
| `SyncCoordinator.swift` | Orchestrates the complete sync cycle. Spawns concurrent tasks via `TaskGroup` — one per record type — each running a batched query-map-serialize-post loop. Handles retryable errors (429, 5xx) with 2-second backoff. Persists anchors after each successful batch for resume-ability. |
| `APIService.swift` | HTTP client for the REST API. Sends NDJSON payloads via POST with headers including `X-Record-Type`, `X-Device-Id`, `X-Platform`, `X-App-Version`, and `X-Upload-Timestamp`. Distinguishes retryable (429, 5xx) from non-retryable (4xx) errors. Supports optional Bearer token auth via Keychain. |
| `SyncLedger.swift` | A Swift `actor` that persists sync telemetry as JSON files in the app's Documents directory (`sync_ledger/`). Stores the last NDJSON payload per record type, cumulative stats, and recent sync events (last 20). Used by the Payload Inspector and Dashboard views. |
| `NDJSONSerializer.swift` | Serializes `Codable` arrays to NDJSON format (one JSON object per line). Uses ISO 8601 date encoding and sorted keys for consistency. |

## Mappers

Each mapper converts raw HealthKit objects into the app's Codable models.

| File | Description |
|---|---|
| `HealthSampleMapper.swift` | Maps `HKQuantitySample` and `HKCategorySample` to `HealthSample`. Extracts canonical units, source device info, and flattens metadata values to strings. |
| `WorkoutMapper.swift` | Maps `HKWorkout` to `WorkoutRecord`. Includes a comprehensive switch statement covering 70+ workout activity types with snake_case names. |
| `SleepMapper.swift` | Groups contiguous sleep stage samples into `SleepRecord` sessions. Uses a 30-minute gap threshold to detect session boundaries. Preserves individual stage UUIDs for deletion matching. |
| `ActivitySummaryMapper.swift` | Maps `HKActivitySummary` to `ActivitySummary`. Formats the date as YYYY-MM-DD and extracts ring values (active energy, exercise time, stand hours) with their goals. |
