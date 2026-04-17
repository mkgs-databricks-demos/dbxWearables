# DataExplorer — Data Explorer Tab Views

Views for the Data Explorer tab, which provides drill-down visibility into synced record counts by type.

## Files

| File | Description |
|---|---|
| `DataExplorerView.swift` | Main Data Explorer tab view. Lists each record type category (samples, workouts, sleep, activity summaries, deletes) with total counts and last sync timestamps. Tapping a category navigates to a detail view. |
| `CategoryDetailView.swift` | Drill-down view for a single record type category. Shows per-type breakdowns — for example, sample counts by HealthKit type (step count, heart rate, etc.) or workout counts by activity type (running, cycling, etc.). |
