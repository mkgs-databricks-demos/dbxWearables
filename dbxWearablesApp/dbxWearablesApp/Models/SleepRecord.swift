import Foundation

/// A sleep session with individual stage intervals.
/// The session itself is a grouping concept — individual stages carry their own UUIDs.
struct SleepRecord: Codable {
    let startDate: Date
    let endDate: Date
    let stages: [SleepStage]

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case endDate = "end_date"
        case stages
    }
}

/// A single sleep stage interval within a SleepRecord.
struct SleepStage: Codable {
    /// HealthKit sample UUID of the individual stage sample.
    let uuid: String
    let stage: String
    let startDate: Date
    let endDate: Date

    enum CodingKeys: String, CodingKey {
        case uuid
        case stage
        case startDate = "start_date"
        case endDate = "end_date"
    }
}
