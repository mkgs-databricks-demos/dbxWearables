# Repositories — Sync State Persistence

Manages persistent state for the incremental sync pipeline.

## Files

| File | Description |
|---|---|
| `SyncStateRepository.swift` | Persists HealthKit query anchors per sample type using `UserDefaults`. Anchors enable incremental fetching — each sync picks up where the last one left off. Also tracks the last sync date for activity summaries, which use date-range queries instead of anchors. |
