import Foundation
import HealthKit

/// Maps HKWorkout objects into Codable WorkoutRecord models.
enum WorkoutMapper {

    static func map(_ workout: HKWorkout) -> WorkoutRecord {
        WorkoutRecord(
            uuid: workout.uuid.uuidString,
            activityType: workout.workoutActivityType.name,
            activityTypeRaw: workout.workoutActivityType.rawValue,
            startDate: workout.startDate,
            endDate: workout.endDate,
            durationSeconds: workout.duration,
            totalEnergyBurnedKcal: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
            totalDistanceMeters: workout.totalDistance?.doubleValue(for: .meter()),
            sourceName: workout.sourceRevision.source.name,
            metadata: stringMetadata(from: workout.metadata)
        )
    }

    /// Convert a batch of HKSample results into WorkoutRecord models,
    /// filtering to only HKWorkout instances.
    static func mapWorkouts(_ samples: [HKSample]) -> [WorkoutRecord] {
        samples.compactMap { $0 as? HKWorkout }.map(map)
    }

    private static func stringMetadata(from metadata: [String: Any]?) -> [String: String]? {
        guard let metadata, !metadata.isEmpty else { return nil }
        var result: [String: String] = [:]
        for (key, value) in metadata {
            switch value {
            case let string as String:  result[key] = string
            case let number as NSNumber: result[key] = number.stringValue
            case let date as Date:       result[key] = DateFormatters.iso8601WithTimezone.string(from: date)
            default:                     result[key] = String(describing: value)
            }
        }
        return result.isEmpty ? nil : result
    }
}

// MARK: - HKWorkoutActivityType readable names

extension HKWorkoutActivityType {

    /// Human-readable name for the activity type, used in JSON payloads.
    var name: String {
        switch self {
        case .americanFootball:        return "american_football"
        case .archery:                 return "archery"
        case .australianFootball:      return "australian_football"
        case .badminton:               return "badminton"
        case .baseball:                return "baseball"
        case .basketball:              return "basketball"
        case .bowling:                 return "bowling"
        case .boxing:                  return "boxing"
        case .climbing:                return "climbing"
        case .cricket:                 return "cricket"
        case .crossTraining:           return "cross_training"
        case .curling:                 return "curling"
        case .cycling:                 return "cycling"
        case .dance:                   return "dance"
        case .elliptical:              return "elliptical"
        case .equestrianSports:        return "equestrian_sports"
        case .fencing:                 return "fencing"
        case .fishing:                 return "fishing"
        case .functionalStrengthTraining: return "functional_strength_training"
        case .golf:                    return "golf"
        case .gymnastics:              return "gymnastics"
        case .handball:                return "handball"
        case .hiking:                  return "hiking"
        case .hockey:                  return "hockey"
        case .hunting:                 return "hunting"
        case .lacrosse:                return "lacrosse"
        case .martialArts:             return "martial_arts"
        case .mindAndBody:             return "mind_and_body"
        case .paddleSports:            return "paddle_sports"
        case .play:                    return "play"
        case .preparationAndRecovery:  return "preparation_and_recovery"
        case .racquetball:             return "racquetball"
        case .rowing:                  return "rowing"
        case .rugby:                   return "rugby"
        case .running:                 return "running"
        case .sailing:                 return "sailing"
        case .skatingSports:           return "skating_sports"
        case .snowSports:              return "snow_sports"
        case .soccer:                  return "soccer"
        case .softball:                return "softball"
        case .squash:                  return "squash"
        case .stairClimbing:           return "stair_climbing"
        case .surfingSports:           return "surfing_sports"
        case .swimming:                return "swimming"
        case .tableTennis:             return "table_tennis"
        case .tennis:                  return "tennis"
        case .trackAndField:           return "track_and_field"
        case .traditionalStrengthTraining: return "traditional_strength_training"
        case .volleyball:              return "volleyball"
        case .walking:                 return "walking"
        case .waterFitness:            return "water_fitness"
        case .waterPolo:               return "water_polo"
        case .waterSports:             return "water_sports"
        case .wrestling:               return "wrestling"
        case .yoga:                    return "yoga"
        case .barre:                   return "barre"
        case .coreTraining:            return "core_training"
        case .crossCountrySkiing:      return "cross_country_skiing"
        case .downhillSkiing:          return "downhill_skiing"
        case .flexibility:             return "flexibility"
        case .highIntensityIntervalTraining: return "hiit"
        case .jumpRope:                return "jump_rope"
        case .kickboxing:              return "kickboxing"
        case .pilates:                 return "pilates"
        case .snowboarding:            return "snowboarding"
        case .stairs:                  return "stairs"
        case .stepTraining:            return "step_training"
        case .wheelchairWalkPace:      return "wheelchair_walk_pace"
        case .wheelchairRunPace:       return "wheelchair_run_pace"
        case .taiChi:                  return "tai_chi"
        case .mixedCardio:             return "mixed_cardio"
        case .handCycling:             return "hand_cycling"
        case .fitnessGaming:           return "fitness_gaming"
        case .cooldown:                return "cooldown"
        case .pickleball:              return "pickleball"
        case .swimBikeRun:             return "swim_bike_run"
        case .transition:              return "transition"
        case .underwaterDiving:        return "underwater_diving"
        case .other:                   return "other"
        @unknown default:              return "unknown_\(rawValue)"
        }
    }
}
