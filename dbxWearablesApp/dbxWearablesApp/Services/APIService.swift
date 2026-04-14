import Foundation

/// Handles HTTP communication with the Databricks REST API.
final class APIService {

    private let session: URLSession
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Post an array of Encodable records as NDJSON to the Databricks ingestion endpoint.
    ///
    /// Wire format:
    /// - Body: NDJSON — one JSON object per line, each a self-contained record
    /// - Headers carry device/upload metadata that the Databricks App attaches to each
    ///   bronze table row alongside the sample VARIANT
    ///
    /// The `recordType` header tells the Databricks App what kind of records are in
    /// the body (e.g., "samples", "workouts", "sleep", "activity_summaries") so it can
    /// route to the appropriate ZeroBus topic or bronze table.
    func postRecords<T: Encodable>(_ records: [T], recordType: String) async throws -> APIResponse {
        let url = APIConfiguration.baseURL.appendingPathComponent(APIConfiguration.ingestPath)
        let body = try NDJSONSerializer.encode(records)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = APIConfiguration.timeoutInterval

        // Content type: NDJSON (RFC-adjacent; widely supported by streaming ingest APIs)
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Content-Type")

        // Device and upload metadata — the Databricks App reads these headers and
        // attaches them as columns alongside each NDJSON record in the bronze table.
        request.setValue(DeviceIdentifier.current, forHTTPHeaderField: "X-Device-Id")
        request.setValue("apple_healthkit", forHTTPHeaderField: "X-Platform")
        request.setValue(appVersion, forHTTPHeaderField: "X-App-Version")
        request.setValue(DateFormatters.iso8601WithTimezone.string(from: Date()), forHTTPHeaderField: "X-Upload-Timestamp")
        request.setValue(recordType, forHTTPHeaderField: "X-Record-Type")

        if let token = KeychainHelper.retrieveAPIToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw APIError.httpError(statusCode: statusCode)
        }

        return try decoder.decode(APIResponse.self, from: data)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}

enum APIError: Error, LocalizedError {
    /// Server returned an error. Check `isRetryable` to decide whether to retry.
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .httpError(let statusCode):
            return "HTTP request failed with status code \(statusCode)."
        }
    }

    /// Whether this error is worth retrying (server-side or rate-limiting).
    /// 4xx errors (except 429) indicate a client problem — retrying won't help.
    var isRetryable: Bool {
        switch self {
        case .httpError(let statusCode):
            return statusCode == 429 || (500...599).contains(statusCode)
        }
    }
}
