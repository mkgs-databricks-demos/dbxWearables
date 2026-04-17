# healthKit — iOS App for Apple HealthKit Integration

An iOS app built with Swift and SwiftUI that reads health and fitness data from Apple HealthKit and sends it to a REST API endpoint as NDJSON payloads. The app is designed as a demo tool for live presentations, featuring Databricks branding and a tab-based UI.

## Architecture

The app follows the **MVVM** (Model-View-ViewModel) pattern:

- **Views** observe `@StateObject` ViewModels and never call services directly
- **ViewModels** are `@MainActor` and access services through `AppDelegate`
- **AppDelegate** owns the core services (`HealthKitManager`, `SyncCoordinator`)
- **Services** handle HealthKit queries, data mapping, serialization, and HTTP communication

## Record Types

The app syncs five categories of HealthKit data, each sent as an NDJSON payload with an `X-Record-Type` HTTP header:

| Record Type | `X-Record-Type` | Description |
|---|---|---|
| **Samples** | `samples` | Quantity and category samples (step count, heart rate, distance, energy burned, VO2 max, SpO2, sleep analysis, stand hours, and more) |
| **Workouts** | `workouts` | Workout sessions with activity type, duration, energy burned, and distance (70+ activity types supported) |
| **Sleep** | `sleep` | Sleep sessions grouped from contiguous sleep stage samples (inBed, asleepCore, asleepDeep, asleepREM, awake) |
| **Activity Summaries** | `activity_summaries` | Daily Apple Activity ring data (active energy, exercise minutes, stand hours with goals) |
| **Deletes** | `deletes` | Lightweight deletion records (UUID + sample type) for soft-delete matching on the backend |

## Sync Pipeline

1. **Query** — Incremental anchored queries fetch only new/updated data since the last sync
2. **Map** — Raw `HKSample` objects are mapped to Codable Swift structs
3. **Serialize** — Records are encoded as NDJSON (one JSON object per line)
4. **POST** — Batched HTTP POSTs with retry logic (retryable on 429/5xx errors)
5. **Checkpoint** — Anchors are persisted after each successful batch for resume-ability

Sync runs concurrently across all record types via Swift `TaskGroup`. Background delivery is supported through HealthKit observer queries that trigger sync when new data arrives.

## Project Structure

```
healthKit/
├── healthKit/              # Main app source code
│   ├── App/                # Entry point, AppDelegate, Info.plist
│   ├── Configuration/      # API endpoint and HealthKit type configs
│   ├── Models/             # Codable data models
│   ├── Services/           # Business logic, sync, API, mappers
│   ├── Repositories/       # Sync state persistence
│   ├── Theme/              # Databricks brand colors, typography, styles
│   ├── Views/              # SwiftUI views (tabs, onboarding, components)
│   ├── ViewModels/         # Observable view models
│   ├── Utilities/          # Helpers (logging, keychain, date formatting)
│   ├── Resources/          # Asset catalog
│   └── Entitlements/       # HealthKit entitlements
├── healthKitTests/         # Unit tests
├── healthKitUITests/       # UI tests
├── XCODE_SETUP.md          # Step-by-step Xcode project creation guide
└── .gitignore              # Xcode/Swift-specific ignores
```

## Setup

No `.xcodeproj` file is checked in. See [`XCODE_SETUP.md`](XCODE_SETUP.md) for step-by-step instructions to create the Xcode project and configure the build.
