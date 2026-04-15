import Foundation

/// Response returned by the Databricks REST API after ingesting a payload.
struct APIResponse: Codable {
    let status: String
    let message: String?
    let recordId: String?

    enum CodingKeys: String, CodingKey {
        case status
        case message
        case recordId = "record_id"
    }
}
