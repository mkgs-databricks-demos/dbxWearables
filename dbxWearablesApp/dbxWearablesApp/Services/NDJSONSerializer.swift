import Foundation

/// Serializes arrays of Codable objects to Newline-Delimited JSON (NDJSON).
///
/// NDJSON format: one JSON object per line, separated by `\n`.
/// Each line is a complete, self-contained JSON record.
///
/// This is the preferred format for posting quantity samples to the Databricks
/// REST API because:
/// - Heart rate and other high-frequency types produce many samples per sync
/// - One line = one record the server can forward to ZeroBus individually
/// - Memory-efficient: no need to hold a complete array in memory on either end
/// - Partial failure is recoverable: malformed lines don't affect other records
enum NDJSONSerializer {

    /// Encode an array of Codable values as NDJSON data.
    /// Each element becomes one line of JSON followed by a newline character.
    static func encode<T: Encodable>(_ values: [T], encoder: JSONEncoder? = nil) throws -> Data {
        let enc = encoder ?? defaultEncoder
        var lines = Data()

        for value in values {
            let lineData = try enc.encode(value)
            lines.append(lineData)
            lines.append(newline)
        }

        return lines
    }

    /// Encode an array of Codable values as a UTF-8 NDJSON string.
    static func encodeToString<T: Encodable>(_ values: [T], encoder: JSONEncoder? = nil) throws -> String {
        let data = try encode(values, encoder: encoder)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static let newline = Data("\n".utf8)

    private static let defaultEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
