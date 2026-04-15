import Foundation

/// A record of a single sync POST to the Databricks endpoint.
struct SyncRecord: Codable, Identifiable {
    let id: UUID
    let recordType: String
    let timestamp: Date
    let recordCount: Int
    let httpStatusCode: Int
    let success: Bool
    /// Raw NDJSON string. Only populated for last-payload storage; nil in recent events log.
    let ndjsonPayload: String?
    let requestHeaders: [String: String]

    enum CodingKeys: String, CodingKey {
        case id
        case recordType = "record_type"
        case timestamp
        case recordCount = "record_count"
        case httpStatusCode = "http_status_code"
        case success
        case ndjsonPayload = "ndjson_payload"
        case requestHeaders = "request_headers"
    }
}
