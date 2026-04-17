import Foundation
import OSLog

/// File-based persistence for sync payloads and statistics.
///
/// Stores:
/// - Cumulative stats (record counts, breakdowns by type)
/// - Last NDJSON payload per record type (for demo verification)
/// - Recent sync events log (last 20, without payloads)
///
/// Thread-safe via actor isolation. Files live in the app's Documents directory
/// under `sync_ledger/`.
actor SyncLedger {

    private let baseDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var stats: SyncStats
    private var recentEvents: [SyncRecord]

    private static let maxRecentEvents = 20

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.baseDirectory = docs.appendingPathComponent("sync_ledger", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        // Load persisted state
        self.stats = Self.loadJSON(SyncStats.self, from: baseDirectory.appendingPathComponent("stats.json"), decoder: dec)
            ?? .empty
        self.recentEvents = Self.loadJSON([SyncRecord].self, from: baseDirectory.appendingPathComponent("recent_events.json"), decoder: dec)
            ?? []
    }

    // MARK: - Public API

    /// Record a successful sync POST.
    func recordSync(
        recordType: String,
        recordCount: Int,
        httpStatusCode: Int,
        ndjsonPayload: String,
        requestHeaders: [String: String]
    ) {
        let record = SyncRecord(
            id: UUID(),
            recordType: recordType,
            timestamp: Date(),
            recordCount: recordCount,
            httpStatusCode: httpStatusCode,
            success: true,
            ndjsonPayload: ndjsonPayload,
            requestHeaders: requestHeaders
        )

        // Update cumulative stats
        stats.totalRecordsSent[recordType, default: 0] += recordCount
        stats.lastSyncTimestamp[recordType] = record.timestamp
        updateBreakdowns(recordType: recordType, ndjsonPayload: ndjsonPayload, recordCount: recordCount)

        // Save last payload for this record type
        let payloadFile = baseDirectory.appendingPathComponent("last_payload_\(recordType).json")
        saveJSON(record, to: payloadFile)

        // Append to recent events (without payload to save space)
        let eventRecord = SyncRecord(
            id: record.id,
            recordType: record.recordType,
            timestamp: record.timestamp,
            recordCount: record.recordCount,
            httpStatusCode: record.httpStatusCode,
            success: record.success,
            ndjsonPayload: nil,
            requestHeaders: record.requestHeaders
        )
        recentEvents.insert(eventRecord, at: 0)
        if recentEvents.count > Self.maxRecentEvents {
            recentEvents = Array(recentEvents.prefix(Self.maxRecentEvents))
        }

        // Persist
        saveJSON(stats, to: baseDirectory.appendingPathComponent("stats.json"))
        saveJSON(recentEvents, to: baseDirectory.appendingPathComponent("recent_events.json"))
    }

    /// Current cumulative stats.
    func getStats() -> SyncStats {
        stats
    }

    /// Recent sync events (most recent first, no payload).
    func getRecentEvents() -> [SyncRecord] {
        recentEvents
    }

    /// Last successful payload for a given record type.
    func getLastPayload(for recordType: String) -> SyncRecord? {
        let file = baseDirectory.appendingPathComponent("last_payload_\(recordType).json")
        return Self.loadJSON(SyncRecord.self, from: file, decoder: decoder)
    }

    // MARK: - Breakdown Parsing

    /// Parse NDJSON lines to extract type fields for per-category breakdowns.
    private func updateBreakdowns(recordType: String, ndjsonPayload: String, recordCount: Int) {
        let lines = ndjsonPayload.split(separator: "\n")

        switch recordType {
        case "samples":
            for line in lines {
                if let type = extractField("type", from: line) {
                    stats.sampleBreakdown[type, default: 0] += 1
                }
            }
        case "workouts":
            for line in lines {
                if let activityType = extractField("activity_type", from: line) {
                    stats.workoutBreakdown[activityType, default: 0] += 1
                }
            }
        case "sleep":
            stats.sleepSessionCount += recordCount
        case "activity_summaries":
            stats.activitySummaryDayCount += recordCount
        case "deletes":
            for line in lines {
                if let sampleType = extractField("sample_type", from: line) {
                    stats.deleteBreakdown[sampleType, default: 0] += 1
                }
            }
        default:
            break
        }
    }

    /// Extract a string field value from a single JSON line.
    private func extractField(_ key: String, from line: Substring) -> String? {
        guard let data = line.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = dict[key] as? String else {
            return nil
        }
        return value
    }

    // MARK: - File I/O

    private func saveJSON<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.sync.error("SyncLedger: failed to write \(url.lastPathComponent) — \(error.localizedDescription)")
        }
    }

    private static func loadJSON<T: Decodable>(_ type: T.Type, from url: URL, decoder: JSONDecoder) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
