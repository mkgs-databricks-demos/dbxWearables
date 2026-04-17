# Utilities — Shared Helper Functions

General-purpose utilities used across the app for logging, security, date formatting, and HealthKit extensions.

## Files

| File | Description |
|---|---|
| `Logger.swift` | Configures three `os.Logger` subsystems for structured logging: HealthKit, API, and Sync. Uses Apple's unified logging framework (`OSLog`) for console and Instruments integration. |
| `KeychainHelper.swift` | Secure storage and retrieval of the API authentication token via the iOS Keychain (service: `com.dbxwearables.api`). |
| `DeviceIdentifier.swift` | Generates and persists a stable per-installation UUID via the Keychain. This is NOT a hardware ID — it survives app updates but not uninstall/reinstall. Sent as the `X-Device-Id` header with every API request. |
| `DateFormatters.swift` | Shared date formatters: an ISO 8601 formatter with timezone and fractional seconds (for API payloads) and a date-only formatter (`yyyy-MM-dd`) for activity summaries. |
| `HKQuantityType+Extensions.swift` | Extension on `HKQuantityType` that maps each type to its canonical unit (steps to count, distance to meters, heart rate to count/min, VO2 max to ml/kg*min, etc.) and provides a `unitString` property for JSON serialization. |
