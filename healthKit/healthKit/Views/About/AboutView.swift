import SwiftUI

/// Tab 4: Explains the app's purpose, ZeroBus, data flow, HealthKit types, and settings.
struct AboutView: View {
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @EnvironmentObject private var syncCoordinator: SyncCoordinator
    @State private var permissionsViewModel: PermissionsViewModel?
    @State private var showOnboarding = false
    @State private var showCredentialsConfig = false
    #if DEBUG
    @State private var showSPNCredentials = false
    @State private var isGeneratingTestData = false
    @State private var showTestDataAlert = false
    @State private var testDataMessage = ""
    @State private var showAdvancedOptions = false
    
    // Generator configuration
    @State private var daysToGenerate = 30
    @State private var fitnessLevel: GeneratorConfig.FitnessLevel = .moderate
    @State private var includeWeekendVariation = true
    @State private var includeWorkouts = true
    @State private var includeSleepStages = true
    @State private var includeAdvancedMetrics = true
    
    // Integration testing
    @State private var isRunningTests = false
    @State private var testResults: [TestResult] = []
    @State private var showTestResults = false
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
                    credentialsSection
                    settingsSection
                    #if DEBUG
                    debugInfoSection
                    integrationTestSection
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
            .sheet(isPresented: $showCredentialsConfig) {
                CredentialsConfigView()
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
            .sheet(isPresented: $showTestResults) {
                TestResultsView(results: testResults)
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

    // MARK: - Integration Testing (Debug)
    
    private var integrationTestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Integration Testing")
            
            Text("Run end-to-end tests with different synthetic data scenarios to validate your entire pipeline.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 8) {
                Button {
                    runIntegrationTests()
                } label: {
                    HStack {
                        Image(systemName: "testtube.2")
                        Text("Run Test Suite")
                        Spacer()
                        if isRunningTests {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        }
                    }
                }
                .buttonStyle(DBXPrimaryButtonStyle())
                .disabled(isRunningTests)
                
                if !testResults.isEmpty {
                    Button {
                        showTestResults = true
                    } label: {
                        HStack {
                            Image(systemName: "chart.bar.doc.horizontal")
                            Text("View Last Results (\(testResults.filter { $0.success }.count)/\(testResults.count) passed)")
                            Spacer()
                        }
                    }
                    .buttonStyle(DBXSecondaryButtonStyle())
                }
            }
            
            Text("Tests: Sedentary 7d, Minimal, Moderate 30d, Deletion workflow")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dbxCard()
    }

    // MARK: - Test Data Generation (Debug)


    private var testDataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Test Data Generator")

            Text("Generate realistic HealthKit data for testing. All samples are tagged as synthetic and can be safely deleted.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Quick Actions
            VStack(spacing: 8) {
                Button {
                    generateTestData()
                } label: {
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                        Text("Generate \(daysToGenerate) Days")
                        Spacer()
                        if isGeneratingTestData {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        }
                    }
                }
                .buttonStyle(DBXPrimaryButtonStyle())
                .disabled(isGeneratingTestData)

                HStack(spacing: 8) {
                    Button {
                        generateTestWorkout()
                    } label: {
                        HStack {
                            Image(systemName: "figure.run")
                            Text("Single Workout")
                            Spacer()
                        }
                    }
                    .buttonStyle(DBXSecondaryButtonStyle())
                    .disabled(isGeneratingTestData)
                    
                    Button(role: .destructive) {
                        deleteSyntheticData()
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Synthetic")
                            Spacer()
                        }
                    }
                    .buttonStyle(DBXSecondaryButtonStyle())
                    .disabled(isGeneratingTestData)
                }
            }
            
