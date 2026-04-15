import Foundation

/// A workout session, mapped from HKWorkout.
struct WorkoutRecord: Codable {
    /// HealthKit sample UUID — stable identifier used for deduplication and delete matching.
    let uuid: String
    let activityType: String
    let activityTypeRaw: UInt
    let startDate: Date
    let endDate: Date
    let durationSeconds: Double
    let totalEnergyBurnedKcal: Double?
    let totalDistanceMeters: Double?
    let sourceName: String
    let metadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case uuid
        case activityType = "activity_type"
        case activityTypeRaw = "activity_type_raw"
        case startDate = "start_date"
        case endDate = "end_date"
        case durationSeconds = "duration_seconds"
        case totalEnergyBurnedKcal = "total_energy_burned_kcal"
        case totalDistanceMeters = "total_distance_meters"
        case sourceName = "source_name"
        case metadata
    }
}
