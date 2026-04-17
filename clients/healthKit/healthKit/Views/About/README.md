# About — About Tab Views

Views for the About tab, which provides app information, a visual data flow diagram, and access to settings.

## Files

| File | Description |
|---|---|
| `AboutView.swift` | Main About tab view. Displays app documentation, lists the HealthKit data types being synced, shows current permissions status, provides a button to replay the onboarding flow, and links to settings. |
| `DataFlowDiagramView.swift` | A visual diagram showing the end-to-end data flow: HealthKit on the device, through the app, to the REST API endpoint and beyond. Rendered as a SwiftUI view with styled boxes and arrows. |
