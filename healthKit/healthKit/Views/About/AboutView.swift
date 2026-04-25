import SwiftUI

/// Tab 4: Explains the app's purpose, ZeroBus, data flow, HealthKit types, and settings.
struct AboutView: View {
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @State private var permissionsViewModel: PermissionsViewModel?
    @State private var showOnboarding = false
    #if DEBUG
    @State private var showSPNCredentials = false
    @State private var isGeneratingTestData = false
    @State private var showTestDataAlert = false
    @State private var testDataMessage = ""
    #endif

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
                    #if DEBUG
                    debugInfoSection
                    testDataSection
                    spnCredentialsSection
                    #endif
                    replayOnboardingSection
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .background(DBXColors.dbxLightGray)
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if permissionsViewModel == nil {
                    permissionsViewModel = PermissionsViewModel(healthKitManager: healthKitManager)
                }
            }
            .sheet(isPresented: $showOnboarding) {
                OnboardingView(
                    isPresented: $showOnboarding,
                    healthKitManager: healthKitManager
                )
                .environmentObject(healthKitManager)
            }
            #if DEBUG
            .sheet(isPresented: $showSPNCredentials) {
                SPNCredentialsView()
            }
            .alert("Test Data", isPresented: $showTestDataAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(testDataMessage)
            }
            #endif
        }
    }

    #if DEBUG
    // MARK: - Debug Info (Debug)
    
    private var debugInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Debug Info")
            
            Button {
                printSyncLedgerInfo()
            } label: {
                HStack {
                    Image(systemName: "folder.badge.questionmark")
                    Text("Print Sync Ledger Files")
                    Spacer()
                }
            }
            .buttonStyle(DBXSecondaryButtonStyle())
            
            Text("Prints the Documents directory path and lists all sync_ledger files in the console. Use this to debug what data has been saved.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dbxCard()
    }
    
    private func printSyncLedgerInfo() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let syncLedgerDir = docs.appendingPathComponent("sync_ledger")
        
        print("\n" + String(repeating: "=", count: 60))
        print("📁 SYNC LEDGER DEBUG INFO")
        print(String(repeating: "=", count: 60))
        print("Documents Directory: \(docs.path)")
        print("Sync Ledger Directory: \(syncLedgerDir.path)")
        print(String(repeating: "-", count: 60))
        
        if let files = try? FileManager.default.contentsOfDirectory(
            at: syncLedgerDir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) {
            print("Files in sync_ledger/ (\(files.count) total):")
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
                let size = attrs?[.size] as? Int64 ?? 0
                let modDate = attrs?[.modificationDate] as? Date
                
                let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                let dateStr = modDate.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? "unknown"
                
                print("  📄 \(file.lastPathComponent)")
                print("      Size: \(sizeStr), Modified: \(dateStr)")
            }
        } else {
            print("⚠️ Could not read sync_ledger directory (may not exist yet)")
        }
        
        print(String(repeating: "=", count: 60) + "\n")
    }

    // MARK: - Test Data Generation (Debug)


    private var testDataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Test Data Generator")

            Text("Generate sample HealthKit data for testing the sync pipeline. All generated data will appear in the Health app and can be synced to your endpoint.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Button {
                    generateTestData()
                } label: {
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                        Text("Generate 30 Days of Data")
                        Spacer()
                        if isGeneratingTestData {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        }
                    }
                }
                .buttonStyle(DBXSecondaryButtonStyle())
                .disabled(isGeneratingTestData)

                Button {
                    generateTestWorkout()
                } label: {
                    HStack {
                        Image(systemName: "figure.run")
                        Text("Generate Test Workout")
                        Spacer()
                        if isGeneratingTestData {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        }
                    }
                }
                .buttonStyle(DBXSecondaryButtonStyle())
                .disabled(isGeneratingTestData)
            }

            Text("Generates: Steps, heart rate, sleep, active energy, exercise time, stand hours, distance, resting HR, and more.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dbxCard()
    }

    private func generateTestData() {
        isGeneratingTestData = true
        Task {
            do {
                let generator = HealthKitTestDataGenerator(healthStore: healthKitManager.healthStore)
                try await generator.generateSampleData()
                
                await MainActor.run {
                    testDataMessage = "✅ Successfully generated 30 days of test data including steps, heart rate, sleep, and activity ring data. Tap 'Sync Now' on the Dashboard to upload it!"
                    showTestDataAlert = true
                    isGeneratingTestData = false
                }
            } catch {
                await MainActor.run {
                    testDataMessage = "❌ Failed to generate test data: \(error.localizedDescription)\n\nMake sure HealthKit write permissions are granted."
                    showTestDataAlert = true
                    isGeneratingTestData = false
                }
            }
        }
    }
    
    private func generateTestWorkout() {
        isGeneratingTestData = true
        Task {
            do {
                let generator = HealthKitTestDataGenerator(healthStore: healthKitManager.healthStore)
                try await generator.generateSampleWorkout(type: .running, date: Date(), duration: 1800)
                
                await MainActor.run {
                    testDataMessage = "✅ Generated a 30-minute running workout with 250 kcal and 5km distance. Check the Health app or sync now!"
                    showTestDataAlert = true
                    isGeneratingTestData = false
                }
            } catch {
                await MainActor.run {
                    testDataMessage = "❌ Failed to generate workout: \(error.localizedDescription)\n\nMake sure HealthKit write permissions are granted."
                    showTestDataAlert = true
                    isGeneratingTestData = false
                }
            }
        }
    }

    // MARK: - SPN Credentials (Debug)


    private var spnCredentialsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Service Principal Credentials")

            HStack {
                Image(systemName: spnConfigured ? "checkmark.shield.fill" : "exclamationmark.shield")
                    .foregroundStyle(spnConfigured ? DBXColors.dbxGreen : DBXColors.dbxYellow)
                Text(spnConfigured ? "Credentials configured" : "Credentials not configured")
                    .font(.subheadline)
            }

            Button("Configure") {
                showSPNCredentials = true
            }
            .buttonStyle(DBXSecondaryButtonStyle())

            Text("Debug builds only. Paste a Databricks service-principal client ID + secret to enable OAuth bearer-token requests.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dbxCard()
    }

    private var spnConfigured: Bool {
        KeychainHelper.exists(for: KeychainHelper.Key.databricksClientID)
            && KeychainHelper.exists(for: KeychainHelper.Key.databricksClientSecret)
    }
    #endif

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

            let isAuthorized = permissionsViewModel?.isAuthorized ?? false

            HStack {
                Image(systemName: isAuthorized ? "checkmark.shield.fill" : "exclamationmark.shield")
                    .foregroundStyle(isAuthorized ? DBXColors.dbxGreen : DBXColors.dbxYellow)
                Text(isAuthorized ? "Authorization requested" : "Not yet requested")
                    .font(.subheadline)
            }

            HStack(spacing: 8) {
                if !isAuthorized {
                    Button("Request Access") {
                        Task { await permissionsViewModel?.requestAuthorization() }
                    }
                    .buttonStyle(DBXSecondaryButtonStyle())
                }
                
                Button(action: openAppSettings) {
                    Label("Open Settings", systemImage: "gear")
                }
                .buttonStyle(DBXSecondaryButtonStyle())
            }

            Text(permissionsFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dbxCard()
    }
    
    private func openAppSettings() {
        // Open iOS Settings app (always works, no sandbox errors)
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }

    private var permissionsFooter: String {
        let baseText = "To verify permissions:\n1. Open Health app\n2. Tap Profile (top right)\n3. Scroll to Apps\n4. Tap dbxWearables\n\nDue to privacy, this app cannot detect if access was granted."
        
        #if DEBUG
        return baseText + "\n\nDebug builds request write permissions for test data generation."
        #else
        return baseText
        #endif
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
