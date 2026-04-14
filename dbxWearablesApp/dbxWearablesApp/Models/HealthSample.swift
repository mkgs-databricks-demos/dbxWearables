import Foundation

/// A single health measurement sample, mapped from HKQuantitySample or HKCategorySample.
struct HealthSample: Codable {
    /// HealthKit sample UUID — stable identifier used for deduplication and delete matching.
    let uuid: String
    let type: String
    let value: Double
    let unit: String
    let startDate: Date
    let endDate: Date
    let sourceName: String
    let sourceBundleId: String?
    let metadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case uuid
        case type
        case value
        case unit
        case startDate = "start_date"
        case endDate = "end_date"
        case sourceName = "source_name"
        case sourceBundleId = "source_bundle_id"
        case metadata
    }
}
