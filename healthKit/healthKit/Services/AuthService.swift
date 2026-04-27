import Foundation

/// Errors thrown by AuthService.
enum AuthError: Error, LocalizedError {
    /// The Databricks SPN client ID/secret is missing from the Keychain.
    case missingCredentials
    /// The OAuth token endpoint returned a non-2xx response.
    case tokenEndpointFailed(statusCode: Int)
    /// The OAuth token endpoint response body could not be decoded.
    case invalidTokenResponse

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Databricks service-principal credentials are not configured."
        case .tokenEndpointFailed(let code):
            return "OAuth token endpoint returned HTTP \(code)."
        case .invalidTokenResponse:
            return "OAuth token endpoint response was malformed."
        }
    }
}

/// Provides bearer tokens for authenticated requests against the Databricks REST API.
/// Abstracted as a protocol so APIService can be tested with a mock.
protocol AuthProviding: Sendable {
    /// Returns a valid bearer token, refreshing if cached one is expired or missing.
    func bearerToken() async throws -> String
    /// Discards any cached token so the next `bearerToken()` call will force a refresh.
    /// Used when the API returns 401 to handle server-side revocation.
    func invalidateCachedToken() async
}

/// Manages the OAuth client_credentials lifecycle for the Databricks service principal.
///
/// Caches the access token both in memory (process-scoped) and the Keychain (persisted
/// across launches). Refreshes ~60s before expiry to avoid using a token that expires
/// in flight, and exposes `invalidateCachedToken()` so callers can force a refresh
/// after a 401.
actor AuthService: AuthProviding {

    private let session: URLSession
    private let tokenEndpoint: URL
    private let scope: String
    private let clock: @Sendable () -> Date
    private let refreshLeadTime: TimeInterval = 60

    private var cachedToken: String?
    private var cachedExpiry: Date?

    init(
        session: URLSession = .shared,
        tokenEndpoint: URL? = nil,
        scope: String = APIConfiguration.oauthScope,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.session = session
        self.tokenEndpoint = tokenEndpoint ?? APIConfiguration.workspaceTokenEndpoint
        self.scope = scope
        self.clock = clock

        if let token = KeychainHelper.get(for: KeychainHelper.Key.oauthAccessToken),
           let expiryString = KeychainHelper.get(for: KeychainHelper.Key.oauthAccessTokenExpiry),
           let expiry = DateFormatters.iso8601WithTimezone.date(from: expiryString) {
            self.cachedToken = token
            self.cachedExpiry = expiry
        }
    }

    func bearerToken() async throws -> String {
        if let token = cachedToken,
           let expiry = cachedExpiry,
           expiry.timeIntervalSince(clock()) > refreshLeadTime {
            return token
        }
        return try await refresh()
    }

    func invalidateCachedToken() {
        cachedToken = nil
        cachedExpiry = nil
        KeychainHelper.delete(for: KeychainHelper.Key.oauthAccessToken)
        KeychainHelper.delete(for: KeychainHelper.Key.oauthAccessTokenExpiry)
    }

    private func refresh() async throws -> String {
        guard let clientID = KeychainHelper.get(for: KeychainHelper.Key.databricksClientID),
              !clientID.isEmpty,
              let clientSecret = KeychainHelper.get(for: KeychainHelper.Key.databricksClientSecret),
              !clientSecret.isEmpty else {
            throw AuthError.missingCredentials
        }

        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let basic = Data("\(clientID):\(clientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        request.httpBody = "grant_type=client_credentials&scope=\(scope)".data(using: .utf8)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AuthError.tokenEndpointFailed(statusCode: code)
        }

        struct TokenResponse: Decodable {
            let accessToken: String
            let expiresIn: Int

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case expiresIn = "expires_in"
            }
        }

        guard let parsed = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw AuthError.invalidTokenResponse
        }

        let expiresAt = clock().addingTimeInterval(TimeInterval(parsed.expiresIn))
        cachedToken = parsed.accessToken
        cachedExpiry = expiresAt

        KeychainHelper.set(parsed.accessToken, for: KeychainHelper.Key.oauthAccessToken)
        KeychainHelper.set(
            DateFormatters.iso8601WithTimezone.string(from: expiresAt),
            for: KeychainHelper.Key.oauthAccessTokenExpiry
        )

        return parsed.accessToken
    }
}
