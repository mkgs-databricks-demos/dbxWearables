# Xcode Project Setup Guide

This guide walks through creating an Xcode project for the dbxWearables iOS app. All Swift source files, tests, resources, and configuration plists already exist — the only missing piece is the `.xcodeproj` file itself.

## Prerequisites

- **Xcode 15+** (required for Swift 5.9 and modern SwiftUI/HealthKit APIs)
- **macOS Sonoma 14+** (required for Xcode 15)
- **Apple Developer account** — free account works for Simulator builds; a paid membership ($99/year) is required for device deployment with HealthKit entitlements
- **Physical iOS device** — recommended for full HealthKit testing (see [Simulator Limitations](#simulator-limitations))

## 1. Create the Xcode Project

1. Open Xcode and choose **File > New > Project**
2. Select **iOS > App** and click Next
3. Fill in the project settings:

   | Setting | Value | Why |
   |---------|-------|-----|
   | Product Name | `dbxWearablesApp` | All test files use `@testable import dbxWearablesApp` — the module name must match exactly |
   | Team | Your Apple Developer account (or "None") | |
   | Organization Identifier | `com.dbxwearables` | Matches `Logger` subsystem and `KeychainHelper` service strings in the source |
   | Bundle Identifier | `com.dbxwearables.dbxWearablesApp` | Auto-filled from the above two fields |
   | Interface | **SwiftUI** | |
   | Language | **Swift** | |
   | Storage | **None** | The app does not use Core Data or SwiftData |
   | Include Tests | **Unchecked** | We add test targets manually to match the existing structure |

4. Click Next and **save into the `healthKit/` directory**. The resulting `.xcodeproj` should sit at:
   ```
   healthKit/
   ├── dbxWearablesApp.xcodeproj   ← new
   ├── healthKit/                   ← existing source
   ├── healthKitTests/              ← existing tests
   └── healthKitUITests/            ← existing UI tests
   ```

> **Note:** The on-disk folder is named `healthKit/` but the Xcode product/module must be `dbxWearablesApp`. These are independent — do not rename the folder.

## 2. Delete Auto-Generated Files

Xcode creates boilerplate files that conflict with the existing source. In the Project Navigator, delete all auto-generated files:

- The generated App struct file (e.g. `dbxWearablesAppApp.swift` or `ContentView.swift`)
- The generated `Assets.xcassets` (the project already has one at `healthKit/Resources/Assets.xcassets`)
- Any generated `Preview Content` folder

Choose **"Move to Trash"** when prompted. Keep only the `.xcodeproj` itself.

## 3. Add Existing Source Files

1. In the Project Navigator, right-click the `dbxWearablesApp` project and select **Add Files to "dbxWearablesApp"**
2. Navigate into `healthKit/healthKit/` and select **all subdirectories**:

   | Directory | Files | Contents |
   |-----------|-------|----------|
   | `App/` | 2 | `dbxWearablesApp.swift` (entry point), `AppDelegate.swift` |
   | `Configuration/` | 2 | `APIConfiguration.swift`, `HealthKitConfiguration.swift` |
   | `Entitlements/` | 1 | `dbxWearablesApp.entitlements` |
   | `Models/` | 8 | Codable structs (HealthSample, WorkoutRecord, etc.) |
   | `Repositories/` | 1 | `SyncStateRepository.swift` |
   | `Resources/` | — | `Assets.xcassets` (AccentColor = #FF3621) |
   | `Services/` | 10 | HealthKitManager, APIService, SyncCoordinator, mappers, etc. |
   | `Theme/` | 2 | `DBXTheme.swift`, `DBXButtonStyles.swift` |
   | `Utilities/` | 5 | Date formatters, HK extensions, Keychain, Logger |
   | `ViewModels/` | 4 | Dashboard, DataExplorer, PayloadInspector, Permissions |
   | `Views/` | 13 | SwiftUI views across 6 subdirectories |

3. In the add dialog:
   - Select **"Create groups"** (not "Create folder references")
   - Ensure the **`dbxWearablesApp` target checkbox** is checked
   - Click **Add**

**Total:** 47 Swift source files + 1 entitlements plist + 1 Info.plist + 1 asset catalog.

## 4. Add Test Targets

### Unit Tests

1. **File > New > Target > iOS > Unit Testing Bundle**
2. Product Name: `healthKitTests`
3. Host Application: `dbxWearablesApp`
4. Click Finish
5. Delete the auto-generated test file
6. Add existing files from `healthKit/healthKitTests/`:
   - `Mocks/MockAPIService.swift`
   - `Models/DeletionRecordTests.swift`
   - `Services/APIServiceTests.swift`
   - `Services/ActivitySummaryMapperTests.swift`
   - `Services/HealthSampleMapperTests.swift`
   - `Services/NDJSONSerializerTests.swift`
   - `Services/SleepMapperTests.swift`
   - `Services/WorkoutMapperTests.swift`
7. Ensure the **`healthKitTests` target** is checked when adding

### UI Tests

1. **File > New > Target > iOS > UI Testing Bundle**
2. Product Name: `healthKitUITests`
3. Target Application: `dbxWearablesApp`
4. Click Finish
5. Delete the auto-generated test file
6. Add existing file from `healthKit/healthKitUITests/`:
   - `PermissionsFlowUITests.swift`

## 5. Configure Build Settings

Select the **dbxWearablesApp** target, then go to **Build Settings**:

| Setting | Value | Location |
|---------|-------|----------|
| iOS Deployment Target | **17.0** | General > Minimum Deployments |
| Info.plist File | `healthKit/App/Info.plist` | Build Settings > Packaging |
| Code Signing Entitlements | `healthKit/Entitlements/dbxWearablesApp.entitlements` | Build Settings > Signing |
| Product Module Name | `dbxWearablesApp` | Build Settings > Packaging (verify this matches) |

The existing `Info.plist` already contains:
- `NSHealthShareUsageDescription` — HealthKit read permission prompt
- `NSHealthUpdateUsageDescription` — HealthKit write permission prompt (app does not write)
- `UIBackgroundModes` — `["processing"]`

## 6. Configure Capabilities

Select the **dbxWearablesApp** target > **Signing & Capabilities**:

### HealthKit
1. Click **+ Capability** and add **HealthKit**
2. Check **Background Delivery**
3. Xcode may try to create a new entitlements file — point it to the existing one at `healthKit/Entitlements/dbxWearablesApp.entitlements`

The entitlements file contains:
```xml
com.apple.developer.healthkit = true
com.apple.developer.healthkit.access = [] (empty)
com.apple.developer.healthkit.background-delivery = true
```

### Background Modes
1. Click **+ Capability** and add **Background Modes**
2. Check **Background processing**

This matches the `UIBackgroundModes` entry in `Info.plist` and is required by `AppDelegate.swift` which calls `healthKitManager.registerBackgroundDelivery()` at launch.

## 7. Set the Environment Variable

The app requires the `DBX_API_BASE_URL` environment variable. Without it, `APIConfiguration.swift` will call `fatalError` on launch.

1. **Product > Scheme > Edit Scheme** (or ⌘<)
2. Select **Run** in the left sidebar
3. Go to the **Arguments** tab
4. Under **Environment Variables**, click **+** and add:

   | Name | Value |
   |------|-------|
   | `DBX_API_BASE_URL` | Your Databricks app URL, e.g. `https://<workspace>.databricks.com/apps/<app-name>` |

> **Tests:** `APIServiceTests.swift` sets this variable programmatically via `setenv()`, so unit tests run without manual configuration.

## 8. Code Signing

| Target | Requirement |
|--------|-------------|
| **Simulator** | Any Apple ID with automatic signing works. HealthKit entitlements are accepted in Simulator builds. |
| **Physical device** | Requires a **paid Apple Developer Program membership**. The HealthKit entitlement must be included in your provisioning profile. Automatic signing handles this if your account has the capability. |

## 9. Build and Run

### Build
- **⌘B** to build. Expect zero errors if all files are added correctly and the module name is `dbxWearablesApp`.

### Run on Simulator
- Select an iPhone simulator from the device toolbar and press **⌘R**
- The app UI will work fully — onboarding, navigation, theming, all tabs
- The sync pipeline will execute but produce empty results (no real HealthKit data in Simulator)

### Run on a Physical Device
- Connect your device via USB or Wi-Fi
- Select it from the device toolbar and press **⌘R**
- Full HealthKit functionality: real health data, authorization dialogs with actual data access, background delivery
- For workout/heart rate/activity ring data, the device should have a paired Apple Watch or data from other HealthKit-contributing apps

### Run Tests
- **⌘U** runs all tests
- Unit tests (`healthKitTests`) use mocked networking (`MockURLProtocol`) — no device or HealthKit access needed
- UI tests (`healthKitUITests`) currently contain a stub class

## Simulator Limitations

`HKHealthStore.isHealthDataAvailable()` returns `true` on recent simulators (Xcode 15+ / iOS 17), but the Simulator has significant limitations:

- **No Health app** — there is no way to populate HealthKit data in the Simulator
- Authorization dialogs appear but grant/deny choices produce no actual data
- Background delivery does not trigger
- The app is usable for **UI development and layout testing** but not for verifying the sync pipeline end-to-end

For meaningful HealthKit testing, use a physical device.

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `No such module 'dbxWearablesApp'` in test files | Product Module Name mismatch | Build Settings > Packaging > Product Module Name must be exactly `dbxWearablesApp` |
| `fatalError: DBX_API_BASE_URL environment variable is not set` | Missing env var | Set `DBX_API_BASE_URL` in the scheme's Run configuration (see [Step 7](#7-set-the-environment-variable)) |
| Code signing / entitlement errors on device | HealthKit requires paid account | Ensure HealthKit capability is added via Signing & Capabilities and you have a paid Apple Developer account |
| Duplicate `@main` entry point | Xcode's auto-generated App file still present | Delete all auto-generated Swift files (see [Step 2](#2-delete-auto-generated-files)) |
| No app icon | None configured yet | Expected — no `AppIcon` asset set exists. Add one to `Resources/Assets.xcassets` when ready |
| Asset catalog warning | Missing root `Contents.json` | If Xcode complains, add `{"info":{"author":"xcode","version":1}}` as `Assets.xcassets/Contents.json` |

## Alternative: Project Generation Tools

For teams that prefer not to maintain `.xcodeproj` files manually, tools like [XcodeGen](https://github.com/yonaskolb/XcodeGen) or [Tuist](https://tuist.io) can generate the project from a YAML or Swift specification. However, given that this app has **zero external dependencies** and a straightforward structure, manual Xcode project creation is simpler and avoids adding tooling dependencies.
