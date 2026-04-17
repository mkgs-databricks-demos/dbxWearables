import HealthKit

extension HKQuantityType {

    /// Returns the canonical HKUnit for a given quantity type, used when extracting doubleValue from samples.
    var canonicalUnit: HKUnit {
        switch self.identifier {
        case HKQuantityTypeIdentifier.stepCount.rawValue:
            return .count()
        case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue:
            return .meter()
        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
             HKQuantityTypeIdentifier.basalEnergyBurned.rawValue:
            return .kilocalorie()
        case HKQuantityTypeIdentifier.heartRate.rawValue,
             HKQuantityTypeIdentifier.restingHeartRate.rawValue:
            return HKUnit.count().unitDivided(by: .minute())
        case HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue:
            return .secondUnit(with: .milli)
        case HKQuantityTypeIdentifier.oxygenSaturation.rawValue:
            return .percent()
        case HKQuantityTypeIdentifier.appleExerciseTime.rawValue,
             HKQuantityTypeIdentifier.appleStandTime.rawValue:
            return .minute()
        case HKQuantityTypeIdentifier.vo2Max.rawValue:
            return HKUnit(from: "ml/kg*min")
        default:
            return .count()
        }
    }

    /// Unit string for JSON payloads (matches HealthKit unit conventions).
    var unitString: String {
        canonicalUnit.unitString
    }
}
