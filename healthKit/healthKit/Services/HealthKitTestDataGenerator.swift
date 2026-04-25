import Foundation
import HealthKit

/// Generates sample HealthKit data for testing and development.
final class HealthKitTestDataGenerator {
    
    private let healthStore: HKHealthStore
    
    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
    }
    
    /// Generate a variety of sample health data for the past 30 days
    func generateSampleData() async throws {
        let calendar = Calendar.current
        let now = Date()
        
        // Generate data for the past 30 days
        for daysAgo in 0..<30 {
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) else { continue }
            
            try await generateDailyData(for: date)
        }
        
        print("✅ Successfully generated 30 days of sample health data")
    }
    
    /// Generate health data for a specific day
    private func generateDailyData(for date: Date) async throws {
        let calendar = Calendar.current
        guard let startOfDay = calendar.startOfDay(for: date) as Date?,
              let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return
        }
        
        var samples: [HKObject] = []
        
        // Steps (random between 5,000 and 15,000)
        if let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            let steps = Double.random(in: 5000...15000)
            let stepsSample = HKQuantitySample(
                type: stepsType,
                quantity: HKQuantity(unit: .count(), doubleValue: steps),
                start: startOfDay,
                end: endOfDay
            )
            samples.append(stepsSample)
        }
        
        // Active Energy (random between 300 and 800 kcal)
        if let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            let calories = Double.random(in: 300...800)
            let energySample = HKQuantitySample(
                type: activeEnergyType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
                start: startOfDay,
                end: endOfDay
            )
            samples.append(energySample)
        }
        
        // Exercise Time / Stand Hours / Stand Time are Apple-managed and cannot be
        // written by third-party apps — they're derived from raw activity by the
        // system. We rely on the OS to populate those from the steps + heart rate
        // samples this generator emits.

        // Distance Walking/Running (random between 3 and 10 km)
        if let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            let distance = Double.random(in: 3000...10000) // meters
            let distanceSample = HKQuantitySample(
                type: distanceType,
                quantity: HKQuantity(unit: .meter(), doubleValue: distance),
                start: startOfDay,
                end: endOfDay
            )
            samples.append(distanceSample)
        }
        
        // Heart Rate samples throughout the day
        if let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            // Generate 10 heart rate readings throughout the day
            for hour in stride(from: 0, to: 24, by: 2.4) {
                guard let timestamp = calendar.date(byAdding: .minute, value: Int(hour * 60), to: startOfDay) else { continue }
                let bpm = Double.random(in: 60...100)
                let heartRateSample = HKQuantitySample(
                    type: heartRateType,
                    quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: bpm),
                    start: timestamp,
                    end: timestamp
                )
                samples.append(heartRateSample)
            }
        }
        
        // Resting Heart Rate (random between 55 and 75 bpm)
        if let restingHRType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            let restingBPM = Double.random(in: 55...75)
            let restingHRSample = HKQuantitySample(
                type: restingHRType,
                quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: restingBPM),
                start: startOfDay,
                end: startOfDay
            )
            samples.append(restingHRSample)
        }
        
        // Sleep data (7-9 hours)
        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis),
           let bedtime = calendar.date(byAdding: .hour, value: -8, to: startOfDay) {
            let sleepHours = Double.random(in: 7...9)
            guard let wakeTime = calendar.date(byAdding: .hour, value: Int(sleepHours), to: bedtime) else { return }
            
            let sleepSample = HKCategorySample(
                type: sleepType,
                value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                start: bedtime,
                end: wakeTime
            )
            samples.append(sleepSample)
        }
        
        // Save all samples
        try await healthStore.save(samples)
    }
    
    /// Generate a single workout (useful for testing)
    func generateSampleWorkout(
        type: HKWorkoutActivityType = .running,
        date: Date = Date(),
        duration: TimeInterval = 1800 // 30 minutes
    ) async throws {
        let startDate = date
        let endDate = startDate.addingTimeInterval(duration)
        
        let workout = HKWorkout(
            activityType: type,
            start: startDate,
            end: endDate,
            duration: duration,
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 250),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 5000),
            metadata: nil
        )
        
        try await healthStore.save(workout)
        print("✅ Generated workout: \(type) for \(duration/60) minutes")
    }
    
    /// Delete all sample data (use carefully!)
    func deleteAllSampleData() async throws {
        let types: [HKQuantityTypeIdentifier] = [
            .stepCount,
            .activeEnergyBurned,
            .distanceWalkingRunning,
            .heartRate,
            .restingHeartRate,
        ]
        
        for identifier in types {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { continue }
            try await deleteAllSamples(of: type)
        }
        
        // Delete sleep data
        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            try await deleteAllSamples(of: sleepType)
        }
        
        print("✅ Deleted all sample data")
    }
    
    private func deleteAllSamples(of sampleType: HKSampleType) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: .strictStartDate)
            
            healthStore.deleteObjects(of: sampleType, predicate: predicate) { success, count, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    if count > 0 {
                        print("  Deleted \(count) samples of type: \(sampleType)")
                    }
                    continuation.resume()
                }
            }
        }
    }
}
