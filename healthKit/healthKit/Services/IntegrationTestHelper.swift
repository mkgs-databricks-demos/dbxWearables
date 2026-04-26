import Foundation
import HealthKit

#if DEBUG

/// Helper for running integration tests with synthetic data
/// Tests the full pipeline: Generate → Sync → Verify → Delete
@MainActor
final class IntegrationTestHelper {
    
    private let healthStore: HKHealthStore
    private let syncCoordinator: SyncCoordinator
    private let syncLedger: SyncLedger
    
    init(healthStore: HKHealthStore, syncCoordinator: SyncCoordinator) {
        self.healthStore = healthStore
        self.syncCoordinator = syncCoordinator
        self.syncLedger = syncCoordinator.syncLedger
    }
    
    // MARK: - Test Scenarios
    
    /// Test Scenario 1: Sedentary user, 7 days
    func testScenario_Sedentary7Days() async throws -> TestResult {
        print("\n🧪 TEST: Sedentary user, 7 days")
        print(String(repeating: "=", count: 60))
        
        let config = GeneratorConfig(
            daysToGenerate: 7,
            fitnessLevel: .sedentary,
            includeWeekendVariation: true,
            includeWorkouts: false,
            includeSleepStages: true,
            includeAdvancedMetrics: true
        )
        
        return try await runTestScenario(config: config, name: "Sedentary_7Days")
    }
    
    /// Test Scenario 2: Moderate user, 30 days (typical use case)
    func testScenario_Moderate30Days() async throws -> TestResult {
        print("\n🧪 TEST: Moderate user, 30 days")
        print(String(repeating: "=", count: 60))
        
        let config = GeneratorConfig(
            daysToGenerate: 30,
            fitnessLevel: .moderate,
            includeWeekendVariation: true,
            includeWorkouts: true,
            includeSleepStages: true,
            includeAdvancedMetrics: true
        )
        
        return try await runTestScenario(config: config, name: "Moderate_30Days")
    }
    
    /// Test Scenario 3: Very Active user, 90 days (stress test)
    func testScenario_VeryActive90Days() async throws -> TestResult {
        print("\n🧪 TEST: Very Active user, 90 days (LARGE DATASET)")
        print(String(repeating: "=", count: 60))
        
        let config = GeneratorConfig(
            daysToGenerate: 90,
            fitnessLevel: .veryActive,
            includeWeekendVariation: true,
            includeWorkouts: true,
            includeSleepStages: true,
            includeAdvancedMetrics: true
        )
        
        return try await runTestScenario(config: config, name: "VeryActive_90Days")
    }
    
    /// Test Scenario 4: Minimal data (edge case)
    func testScenario_Minimal() async throws -> TestResult {
        print("\n🧪 TEST: Minimal data (no extras)")
        print(String(repeating: "=", count: 60))
        
        let config = GeneratorConfig(
            daysToGenerate: 7,
            fitnessLevel: .light,
            includeWeekendVariation: false,
            includeWorkouts: false,
            includeSleepStages: false,
            includeAdvancedMetrics: false
        )
        
        return try await runTestScenario(config: config, name: "Minimal")
    }
    
    /// Test Scenario 5: Deletion workflow
    func testScenario_DeletionWorkflow() async throws -> TestResult {
        print("\n🧪 TEST: Deletion workflow")
        print(String(repeating: "=", count: 60))
        
        // Generate small dataset
        let config = GeneratorConfig(
            daysToGenerate: 7,
            fitnessLevel: .moderate,
            includeWeekendVariation: true,
            includeWorkouts: true,
            includeSleepStages: true,
            includeAdvancedMetrics: true
        )
        
        let generator = HealthKitTestDataGenerator(healthStore: healthStore)
        
        print("1️⃣ Generating data...")
        try await generator.generateSampleData(config: config)
        
        print("2️⃣ First sync...")
        let statsBeforeDelete = await syncLedger.getStats()
        let initialCounts = statsBeforeDelete.totalRecordsSent
        await syncCoordinator.sync(context: .foreground)
        
        // Wait a moment for sync to complete
        try await Task.sleep(for: .seconds(2))
        
        print("3️⃣ Deleting synthetic data...")
        try await generator.deleteSyntheticData()
        
        print("4️⃣ Second sync (should send deletions)...")
        await syncCoordinator.sync(context: .foreground)
        
        // Wait for deletion sync
        try await Task.sleep(for: .seconds(2))
        
        let statsAfterDelete = await syncLedger.getStats()
        let deleteCount = statsAfterDelete.totalRecordsSent["deletes", default: 0]
        
        let result = TestResult(
            scenarioName: "DeletionWorkflow",
            config: config,
            samplesGenerated: 0, // N/A for this test
            recordsSynced: initialCounts,
            deletionCount: deleteCount,
            duration: 0,
            success: deleteCount > 0,
            notes: "Verified deletion records sent: \(deleteCount)"
        )
        
        result.printSummary()
        return result
    }
    
    // MARK: - Test Execution
    
