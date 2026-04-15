import SwiftUI

/// Tab 4: Explains the app's purpose, ZeroBus, data flow, HealthKit types, and settings.
struct AboutView: View {
    @StateObject private var permissionsViewModel = PermissionsViewModel()
    @State private var showOnboarding = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    DBXHeaderView(showVersion: true)

                    purposeSection
                    dataFlowSection
                    zeroBusSection
                    healthKitTypesSection
                    howDataIsSentSection
                    permissionsSection
                    settingsSection
                    replayOnboardingSection
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .background(DBXColors.dbxLightGray)
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showOnboarding) {
                OnboardingView(isPresented: $showOnboarding)
            }
        }
    }

    // MARK: - Purpose

    private var purposeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("What This App Does")

            Text("dbxWearables reads health and fitness data from Apple HealthKit on your iPhone and Apple Watch, serializes it as NDJSON (Newline-Delimited JSON), and POSTs it to a Databricks AppKit REST endpoint. The endpoint streams each record through ZeroBus into a Unity Catalog bronze table for analytics.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dbxCard()
    }

    // MARK: - Data Flow

    private var dataFlowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Data Flow")

            DataFlowDiagramView()
                .padding(12)
                .background(DBXColors.dbxNavy)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dbxCard()
    }

    // MARK: - ZeroBus

    private var zeroBusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("What is ZeroBus?")

            Text("ZeroBus is Databricks' built-in event streaming SDK. It decouples REST API intake from table writes, providing streaming semantics without managing Kafka or similar infrastructure. When the AppKit endpoint receives an NDJSON POST, ZeroBus streams each record directly into a Unity Catalog table with exactly-once guarantees.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dbxCard()
    }

    // MARK: - HealthKit Types

    private var healthKitTypesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("HealthKit Data Sent")

            Group {
                typeGroup("Quantity Samples", items: [
                    ("figure.walk", "Steps & Distance"),
                    ("heart.fill", "Heart Rate, Resting HR, HRV"),
                    ("flame.fill", "Active & Basal Energy"),
                    ("lungs.fill", "Blood Oxygen (SpO2)"),
                    ("timer", "Exercise Time, Stand Time"),
                    ("chart.line.uptrend.xyaxis", "VO2 Max"),
                ])

                typeGroup("Category Samples", items: [
                    ("bed.double.fill", "Sleep Analysis (stages)"),
                    ("figure.stand", "Stand Hours"),
                ])

                typeGroup("Other", items: [
                    ("figure.run", "Workouts (70+ activity types)"),
                    ("circle.circle", "Activity Ring Summaries"),
                    ("trash", "Deletion Records"),
                ])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dbxCard()
    }

    private func typeGroup(_ title: String, items: [(icon: String, label: String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(DBXColors.dbxRed)
                .textCase(.uppercase)

            ForEach(items, id: \.label) { item in
                Label(item.label, systemImage: item.icon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - How Data Is Sent

    private var howDataIsSentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("How Data Is Sent")

            VStack(alignment: .leading, spacing: 12) {
                infoRow("Format", "NDJSON — one JSON record per line, enabling streaming ingestion and partial failure recovery.")
                infoRow("Batching", "Incremental sync using HealthKit anchored queries. 2,000 records per batch (foreground) or 500 (background).")
                infoRow("Headers", "Each POST includes X-Record-Type, X-Device-Id, X-Platform, X-App-Version, and X-Upload-Timestamp for routing and auditing.")
                infoRow("Deletions", "When HealthKit reports deleted samples, deletion records are sent separately with X-Record-Type: deletes.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dbxCard()
    }

    private func infoRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("HealthKit Permissions")

            HStack {
                Image(systemName: permissionsViewModel.isAuthorized ? "checkmark.shield.fill" : "exclamationmark.shield")
                    .foregroundStyle(permissionsViewModel.isAuthorized ? DBXColors.dbxGreen : DBXColors.dbxYellow)
                Text(permissionsViewModel.isAuthorized ? "Access granted" : "Access not yet granted")
                    .font(.subheadline)
            }

            if !permissionsViewModel.isAuthorized {
                Button("Request Access") {
                    Task { await permissionsViewModel.requestAuthorization() }
                }
                .buttonStyle(DBXSecondaryButtonStyle())
            }

            Text("This app only reads health data. It never writes to HealthKit.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dbxCard()
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Settings")

            settingRow("API Endpoint", value: ProcessInfo.processInfo.environment["DBX_API_BASE_URL"] ?? "(not configured)")
            settingRow("Device ID", value: DeviceIdentifier.current)
            settingRow("App Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dbxCard()
    }

    private func settingRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fontDesign(.monospaced)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Replay Onboarding

    private var replayOnboardingSection: some View {
        Button("Replay Onboarding") {
            showOnboarding = true
        }
        .buttonStyle(DBXSecondaryButtonStyle())
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(DBXTypography.sectionHeader)
    }
}
