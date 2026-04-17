# ViewModels — MVVM View Models

`ObservableObject` classes that manage UI state and bridge SwiftUI views to the service layer. All view models are `@MainActor` and access services through `AppDelegate` via `UIApplication.shared.delegate`.

## Files

| File | Description |
|---|---|
| `DashboardViewModel.swift` | Drives the Dashboard tab. Published properties: `lastSyncDate`, `lastSyncRecordCount`, `isSyncing`, `categoryCounts` (per record type), and `recentEvents` (last sync activity). Methods to request HealthKit authorization, trigger a manual sync, and load stats from `SyncLedger`. |
| `DataExplorerViewModel.swift` | Drives the Data Explorer tab. Loads `SyncStats` and exposes `categorySummaries` (display name, icon, total count, last sync timestamp) and per-type breakdown data. Formats raw HealthKit type identifiers into readable labels. |
| `PayloadInspectorViewModel.swift` | Drives the Payloads tab. Loads the last NDJSON payload per record type from `SyncLedger`. Parses individual lines and provides truncated previews and pretty-printed JSON for inspection. |
| `PermissionsViewModel.swift` | Manages the HealthKit authorization flow. Published properties: `isAuthorized` and `errorMessage`. Used by both the onboarding flow and the standalone permissions view. |
