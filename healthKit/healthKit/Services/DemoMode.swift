import Foundation
import SwiftUI

/// Demo mode configuration for testing without polluting user's HealthKit data.
///
/// Two modes:
/// - **HealthKit Mode** (default): Writes to HealthKit, auto-deletes after 1 hour
/// - **Mock Mode**: Generates synthetic data directly, bypasses HealthKit entirely
@MainActor
final class DemoModeManager: ObservableObject {
    
    enum Mode: String, CaseIterable {
        case healthKit = "healthkit"
        case mock = "mock"
        
        var displayName: String {
            switch self {
            case .healthKit: return "HealthKit Mode"
            case .mock: return "Mock Mode"
            }
        }
        
        var description: String {
            switch self {
            case .healthKit:
                return "Writes to Apple Health app. Test data auto-deletes after 1 hour."
            case .mock:
                return "Generates data directly without HealthKit. No cleanup needed."
            }
        }
        
        var icon: String {
            switch self {
            case .healthKit: return "heart.text.square.fill"
            case .mock: return "wand.and.stars"
            }
        }
    }
    
    @AppStorage("demoMode") private var storedMode: String = Mode.healthKit.rawValue
    
    @Published var currentMode: Mode = .healthKit {
        didSet {
            storedMode = currentMode.rawValue
        }
    }
    
    /// Scheduled deletion times for HealthKit test data
    @Published var scheduledDeletions: [ScheduledDeletion] = []
    
    /// Timer for checking scheduled deletions
    private var deletionTimer: Timer?
    
    init() {
        // Initialize currentMode from stored value
        if let mode = Mode(rawValue: storedMode) {
            self.currentMode = mode
        }
        loadScheduledDeletions()
        startDeletionTimer()
    }
    
    // MARK: - Scheduled Deletions
    
    struct ScheduledDeletion: Codable, Identifiable, Equatable {
        let id: UUID
        let scheduledFor: Date
        let recordCount: Int
        let dataTypes: [String]
        
        var timeRemaining: TimeInterval {
            scheduledFor.timeIntervalSinceNow
        }
        
        var isExpired: Bool {
            timeRemaining <= 0
        }
        
        var formattedTimeRemaining: String {
            guard !isExpired else { return "Ready for deletion" }
            
            let minutes = Int(timeRemaining / 60)
            if minutes < 60 {
                return "\(minutes) minutes"
            } else {
                let hours = minutes / 60
                let mins = minutes % 60
                return "\(hours)h \(mins)m"
            }
        }
    }
    
    /// Schedule test data for deletion in 1 hour
    func scheduleHealthKitDeletion(recordCount: Int, dataTypes: [String]) {
        let deletion = ScheduledDeletion(
            id: UUID(),
            scheduledFor: Date().addingTimeInterval(3600), // 1 hour
            recordCount: recordCount,
            dataTypes: dataTypes
        )
        
        scheduledDeletions.append(deletion)
        saveScheduledDeletions()
        
        print("⏰ Scheduled deletion of \(recordCount) test records in 1 hour")
    }
    
    /// Remove a scheduled deletion
    func cancelScheduledDeletion(_ deletion: ScheduledDeletion) {
        scheduledDeletions.removeAll { $0.id == deletion.id }
        saveScheduledDeletions()
    }
    
    /// Check for expired deletions and execute them
    func checkScheduledDeletions(healthStore: HealthKitManager) async {
        let expired = scheduledDeletions.filter { $0.isExpired }
        
        guard !expired.isEmpty else { return }
        
        print("🗑️ Processing \(expired.count) expired deletion schedules...")
        
        for deletion in expired {
            do {
                let generator = HealthKitTestDataGenerator(healthStore: healthStore.healthStore)
                try await generator.deleteSyntheticData()
                
                // Remove from scheduled list
                scheduledDeletions.removeAll { $0.id == deletion.id }
                
                print("✅ Auto-deleted \(deletion.recordCount) test records")
            } catch {
                print("❌ Auto-deletion failed: \(error.localizedDescription)")
            }
        }
        
        saveScheduledDeletions()
    }
    
    // MARK: - Persistence
    
