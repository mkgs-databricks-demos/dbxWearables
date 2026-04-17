# Onboarding — First-Launch Onboarding Flow

Contains the onboarding experience shown to users on first launch.

## Files

| File | Description |
|---|---|
| `OnboardingView.swift` | A 4-page swipeable sheet presented on first launch (tracked via `@AppStorage`). Pages: (1) Welcome with Databricks branding, (2) Explanation of ZeroBus and the data flow, (3) List of HealthKit data types the app will read, (4) Get Started page with the HealthKit authorization prompt. The onboarding can be replayed from the About tab. |
