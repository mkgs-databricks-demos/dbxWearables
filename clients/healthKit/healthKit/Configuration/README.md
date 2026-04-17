# Configuration — API and HealthKit Settings

Static configuration for the REST API endpoint and the HealthKit data types the app reads.

## Files

| File | Description |
|---|---|
| `APIConfiguration.swift` | Defines the REST API base URL, ingest path (`/api/v1/healthkit/ingest`), timeout interval (30s), and maximum retry attempts (3). |
| `HealthKitConfiguration.swift` | Lists all HealthKit types the app requests permission to read: 11 quantity types (step count, heart rate, distance, energy burned, VO2 max, SpO2, etc.), 2 category types (sleep analysis, stand hour), workouts, and activity summaries. Also defines batch sizes — 500 for background sync (~30s window) and 2000 for foreground sync. |
