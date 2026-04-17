# Dashboard — Dashboard Tab Views

Views for the Dashboard tab, the app's primary screen. Shows sync status, record counts by category, and recent sync activity.

## Files

| File | Description |
|---|---|
| `DashboardView.swift` | Main Dashboard tab view. Displays a hero header with the Databricks wordmark, a sync button, a grid of per-category record counts (samples, workouts, sleep, activity summaries, deletes), and a feed of the last 5 sync events. |
| `SyncStatusCard.swift` | A card with the manual "Sync Now" button. Shows a loading indicator during sync and the timestamp of the last successful sync. |
| `CategoryStatCard.swift` | A compact card displaying an icon, label, and count for a single record type category. Used in the stats grid on the Dashboard. |
