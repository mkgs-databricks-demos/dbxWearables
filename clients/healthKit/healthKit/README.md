# healthKit/healthKit — Main App Source Code

This directory contains all Swift source code for the dbxWearables iOS app, organized by architectural layer following the MVVM pattern.

## Directory Structure

| Directory | Purpose |
|---|---|
| [`App/`](App/) | Application entry point, AppDelegate, Info.plist |
| [`Configuration/`](Configuration/) | API endpoint and HealthKit type configuration |
| [`Models/`](Models/) | Codable data models for health records and sync state |
| [`Services/`](Services/) | Business logic — HealthKit queries, data mapping, serialization, API communication, sync orchestration |
| [`Repositories/`](Repositories/) | Persistent state management (sync anchors and dates) |
| [`Theme/`](Theme/) | Databricks brand colors, gradients, typography, and button styles |
| [`Views/`](Views/) | SwiftUI views organized by tab and feature |
| [`ViewModels/`](ViewModels/) | Observable view models that bridge services and views |
| [`Utilities/`](Utilities/) | Shared helpers — logging, keychain, date formatting, HealthKit extensions |
| [`Resources/`](Resources/) | Xcode asset catalog (accent color) |
| [`Entitlements/`](Entitlements/) | App capability entitlements (HealthKit access) |

## Ownership & Data Flow

`AppDelegate` is the root owner of the service graph:

```
AppDelegate
├── HealthKitManager      (HKHealthStore, authorization, observer queries)
└── SyncCoordinator       (orchestrates the full sync cycle)
    ├── HealthKitQueryService   (anchored queries)
    ├── APIService              (HTTP POST to REST endpoint)
    ├── SyncStateRepository     (anchor persistence)
    └── SyncLedger              (payload & stats persistence)
```

ViewModels access services through `AppDelegate` via `UIApplication.shared.delegate`.
