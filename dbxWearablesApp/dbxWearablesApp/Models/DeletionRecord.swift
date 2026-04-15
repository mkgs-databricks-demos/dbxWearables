import Foundation

/// A record indicating that a HealthKit sample was deleted by the user.
/// Posted as NDJSON with X-Record-Type: "deletes" so the Databricks silver
/// layer can soft-delete or filter the corresponding bronze row.
struct DeletionRecord: Codable {
    /// UUID of the deleted HealthKit sample — matches the `uuid` field
    /// on the original HealthSample, WorkoutRecord, or SleepStage.
    let uuid: String

    /// HealthKit type identifier of the deleted sample (e.g.,
    /// "HKQuantityTypeIdentifierHeartRate", "HKWorkoutTypeIdentifier").
    let sampleType: String

    enum CodingKeys: String, CodingKey {
        case uuid
        case sampleType = "sample_type"
    }
}
