import SwiftUI

/// Settings screen for API endpoint configuration and sync preferences.
struct SettingsView: View {

    var body: some View {
        List {
            Section("API Endpoint") {
                Text("Configured via DBX_API_BASE_URL environment variable.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Data Types") {
                Text("All configured HealthKit types are synced. Edit HealthKitConfiguration.swift to adjust.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
