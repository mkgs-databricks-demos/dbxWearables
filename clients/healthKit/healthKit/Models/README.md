# Models — Codable Data Models

Swift structs that represent the data the app reads from HealthKit and the metadata it tracks during sync. All models conform to `Codable` for JSON/NDJSON serialization.

## Health Record Models

| File | Description |
|---|---|
| `HealthSample.swift` | A single health measurement (quantity or category sample). Fields: UUID, type identifier, value, unit, start/end dates, source device info, and optional metadata. |
| `WorkoutRecord.swift` | A workout session. Fields: UUID, activity type (readable name + raw enum value), duration in seconds, energy burned, distance, source name, and metadata. |
| `SleepRecord.swift` | A sleep session composed of multiple `SleepStage` entries. Each stage has a UUID, stage name (inBed, asleepCore, asleepDeep, asleepREM, awake), and time bounds. Stages are grouped into sessions by the `SleepMapper`. |
| `ActivitySummary.swift` | A daily Activity Rings summary. Fields: date (YYYY-MM-DD), active energy burned, exercise minutes, stand hours, and corresponding goal values. |
| `DeletionRecord.swift` | A lightweight record for deleted samples. Contains only the UUID and sample type identifier, used for soft-delete matching on the backend. |

## Sync & API Models

| File | Description |
|---|---|
| `SyncRecord.swift` | Audit trail entry for each successful POST. Includes record type, count, HTTP status, timestamp, the NDJSON payload (optional), and request headers sent. |
| `SyncStats.swift` | Cumulative sync statistics. Tracks total records sent per type, last sync timestamp, and breakdowns by sample type, workout activity type, sleep sessions, and activity summary days. |
| `APIResponse.swift` | Response from the REST API. Contains status, optional message, and optional record ID. |
