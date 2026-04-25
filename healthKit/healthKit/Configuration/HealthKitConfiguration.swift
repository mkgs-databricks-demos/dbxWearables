import HealthKit

/// Whether the sync is running while the user has the app open (foreground)
/// or during a background execution window (~30s).
enum SyncContext {
    case foreground
    case background
}

/// Defines which HealthKit data types the app reads and syncs.
enum HealthKitConfiguration {

    /// Quantity types to query from HealthKit.
    static let quantityTypes: Set<HKQuantityType> = [
        HKQuantityType(.stepCount),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.basalEnergyBurned),
        HKQuantityType(.heartRate),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.oxygenSaturation),
        HKQuantityType(.appleExerciseTime),
        HKQuantityType(.appleStandTime),
        HKQuantityType(.vo2Max),
    ]

    /// Category types to query from HealthKit.
    static let categoryTypes: Set<HKCategoryType> = [
        HKCategoryType(.sleepAnalysis),
        HKCategoryType(.appleStandHour),
    ]

    /// All sample types eligible for background delivery.
    static var allSampleTypes: Set<HKSampleType> {
        var types = Set<HKSampleType>()
        types.formUnion(quantityTypes)
        types.formUnion(categoryTypes)
        types.insert(HKSeriesType.workoutType())
        return types
    }

    /// All object types requested during authorization (read-only).
    static var allReadTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        types.formUnion(quantityTypes)
        types.formUnion(categoryTypes)
        types.insert(HKSeriesType.workoutType())
        types.insert(HKObjectType.activitySummaryType())
        return types
    }

    /// Sample types this app is allowed to write to (DEBUG test-data generation).
    /// Excludes Apple-managed types (`appleExerciseTime`, `appleStandTime`, `appleStandHour`)
    /// which throw if listed in `toShare:` and the activity-summary type which is read-only.
    static var allWritableTypes: Set<HKSampleType> {
        let appleManagedIDs: Set<String> = [
            HKQuantityTypeIdentifier.appleExerciseTime.rawValue,
            HKQuantityTypeIdentifier.appleStandTime.rawValue,
            HKCategoryTypeIdentifier.appleStandHour.rawValue,
        ]
        var types = Set<HKSampleType>()
        types.formUnion(quantityTypes.filter { !appleManagedIDs.contains($0.identifier) })
        types.formUnion(categoryTypes.filter { !appleManagedIDs.contains($0.identifier) })
        types.insert(HKSeriesType.workoutType())
        return types
    }

    /// Background delivery frequency for observer queries.
    static let backgroundDeliveryFrequency: HKUpdateFrequency = .hourly

    /// Maximum number of samples per anchored query batch, depending on execution context.
    ///
    /// **Background (~30s window):** 500 records per batch (~125 KB). Small enough that
    /// multiple types can each complete at least one batch before time expires.
    ///
    /// **Foreground (no time limit):** 2000 records per batch (~500 KB). Clears backlogs
    /// faster when the user has the app open — fewer round trips, same incremental anchor
    /// safety since each batch is still an independent commit point.
    static func queryBatchSize(for context: SyncContext) -> Int {
        switch context {
        case .foreground: return 2_000
        case .background: return 500
        }
    }
}