    private func saveScheduledDeletions() {
        if let encoded = try? JSONEncoder().encode(scheduledDeletions) {
            UserDefaults.standard.set(encoded, forKey: "scheduledDeletions")
        }
    }
    
    private func loadScheduledDeletions() {
        guard let data = UserDefaults.standard.data(forKey: "scheduledDeletions"),
              let decoded = try? JSONDecoder().decode([ScheduledDeletion].self, from: data) else {
            return
        }
        
        // Remove already-expired deletions from previous sessions
        scheduledDeletions = decoded.filter { !$0.isExpired || $0.timeRemaining > -3600 } // Keep up to 1 hour expired
    }
    
    // MARK: - Timer
    
    private func startDeletionTimer() {
        // Check every minute for expired deletions
        deletionTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                // Note: This requires HealthKitManager to be injected
                // We'll handle this in the view layer
                self.objectWillChange.send()
            }
        }
    }
    
    deinit {
        deletionTimer?.invalidate()
    }
}

// MARK: - Mock Data Generator

/// Generates synthetic data without writing to HealthKit
struct MockDataGenerator {
    
    /// Generate mock health samples
    static func generateMockSamples(days: Int, fitnessLevel: GeneratorConfig.FitnessLevel) -> [HealthSample] {
        var samples: [HealthSample] = []
        let calendar = Calendar.current
        
        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            
            // Generate steps
            let steps = baseSteps(for: fitnessLevel) + Int.random(in: -1000...1000)
            samples.append(HealthSample(
                uuid: UUID().uuidString,
                type: "HKQuantityTypeIdentifierStepCount",
                value: Double(steps),
                unit: "count",
                startDate: calendar.startOfDay(for: date),
                endDate: date,
                sourceName: "dbxWearables-Mock",
                sourceBundleId: "com.databricks.dbxWearables",
                metadata: ["demo_mode": "mock"]
            ))
            
            // Generate heart rate samples (5 per day)
            for hour in stride(from: 8, through: 20, by: 3) {
                guard let timestamp = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) else { continue }
                
                let hr = baseHeartRate(for: fitnessLevel) + Double.random(in: -10...10)
                samples.append(HealthSample(
                    uuid: UUID().uuidString,
                    type: "HKQuantityTypeIdentifierHeartRate",
                    value: hr,
                    unit: "count/min",
                    startDate: timestamp,
                    endDate: timestamp,
                    sourceName: "dbxWearables-Mock",
                    sourceBundleId: "com.databricks.dbxWearables",
                    metadata: ["demo_mode": "mock"]
                ))
            }
        }
        
        return samples
    }
    
    /// Generate mock workouts
    static func generateMockWorkouts(count: Int) -> [WorkoutRecord] {
        var workouts: [WorkoutRecord] = []
        
        for i in 0..<count {
            let daysAgo = i * 2 // Every other day
            guard let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) else { continue }
            
            let types: [(String, UInt)] = [
                ("Running", 37),
                ("Cycling", 13),
                ("Swimming", 46),
                ("Walking", 52)
            ]
            let (typeName, typeRaw) = types.randomElement()!
            
            let duration = Double.random(in: 1800...3600) // 30-60 minutes
            let calories = Double.random(in: 200...500)
            let distance = typeName == "Running" ? Double.random(in: 3000...8000) : nil
            
            workouts.append(WorkoutRecord(
                uuid: UUID().uuidString,
                activityType: typeName,
                activityTypeRaw: typeRaw,
                startDate: date,
                endDate: date.addingTimeInterval(duration),
                durationSeconds: duration,
                totalEnergyBurnedKcal: calories,
                totalDistanceMeters: distance,
                sourceName: "dbxWearables-Mock",
                metadata: ["demo_mode": "mock"]
            ))
        }
        
        return workouts
    }
    
    private static func baseSteps(for level: GeneratorConfig.FitnessLevel) -> Int {
        switch level {
        case .sedentary: return 3000
        case .light: return 6000
        case .moderate: return 10000
        case .active: return 14000
        case .veryActive: return 18000
        }
    }
    
    private static func baseHeartRate(for level: GeneratorConfig.FitnessLevel) -> Double {
        switch level {
        case .sedentary: return 75
        case .light: return 70
        case .moderate: return 65
        case .active: return 60
        case .veryActive: return 55
        }
    }
}