    private func runTestScenario(config: GeneratorConfig, name: String) async throws -> TestResult {
        let startTime = Date()
        
        // Step 1: Generate data
        print("1️⃣ Generating \(config.daysToGenerate) days of data...")
        let generator = HealthKitTestDataGenerator(healthStore: healthStore)
        try await generator.generateSampleData(config: config)
        
        print("✅ Data generated")
        
        // Step 2: Get baseline stats
        let statsBefore = await syncLedger.getStats()
        let recordsBeforeSync = statsBefore.totalRecordsSent.values.reduce(0, +)
        
        // Step 3: Sync data
        print("\n2️⃣ Syncing to Databricks...")
        await syncCoordinator.sync(context: .foreground)
        
        // Wait a bit for sync to complete
        try await Task.sleep(for: .seconds(3))
        
        // Step 4: Verify sync
        print("\n3️⃣ Verifying sync results...")
        let statsAfter = await syncLedger.getStats()
        let recordsAfterSync = statsAfter.totalRecordsSent.values.reduce(0, +)
        let recordsSynced = recordsAfterSync - recordsBeforeSync
        
        // Step 5: Validate payloads
        print("\n4️⃣ Validating NDJSON payloads...")
        let payloadValidation = await validatePayloads()
        
        let duration = Date().timeIntervalSince(startTime)
        
        let result = TestResult(
            scenarioName: name,
            config: config,
            samplesGenerated: 0, // Generator prints this
            recordsSynced: statsAfter.totalRecordsSent,
            deletionCount: 0,
            duration: duration,
            success: recordsSynced > 0 && payloadValidation.isValid,
            notes: payloadValidation.notes
        )
        
        result.printSummary()
        
        return result
    }
    
    private func validatePayloads() async -> (isValid: Bool, notes: String) {
        var validationNotes: [String] = []
        var allValid = true
        
        let recordTypes = ["samples", "workouts", "sleep", "activity_summaries"]
        
        for type in recordTypes {
            if let payload = await syncLedger.getLastPayload(for: type) {
                // Check 1: Has NDJSON content
                guard let ndjson = payload.ndjsonPayload, !ndjson.isEmpty else {
                    validationNotes.append("❌ \(type): Empty payload")
                    allValid = false
                    continue
                }
                
                // Check 2: Valid JSON lines
                let lines = ndjson.split(separator: "\n")
                var validLines = 0
                
                for line in lines {
                    if let data = line.data(using: .utf8),
                       let _ = try? JSONSerialization.jsonObject(with: data) {
                        validLines += 1
                    }
                }
                
                if validLines == lines.count {
                    validationNotes.append("✅ \(type): \(validLines) valid JSON lines")
                } else {
                    validationNotes.append("⚠️ \(type): \(validLines)/\(lines.count) valid lines")
                    allValid = false
                }
                
                // Check 3: Has required headers
                let requiredHeaders = ["X-Record-Type", "X-Device-Id", "X-Platform"]
                for header in requiredHeaders {
                    if payload.requestHeaders[header] == nil {
                        validationNotes.append("⚠️ \(type): Missing header \(header)")
                        allValid = false
                    }
                }
            }
        }
        
        return (allValid, validationNotes.joined(separator: "\n"))
    }
    
    // MARK: - Test Suite Runner
    
    /// Run all test scenarios in sequence
    func runFullTestSuite() async throws -> [TestResult] {
        print("\n" + String(repeating: "=", count: 60))
        print("🧪 INTEGRATION TEST SUITE")
        print(String(repeating: "=", count: 60))
        
        var results: [TestResult] = []
        
        // Run all scenarios
        results.append(try await testScenario_Sedentary7Days())
        results.append(try await testScenario_Minimal())
        results.append(try await testScenario_Moderate30Days())
        results.append(try await testScenario_DeletionWorkflow())
        // Uncomment for full stress test:
        // results.append(try await testScenario_VeryActive90Days())
        
        // Print summary
        printTestSuiteSummary(results)
        
        return results
    }
    
    private func printTestSuiteSummary(_ results: [TestResult]) {
        print("\n" + String(repeating: "=", count: 60))
        print("📊 TEST SUITE SUMMARY")
        print(String(repeating: "=", count: 60))
        
        let passed = results.filter { $0.success }.count
        let failed = results.count - passed
        
        print("\nResults: \(passed)/\(results.count) passed")
        
        for result in results {
            let icon = result.success ? "✅" : "❌"
            print("\(icon) \(result.scenarioName) (\(String(format: "%.1f", result.duration))s)")
        }
        
        if failed == 0 {
            print("\n🎉 ALL TESTS PASSED!")
        } else {
            print("\n⚠️ \(failed) TEST(S) FAILED")
        }
        
        print(String(repeating: "=", count: 60) + "\n")
    }
}

// MARK: - Test Result

struct TestResult {
    let scenarioName: String
    let config: GeneratorConfig
    let samplesGenerated: Int
    let recordsSynced: [String: Int]
    let deletionCount: Int
    let duration: TimeInterval
    let success: Bool
    let notes: String
    
    func printSummary() {
        print("\n" + String(repeating: "-", count: 60))
        print("📋 TEST RESULT: \(scenarioName)")
        print(String(repeating: "-", count: 60))
        print("Status: \(success ? "✅ PASS" : "❌ FAIL")")
        print("Duration: \(String(format: "%.2f", duration))s")
        print("\nConfiguration:")
        print("  Days: \(config.daysToGenerate)")
        print("  Fitness: \(config.fitnessLevel.displayName)")
        print("  Weekend Variation: \(config.includeWeekendVariation)")
        print("  Workouts: \(config.includeWorkouts)")
        print("  Sleep Stages: \(config.includeSleepStages)")
        print("  Advanced Metrics: \(config.includeAdvancedMetrics)")
        
        print("\nRecords Synced:")
        for (type, count) in recordsSynced.sorted(by: { $0.key < $1.key }) {
            if count > 0 {
                print("  \(type): \(count)")
            }
        }
        
        if deletionCount > 0 {
            print("  Deletions: \(deletionCount)")
        }
        
        if !notes.isEmpty {
            print("\nValidation:")
            print(notes)
        }
        
        print(String(repeating: "-", count: 60))
    }
}

#endif
