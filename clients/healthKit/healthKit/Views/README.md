# Views — SwiftUI User Interface

All SwiftUI views for the app, organized by tab and feature. The app uses tab-based navigation with four tabs plus a first-launch onboarding sheet.

## Root Views

| File | Description |
|---|---|
| `MainTabView.swift` | Root `TabView` with four tabs: Dashboard, Data Explorer, Payloads, and About. Uses Databricks red (#FF3621) as the tab bar tint color. |
| `PermissionsView.swift` | Standalone HealthKit authorization view. Shows a detailed explanation of the data types requested and a "Grant Access" button. Used in both onboarding and the About tab. |

## Subdirectories

| Directory | Tab | Description |
|---|---|---|
| [`Dashboard/`](Dashboard/) | Dashboard | Hero header, sync button, per-category record counts, recent activity feed |
| [`DataExplorer/`](DataExplorer/) | Data | Per-category list with drill-down to type-level breakdowns |
| [`Payloads/`](Payloads/) | Payloads | Terminal-styled NDJSON viewer for inspecting sent payloads |
| [`About/`](About/) | About | App info, data flow diagram, settings, replay onboarding |
| [`Onboarding/`](Onboarding/) | (Sheet) | First-launch 4-page swipeable onboarding flow |
| [`Components/`](Components/) | (Shared) | Reusable UI components used across tabs |