            // Advanced Options Toggle
            Button {
                withAnimation {
                    showAdvancedOptions.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: showAdvancedOptions ? "chevron.down" : "chevron.right")
                        .font(.caption)
                    Text("Advanced Options")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                }
            }
            .foregroundStyle(.primary)
            .padding(.top, 4)
            
            if showAdvancedOptions {
                advancedOptionsView
            }

            Text("Generated: Steps, HR, HRV, SpO2, VO2Max, Sleep, Workouts, Energy, Distance")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dbxCard()
    }
    
    private var advancedOptionsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
            
            // Days Slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Days to Generate")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(daysToGenerate)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                
                Slider(value: Binding(
                    get: { Double(daysToGenerate) },
                    set: { daysToGenerate = Int($0) }
                ), in: 7...90, step: 1)
                .tint(DBXColors.dbxRed)
                
                HStack {
                    Text("7 days")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("90 days")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Fitness Level Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Fitness Level")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Picker("Fitness Level", selection: $fitnessLevel) {
                    Text("Sedentary").tag(GeneratorConfig.FitnessLevel.sedentary)
                    Text("Light").tag(GeneratorConfig.FitnessLevel.light)
                    Text("Moderate").tag(GeneratorConfig.FitnessLevel.moderate)
                    Text("Active").tag(GeneratorConfig.FitnessLevel.active)
                    Text("Very Active").tag(GeneratorConfig.FitnessLevel.veryActive)
                }
                .pickerStyle(.menu)
                
                Text(fitnessLevelDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            // Feature Toggles
            VStack(alignment: .leading, spacing: 12) {
                Text("Features")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Toggle(isOn: $includeWeekendVariation) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weekend Variation")
                            .font(.subheadline)
                        Text("30% less activity on weekends")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(DBXColors.dbxRed)
                
                Toggle(isOn: $includeWorkouts) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Workouts")
                            .font(.subheadline)
                        Text("2-3 workouts per week (running, cycling, etc.)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(DBXColors.dbxRed)
                
                Toggle(isOn: $includeSleepStages) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sleep Stages")
                            .font(.subheadline)
                        Text("Realistic light, deep, REM cycles")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(DBXColors.dbxRed)
                
                Toggle(isOn: $includeAdvancedMetrics) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Advanced Metrics")
                            .font(.subheadline)
                        Text("HRV, SpO2, VO2Max, basal energy")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(DBXColors.dbxRed)
            }
        }
        .padding(.top, 8)
    }
    
    private var fitnessLevelDescription: String {
        switch fitnessLevel {
        case .sedentary:
            return "2k-5k steps/day, 200-400 kcal active, HR 65-80 resting"
        case .light:
            return "5k-8k steps/day, 400-600 kcal active, HR 60-75 resting"
        case .moderate:
            return "8k-12k steps/day, 600-900 kcal active, HR 55-70 resting"
        case .active:
            return "12k-16k steps/day, 900-1200 kcal active, HR 50-65 resting"
        case .veryActive:
            return "16k-22k steps/day, 1200-1800 kcal active, HR 45-60 resting"
        }
    }

    private func generateTestData() {
        isGeneratingTestData = true
        Task {
            do {
                let config = GeneratorConfig(
                    daysToGenerate: daysToGenerate,
                    fitnessLevel: fitnessLevel,
                    includeWeekendVariation: includeWeekendVariation,
                    includeWorkouts: includeWorkouts,
                    includeSleepStages: includeSleepStages,
                    includeAdvancedMetrics: includeAdvancedMetrics
                )
                
                let generator = HealthKitTestDataGenerator(healthStore: healthKitManager.healthStore)
                try await generator.generateSampleData(config: config)
                
                await MainActor.run {
                    testDataMessage = """
                    ✅ Successfully generated \(daysToGenerate) days of realistic health data!
                    
                    Fitness Level: \(fitnessLevel.displayName)
                    Weekend Variation: \(includeWeekendVariation ? "Yes" : "No")
                    Workouts: \(includeWorkouts ? "Yes" : "No")
                    Sleep Stages: \(includeSleepStages ? "Yes" : "No")
                    Advanced Metrics: \(includeAdvancedMetrics ? "Yes" : "No")
                    
                    All data is tagged as synthetic. Go to Dashboard and tap "Sync Now" to upload!
                    """
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
                    testDataMessage = "✅ Generated a 30-minute running workout with realistic metrics. Check the Health app or sync now!"
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
    
    private func deleteSyntheticData() {
        isGeneratingTestData = true
        Task {
            do {
                let generator = HealthKitTestDataGenerator(healthStore: healthKitManager.healthStore)
                try await generator.deleteSyntheticData()
                
                await MainActor.run {
                    testDataMessage = "✅ Successfully deleted all synthetic data!\n\nOnly test data generated by this app was removed. Your real health data is safe."
                    showTestDataAlert = true
                    isGeneratingTestData = false
                }
            } catch {
                await MainActor.run {
                    testDataMessage = "❌ Failed to delete synthetic data: \(error.localizedDescription)"
                    showTestDataAlert = true
                    isGeneratingTestData = false
                }
            }
        }
    }
    
    private func runIntegrationTests() {
        isRunningTests = true
        testResults = []
        
        Task {
            do {
                let testHelper = IntegrationTestHelper(
                    healthStore: healthKitManager.healthStore,
                    syncCoordinator: syncCoordinator
                )
                
                let results = try await testHelper.runFullTestSuite()
                
                await MainActor.run {
                    testResults = results
                    isRunningTests = false
                    showTestResults = true
                }
            } catch {
                await MainActor.run {
                    testDataMessage = "❌ Test suite failed: \(error.localizedDescription)"
                    showTestDataAlert = true
                    isRunningTests = false
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
                .background(DBXGradients.heroHeader)
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
    
    // MARK: - Credentials Configuration
    
    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("API Credentials")
            
            HStack(spacing: 12) {
                Image(systemName: credentialsConfigured ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(credentialsConfigured ? DBXColors.dbxGreen : DBXColors.dbxYellow)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(credentialsConfigured ? "Credentials Configured" : "Credentials Required")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(credentialsConfigured ? 
                         "Service principal credentials are stored securely in the Keychain." :
                         "Configure your Databricks service principal credentials to enable data sync.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Button {
                showCredentialsConfig = true
            } label: {
                HStack {
                    Image(systemName: credentialsConfigured ? "pencil" : "key.fill")
                    Text(credentialsConfigured ? "Update Credentials" : "Configure Credentials")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(DBXSecondaryButtonStyle())
            
            if credentialsConfigured {
                credentialStatusRows
            }
            
            Text("Credentials are stored securely in the iOS Keychain and never leave your device except when requesting authentication tokens from Databricks.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dbxCard()
    }
    
    private var credentialStatusRows: some View {
        VStack(spacing: 8) {
            Divider()
                .padding(.vertical, 4)
            
            HStack {
                Image(systemName: "person.text.rectangle")
                    .foregroundStyle(DBXColors.dbxRed)
                    .frame(width: 24)
                Text("Client ID")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DBXColors.dbxGreen)
                    .font(.caption)
            }
            
            HStack {
                Image(systemName: "key.fill")
                    .foregroundStyle(DBXColors.dbxRed)
                    .frame(width: 24)
                Text("Client Secret")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DBXColors.dbxGreen)
                    .font(.caption)
            }
        }
    }
    
    private var credentialsConfigured: Bool {
        KeychainHelper.exists(for: KeychainHelper.Key.databricksClientID) &&
        KeychainHelper.exists(for: KeychainHelper.Key.databricksClientSecret)
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
