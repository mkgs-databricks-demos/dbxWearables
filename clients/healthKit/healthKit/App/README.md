# App — Application Entry Point

Contains the app's launch configuration and root service initialization.

## Files

| File | Description |
|---|---|
| `dbxWearablesApp.swift` | `@main` SwiftUI app struct. Renders `MainTabView` as the root view and manages the first-launch onboarding sheet (tracked via `@AppStorage`). |
| `AppDelegate.swift` | `UIApplicationDelegate` that owns the core services: `HealthKitManager` and `SyncCoordinator`. At launch, it initializes these services and registers HealthKit background delivery for all configured data types. |
| `Info.plist` | App metadata including the HealthKit usage description shown during the authorization prompt. |
