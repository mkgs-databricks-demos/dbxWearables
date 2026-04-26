import Foundation
import HealthKit

/// Configuration for synthetic data generation
struct GeneratorConfig {
    var daysToGenerate: Int = 30
    var fitnessLevel: FitnessLevel = .moderate
    var includeWeekendVariation: Bool = true
    var includeWorkouts: Bool = true
    var includeSleepStages: Bool = true
    var includeAdvancedMetrics: Bool = true
    
    enum FitnessLevel {
        case sedentary, light, moderate, active, veryActive
        
        var displayName: String {
            switch self {
            case .sedentary: return "Sedentary"
            case .light: return "Light"
            case .moderate: return "Moderate"
            case .active: return "Active"
            case .veryActive: return "Very Active"
            }
        }
        
        var stepRange: ClosedRange<Double> {
            switch self {
            case .sedentary: return 2000...5000
            case .light: return 5000...8000
            case .moderate: return 8000...12000
            case .active: return 12000...16000
            case .veryActive: return 16000...22000
            }
        }
        
        var activeCalorieRange: ClosedRange<Double> {
            switch self {
            case .sedentary: return 200...400
            case .light: return 400...600
            case .moderate: return 600...900
            case .active: return 900...1200
            case .veryActive: return 1200...1800
            }
        }
        
        var restingHRRange: ClosedRange<Double> {
            switch self {
            case .sedentary: return 65...80
            case .light: return 60...75
            case .moderate: return 55...70
            case .active: return 50...65
            case .veryActive: return 45...60
            }
        }
    }
}

/// Generates realistic sample HealthKit data for testing and development.
/// Each sample has a unique UUID and metadata to identify it as synthetic.
final class HealthKitTestDataGenerator {
    
    private let healthStore: HKHealthStore
    private let generatorID = UUID().uuidString
    
