import Foundation

/// Cumulative statistics about all data sent to Databricks.
struct SyncStats: Codable {
    /// recordType → cumulative record count
    var totalRecordsSent: [String: Int]
    /// recordType → timestamp of last successful POST
    var lastSyncTimestamp: [String: Date]
    /// HK type identifier → count (for the "samples" record type)
    var sampleBreakdown: [String: Int]
    /// Workout activity type → count
    var workoutBreakdown: [String: Int]
    /// Total sleep sessions sent
    var sleepSessionCount: Int
    /// Total activity summary days sent
    var activitySummaryDayCount: Int
    /// Deleted sample type → count
    var deleteBreakdown: [String: Int]

    enum CodingKeys: String, CodingKey {
        case totalRecordsSent = "total_records_sent"
        case lastSyncTimestamp = "last_sync_timestamp"
        case sampleBreakdown = "sample_breakdown"
        case workoutBreakdown = "workout_breakdown"
        case sleepSessionCount = "sleep_session_count"
        case activitySummaryDayCount = "activity_summary_day_count"
        case deleteBreakdown = "delete_breakdown"
    }

    static let empty = SyncStats(
        totalRecordsSent: [:],
        lastSyncTimestamp: [:],
        sampleBreakdown: [:],
        workoutBreakdown: [:],
        sleepSessionCount: 0,
        activitySummaryDayCount: 0,
        deleteBreakdown: [:]
    )
}
