import Foundation

/// Shared date formatters for API payloads and display.
enum DateFormatters {

    /// ISO 8601 formatter with timezone offset, used for all API communication.
    static let iso8601WithTimezone: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Date-only formatter (yyyy-MM-dd) for activity summary dates.
    static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