    /// Metadata key to identify synthetic data
    static let syntheticDataKey = "com.dbxwearables.synthetic"
    
    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
    }
    
    /// Generate a variety of sample health data with realistic patterns
    func generateSampleData(config: GeneratorConfig = GeneratorConfig()) async throws {
        let calendar = Calendar.current
        let now = Date()
        
        var totalSamples = 0
        
        // Generate data for each day
        for daysAgo in 0..<config.daysToGenerate {
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) else { continue }
            
            let isWeekend = calendar.isDateInWeekend(date)
            let dayMultiplier = (config.includeWeekendVariation && isWeekend) ? 0.7 : 1.0
            
            let count = try await generateDailyData(
                for: date,
                config: config,
                dayMultiplier: dayMultiplier,
                dayIndex: daysAgo
            )
            totalSamples += count
        }
        
        print("✅ Successfully generated \(totalSamples) samples across \(config.daysToGenerate) days")
        print("   Fitness level: \(config.fitnessLevel)")
        print("   Generator ID: \(generatorID)")
    }
    
    /// Generate health data for a specific day with realistic patterns
    private func generateDailyData(
        for date: Date,
        config: GeneratorConfig,
        dayMultiplier: Double,
        dayIndex: Int
    ) async throws -> Int {
        let calendar = Calendar.current
        guard let startOfDay = calendar.startOfDay(for: date) as Date?,
              let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return 0
        }
        
        var samples: [HKObject] = []
        let metadata = createMetadata()
        
        // Trend: slight improvement over time (more recent = better fitness)
        let trendMultiplier = 1.0 + (Double(config.daysToGenerate - dayIndex) / Double(config.daysToGenerate) * 0.15)
        
        // MARK: - Steps (with hourly distribution)
        if let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            let baseSteps = config.fitnessLevel.stepRange.randomElement() * dayMultiplier * trendMultiplier
            samples += generateHourlySteps(baseSteps: baseSteps, startOfDay: startOfDay, type: stepsType, metadata: metadata)
        }
        
        // MARK: - Active Energy
        if let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            let calories = config.fitnessLevel.activeCalorieRange.randomElement() * dayMultiplier * trendMultiplier
            let energySample = HKQuantitySample(
                type: activeEnergyType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
                start: startOfDay,
                end: endOfDay,
                metadata: metadata
            )
            samples.append(energySample)
        }
        
        // MARK: - Basal Energy
        if let basalEnergyType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned) {
            // Basal metabolic rate ~1400-1800 kcal/day
            let basalCalories = Double.random(in: 1400...1800)
            let basalSample = HKQuantitySample(
                type: basalEnergyType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: basalCalories),
                start: startOfDay,
                end: endOfDay,
                metadata: metadata
            )
            samples.append(basalSample)
        }
        
        // MARK: - Distance
        if let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            let distance = Double.random(in: 3000...12000) * dayMultiplier * trendMultiplier
            let distanceSample = HKQuantitySample(
                type: distanceType,
                quantity: HKQuantity(unit: .meter(), doubleValue: distance),
                start: startOfDay,
                end: endOfDay,
                metadata: metadata
            )
            samples.append(distanceSample)
        }
        
        // MARK: - Heart Rate (realistic daily pattern)
        if let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            samples += generateRealisticHeartRate(startOfDay: startOfDay, config: config, type: heartRateType, metadata: metadata)
        }
        
        // MARK: - Resting Heart Rate
        if let restingHRType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            let restingBPM = config.fitnessLevel.restingHRRange.randomElement() - (trendMultiplier - 1.0) * 5
            let restingHRSample = HKQuantitySample(
                type: restingHRType,
                quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: restingBPM),
                start: startOfDay,
                end: startOfDay,
                metadata: metadata
            )
            samples.append(restingHRSample)
        }
        
        // MARK: - Advanced Metrics (HRV, SpO2)
        if config.includeAdvancedMetrics {
            // Heart Rate Variability (SDNN)
            if let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
                let hrv = Double.random(in: 30...80) + (trendMultiplier - 1.0) * 10
                let hrvSample = HKQuantitySample(
                    type: hrvType,
                    quantity: HKQuantity(unit: .secondUnit(with: .milli), doubleValue: hrv),
                    start: startOfDay,
                    end: startOfDay,
                    metadata: metadata
                )
                samples.append(hrvSample)
            }
            
            // Oxygen Saturation (SpO2)
            if let spo2Type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) {
                let spo2 = Double.random(in: 0.95...0.99) // 95-99%
                let spo2Sample = HKQuantitySample(
                    type: spo2Type,
                    quantity: HKQuantity(unit: .percent(), doubleValue: spo2),
                    start: startOfDay,
                    end: startOfDay,
                    metadata: metadata
                )
                samples.append(spo2Sample)
            }
            
            // VO2 Max (cardio fitness - every 7 days)
            if dayIndex % 7 == 0, let vo2MaxType = HKQuantityType.quantityType(forIdentifier: .vo2Max) {
                let vo2Max = Double.random(in: 35...55) + (trendMultiplier - 1.0) * 5
                let vo2Sample = HKQuantitySample(
                    type: vo2MaxType,
                    quantity: HKQuantity(unit: HKUnit.literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .minute())), doubleValue: vo2Max),
                    start: startOfDay,
                    end: startOfDay,
                    metadata: metadata
                )
                samples.append(vo2Sample)
            }
        }
        
        // MARK: - Sleep (with stages)
        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis),
           let bedtime = calendar.date(byAdding: .hour, value: -8, to: startOfDay) {
            
            if config.includeSleepStages {
                samples += generateRealisticSleep(bedtime: bedtime, type: sleepType, metadata: metadata)
            } else {
                let sleepHours = Double.random(in: 6.5...8.5)
                guard let wakeTime = calendar.date(byAdding: .minute, value: Int(sleepHours * 60), to: bedtime) else {
                    return samples.count
                }
                let sleepSample = HKCategorySample(
                    type: sleepType,
                    value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    start: bedtime,
                    end: wakeTime,
                    metadata: metadata
                )
                samples.append(sleepSample)
            }
        }
        
        // MARK: - Workouts (2-3 times per week)
        if config.includeWorkouts && dayIndex % 3 == 0 {
            if let workout = try? await generateRealisticWorkout(for: date, config: config, metadata: metadata) {
                samples.append(workout)
            }
        }
        
        // Save all samples
        try await healthStore.save(samples)
        
        return samples.count
    }
    
    // MARK: - Realistic Patterns
    
    /// Generate hourly step distribution (more realistic than one daily total)
    private func generateHourlySteps(
        baseSteps: Double,
        startOfDay: Date,
        type: HKQuantityType,
        metadata: [String: Any]
    ) -> [HKQuantitySample] {
        var samples: [HKQuantitySample] = []
        let calendar = Calendar.current
        
        // Distribute steps across waking hours (7am - 11pm)
        let wakingHours = 7...22
        let stepsPerHour = baseSteps / Double(wakingHours.count)
        
        for hour in wakingHours {
            guard let hourStart = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: startOfDay),
                  let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart) else { continue }
            
            // Vary steps by time of day (more during morning/evening commute)
            var multiplier = 1.0
            if hour == 8 || hour == 9 || hour == 17 || hour == 18 { multiplier = 1.3 }
            if hour >= 12 && hour <= 14 { multiplier = 1.2 } // lunch walk
            if hour < 7 || hour > 23 { multiplier = 0.1 } // sleeping
            
            let steps = stepsPerHour * multiplier * Double.random(in: 0.8...1.2)
            
            let sample = HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: .count(), doubleValue: steps),
                start: hourStart,
                end: hourEnd,
                metadata: metadata
            )
            samples.append(sample)
        }
        
        return samples
    }
    
    /// Generate realistic heart rate throughout the day
    private func generateRealisticHeartRate(
        startOfDay: Date,
        config: GeneratorConfig,
        type: HKQuantityType,
        metadata: [String: Any]
    ) -> [HKQuantitySample] {
        var samples: [HKQuantitySample] = []
        let calendar = Calendar.current
        let restingHR = config.fitnessLevel.restingHRRange.randomElement()
        
        // Generate readings every 15 minutes during waking hours
        for hour in 7...23 {
            for minute in stride(from: 0, to: 60, by: 15) {
                guard let timestamp = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: startOfDay) else { continue }
                
                // Vary HR based on time of day
                var bpm = restingHR
                if hour >= 6 && hour <= 9 { bpm += Double.random(in: 10...25) } // morning activity
                if hour >= 12 && hour <= 13 { bpm += Double.random(in: 5...15) } // lunch
                if hour >= 17 && hour <= 19 { bpm += Double.random(in: 15...30) } // evening activity
                if hour >= 22 { bpm -= Double.random(in: 5...10) } // winding down
                
                // Add random variation
                bpm += Double.random(in: -5...5)
                bpm = max(50, min(180, bpm)) // Clamp to realistic range
                
                let sample = HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: bpm),
                    start: timestamp,
                    end: timestamp,
                    metadata: metadata
                )
                samples.append(sample)
            }
        }
        
        return samples
    }
    
    /// Generate realistic sleep with stages (light, deep, REM)
    private func generateRealisticSleep(
        bedtime: Date,
        type: HKCategoryType,
        metadata: [String: Any]
    ) -> [HKCategorySample] {
        var samples: [HKCategorySample] = []
        let calendar = Calendar.current
        
        let totalSleepMinutes = Double.random(in: 390...510) // 6.5-8.5 hours
        var currentTime = bedtime
        var remainingMinutes = totalSleepMinutes
        
        // Sleep cycle: Light → Deep → REM (repeats ~90 min cycles)
        let cycles = Int(totalSleepMinutes / 90)
        let minutesPerCycle = totalSleepMinutes / Double(cycles)
        
        for cycle in 0..<cycles {
            let cycleMultiplier = cycle == 0 ? 1.2 : 1.0 // First cycle longer
            
            // Awake brief moments between cycles
            if cycle > 0 {
                let awakeDuration = Double.random(in: 2...5)
                if let awakeEnd = calendar.date(byAdding: .minute, value: Int(awakeDuration), to: currentTime) {
                    let awakeSample = HKCategorySample(
                        type: type,
                        value: HKCategoryValueSleepAnalysis.awake.rawValue,
                        start: currentTime,
                        end: awakeEnd,
                        metadata: metadata
                    )
                    samples.append(awakeSample)
                    currentTime = awakeEnd
                    remainingMinutes -= awakeDuration
                }
            }
            
            // Light sleep (50% of cycle)
            let lightDuration = min(minutesPerCycle * 0.5 * cycleMultiplier, remainingMinutes)
            if let lightEnd = calendar.date(byAdding: .minute, value: Int(lightDuration), to: currentTime) {
                let lightSample = HKCategorySample(
                    type: type,
                    value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    start: currentTime,
                    end: lightEnd,
                    metadata: metadata
                )
                samples.append(lightSample)
                currentTime = lightEnd
                remainingMinutes -= lightDuration
            }
            
            // Deep sleep (25% of cycle)
            let deepDuration = min(minutesPerCycle * 0.25 * cycleMultiplier, remainingMinutes)
            if let deepEnd = calendar.date(byAdding: .minute, value: Int(deepDuration), to: currentTime) {
                let deepSample = HKCategorySample(
                    type: type,
                    value: HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    start: currentTime,
                    end: deepEnd,
                    metadata: metadata
                )
                samples.append(deepSample)
                currentTime = deepEnd
                remainingMinutes -= deepDuration
            }
            
            // REM sleep (25% of cycle)
            let remDuration = min(minutesPerCycle * 0.25, remainingMinutes)
            if let remEnd = calendar.date(byAdding: .minute, value: Int(remDuration), to: currentTime) {
                let remSample = HKCategorySample(
                    type: type,
                    value: HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                    start: currentTime,
                    end: remEnd,
                    metadata: metadata
                )
                samples.append(remSample)
                currentTime = remEnd
                remainingMinutes -= remDuration
            }
        }
        
        return samples
    }
    
    /// Generate realistic workout with varied types
    private func generateRealisticWorkout(
        for date: Date,
        config: GeneratorConfig,
        metadata: [String: Any]
    ) async throws -> HKWorkout {
        let calendar = Calendar.current
        
        // Workout types with realistic durations and intensities
        let workoutTypes: [(HKWorkoutActivityType, ClosedRange<TimeInterval>, ClosedRange<Double>, ClosedRange<Double>)] = [
            (.running, 1200...3600, 300...600, 3000...10000), // 20-60 min, calories, distance(m)
            (.cycling, 1800...5400, 400...800, 10000...40000),
            (.swimming, 1800...3600, 300...500, 1000...3000),
            (.walking, 1800...5400, 150...350, 3000...8000),
            (.yoga, 1800...3600, 100...200, 0...0),
            (.functionalStrengthTraining, 1800...3600, 200...400, 0...0),
            (.hiking, 3600...7200, 400...700, 5000...15000),
        ]
        
        let (type, durationRange, calorieRange, distanceRange) = workoutTypes.randomElement()!
        
        let duration = TimeInterval.random(in: durationRange)
        let calories = Double.random(in: calorieRange) * (config.fitnessLevel == .veryActive ? 1.2 : 1.0)
        let distance = distanceRange.lowerBound > 0 ? Double.random(in: distanceRange) : nil
        
        // Workout typically happens in morning (6-9am) or evening (5-8pm)
        let hour = Bool.random() ? Int.random(in: 6...9) : Int.random(in: 17...20)
        guard let workoutStart = calendar.date(bySettingHour: hour, minute: Int.random(in: 0...59), second: 0, of: calendar.startOfDay(for: date)) else {
            throw NSError(domain: "Generator", code: 1, userInfo: nil)
        }
        
        let workoutEnd = workoutStart.addingTimeInterval(duration)
        
        // Use HKWorkoutBuilder (iOS 17+) to create workout
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = type
        
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
        
        // Start the workout session
        try await builder.beginCollection(at: workoutStart)
        
        // Add energy burned if available
        let energyBurned = HKQuantity(unit: .kilocalorie(), doubleValue: calories)
        let energySample = HKCumulativeQuantitySample(
            type: HKQuantityType(.activeEnergyBurned),
            quantity: energyBurned,
            start: workoutStart,
            end: workoutEnd
        )
        try await builder.addSamples([energySample])
        
        // Add distance if applicable
        if let distance = distance {
            let distanceQuantity = HKQuantity(unit: .meter(), doubleValue: distance)
            let distanceSample = HKCumulativeQuantitySample(
                type: HKQuantityType(.distanceWalkingRunning),
                quantity: distanceQuantity,
                start: workoutStart,
                end: workoutEnd
            )
            try await builder.addSamples([distanceSample])
        }
        
        // Add metadata
        try await builder.addMetadata(metadata)
        
        // Finish and create the workout
        try await builder.endCollection(at: workoutEnd)
        guard let workout = try await builder.finishWorkout() else {
            throw NSError(domain: "Generator", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create workout"])
        }
        
        return workout
    }
    
    // MARK: - Metadata
    
    /// Create metadata to identify synthetic samples
    private func createMetadata() -> [String: Any] {
        return [
            Self.syntheticDataKey: true,
            "generator_id": generatorID,
            "generated_at": ISO8601DateFormatter().string(from: Date())
        ]
    }
    
    // MARK: - Single Workout Generation
    
    /// Generate a single workout (useful for quick testing)
    func generateSampleWorkout(
        type: HKWorkoutActivityType = .running,
        date: Date = Date(),
        duration: TimeInterval = 1800 // 30 minutes
    ) async throws {
        let startDate = date
        let endDate = startDate.addingTimeInterval(duration)
        let metadata = createMetadata()
        
        // Use HKWorkoutBuilder (iOS 17+)
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = type
        
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
        
        // Start the workout
        try await builder.beginCollection(at: startDate)
        
        // Add energy burned
        let energySample = HKCumulativeQuantitySample(
            type: HKQuantityType(.activeEnergyBurned),
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: 250),
            start: startDate,
            end: endDate
        )
        try await builder.addSamples([energySample])
        
        // Add distance (for running/walking/cycling)
        if type == .running || type == .walking || type == .cycling {
            let distanceSample = HKCumulativeQuantitySample(
                type: HKQuantityType(.distanceWalkingRunning),
                quantity: HKQuantity(unit: .meter(), doubleValue: 5000),
                start: startDate,
                end: endDate
            )
            try await builder.addSamples([distanceSample])
        }
        
        // Add metadata
        try await builder.addMetadata(metadata)
        
        // Finish the workout
        try await builder.endCollection(at: endDate)
        guard let _ = try await builder.finishWorkout() else {
            throw NSError(domain: "Generator", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create workout"])
        }
        
        print("✅ Generated workout: \(type.displayName) for \(Int(duration/60)) minutes")
    }
    
    // MARK: - Delete Functions
    
    /// Delete ONLY synthetic data generated by this tool (safe!)
    func deleteSyntheticData() async throws {
        var totalDeleted = 0
        
        // Quantity types
        let quantityTypes: [HKQuantityTypeIdentifier] = [
            .stepCount,
            .activeEnergyBurned,
            .basalEnergyBurned,
            .distanceWalkingRunning,
            .heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .oxygenSaturation,
            .vo2Max,
        ]
        
        for identifier in quantityTypes {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { continue }
            let count = try await deleteSyntheticSamples(of: type)
            totalDeleted += count
        }
        
        // Category types
        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            let count = try await deleteSyntheticSamples(of: sleepType)
            totalDeleted += count
        }
        
        // Workouts
        let workoutCount = try await deleteSyntheticWorkouts()
        totalDeleted += workoutCount
        
        print("✅ Deleted \(totalDeleted) synthetic samples")
    }
    
    /// Delete ALL sample data (DANGEROUS - use only for testing!)
    func deleteAllSampleData() async throws {
        print("⚠️ WARNING: Deleting ALL health data (including real data)!")
        
        let types: [HKQuantityTypeIdentifier] = [
            .stepCount,
            .activeEnergyBurned,
            .basalEnergyBurned,
            .distanceWalkingRunning,
            .heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .oxygenSaturation,
        ]
        
        for identifier in types {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { continue }
            try await deleteAllSamples(of: type)
        }
        
        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            try await deleteAllSamples(of: sleepType)
        }
        
        print("✅ Deleted all sample data")
    }
    
    private func deleteSyntheticSamples(of sampleType: HKSampleType) async throws -> Int {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            // Predicate to match only synthetic data
            let syntheticPredicate = HKQuery.predicateForObjects(withMetadataKey: Self.syntheticDataKey)
            
            healthStore.deleteObjects(of: sampleType, predicate: syntheticPredicate) { success, count, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    if count > 0 {
                        print("  Deleted \(count) synthetic samples of type: \(sampleType.identifier)")
                    }
                    continuation.resume(returning: count)
                }
            }
        }
    }
    
    private func deleteSyntheticWorkouts() async throws -> Int {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            let syntheticPredicate = HKQuery.predicateForObjects(withMetadataKey: Self.syntheticDataKey)
            
            healthStore.deleteObjects(of: HKSeriesType.workoutType(), predicate: syntheticPredicate) { success, count, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    if count > 0 {
                        print("  Deleted \(count) synthetic workouts")
                    }
                    continuation.resume(returning: count)
                }
            }
        }
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
// MARK: - Helper Extensions

extension ClosedRange where Bound == Double {
    func randomElement() -> Double {
        Double.random(in: self)
    }
}

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .walking: return "Walking"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Strength Training"
        case .hiking: return "Hiking"
        default: return "Workout"
        }
    }
}

