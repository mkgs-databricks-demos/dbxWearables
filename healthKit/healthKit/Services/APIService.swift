import Foundation

/// Handles HTTP communication with the Databricks REST API.
final class APIService {

    private let session: URLSession
    private let auth: AuthProviding
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(session: URLSession = .shared, auth: AuthProviding = AuthService()) {
        self.session = session
        self.auth = auth
    }

    /// Build the metadata headers sent with every POST request.
    /// Exposed so callers (e.g., SyncCoordinator) can capture headers for the SyncLedger.
    ///
    /// `async throws` because the bearer token may need to be fetched/refreshed via
    /// the OAuth token endpoint.
    func buildRequestHeaders(for recordType: String) async throws -> [String: String] {
        let token = try await auth.bearerToken()
        return [
            "Content-Type": "application/x-ndjson",
            "X-Device-Id": DeviceIdentifier.current,
            "X-Platform": "apple_healthkit",
            "X-App-Version": appVersion,
            "X-Upload-Timestamp": DateFormatters.iso8601WithTimezone.string(from: Date()),
            "X-Record-Type": recordType,
            "Authorization": "Bearer \(token)",
        ]
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
    ///
    /// On HTTP 401, the cached token is invalidated and the request is retried once
    /// with a freshly minted bearer token. This handles server-side token revocation.
    func postRecords<T: Encodable>(_ records: [T], recordType: String) async throws -> APIResponse {
        let url = APIConfiguration.baseURL.appendingPathComponent(APIConfiguration.ingestPath)
        let body = try NDJSONSerializer.encode(records)

        do {
            return try await sendRequest(url: url, body: body, recordType: recordType)
        } catch APIError.httpError(let statusCode) where statusCode == 401 {
            await auth.invalidateCachedToken()
            return try await sendRequest(url: url, body: body, recordType: recordType)
        }
    }

    private func sendRequest(url: URL, body: Data, recordType: String) async throws -> APIResponse {
        let headers = try await buildRequestHeaders(for: recordType)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = APIConfiguration.timeoutInterval

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
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
