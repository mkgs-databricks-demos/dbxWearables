import Foundation

/// Configuration for the Databricks REST API endpoint.
///
/// URLs are resolved with this precedence:
///   1. `WorkspaceConfig` (UserDefaults) — set at runtime via QR scan or
///      manual entry in `CredentialsConfigView`.
///   2. `DBX_API_BASE_URL` / `DBX_WORKSPACE_HOST` environment variables —
///      injected via the Xcode scheme (dev/staging/prod) and UI test
///      `launchEnvironment`.
///
/// This lets a Databricks demoer scan a different QR to switch workspaces
/// without rebuilding, while keeping the env-var fallback for CI and the
/// stock dev workflow.
enum APIConfiguration {

    /// Base URL of the Databricks App REST API
    /// (e.g. `https://<ws>.databricksapps.com/<app>`). Hosts the ingest and
    /// JWT-exchange endpoints.
    static var baseURL: URL {
        guard let url = configuredBaseURL else {
            fatalError("API base URL is not configured. Scan a workspace QR code in API Credentials, or set DBX_API_BASE_URL.")
        }
        return url
    }

    /// Non-fataling variant for UI surfaces (status rows, gating).
    static var configuredBaseURL: URL? {
        if let url = WorkspaceConfig.storedURL(for: WorkspaceConfig.Key.apiBaseURL) {
            return url
        }
        return envURL(for: "DBX_API_BASE_URL")
    }

    /// Workspace hostname used for the OAuth token endpoint
    /// (e.g. `https://<ws>.cloud.databricks.com`). Distinct from `baseURL`
    /// because Databricks Apps run on `*.databricksapps.com` while the
    /// workspace OIDC endpoint lives on the workspace host.
    static var workspaceHost: URL {
        guard let url = configuredWorkspaceHost else {
            fatalError("Workspace host is not configured. Scan a workspace QR code in API Credentials, or set DBX_WORKSPACE_HOST.")
        }
        return url
    }

    /// Non-fataling variant for UI surfaces (status rows, gating).
    static var configuredWorkspaceHost: URL? {
        if let url = WorkspaceConfig.storedURL(for: WorkspaceConfig.Key.host) {
            return url
        }
        return envURL(for: "DBX_WORKSPACE_HOST")
    }

    /// True when both URLs are resolvable (runtime override or env var).
    static var isFullyConfigured: Bool {
        configuredBaseURL != nil && configuredWorkspaceHost != nil
    }

    /// OAuth 2.0 token endpoint for the Databricks workspace (`POST /oidc/v1/token`).
    static var workspaceTokenEndpoint: URL {
        workspaceHost.appendingPathComponent("oidc/v1/token")
    }

    /// OAuth scope requested for the M2M client_credentials flow.
    static let oauthScope = "all-apis"

    /// Endpoint path for posting HealthKit payloads.
    static let ingestPath = "/api/v1/healthkit/ingest"

    /// Endpoint path for exchanging an Apple ID token for a Databricks JWT.
    static let jwtExchangePath = "/api/v1/auth/apple/exchange"

    /// Fully-qualified ingest URL (`baseURL + ingestPath`).
    static var ingestURL: URL {
        baseURL.appendingPathComponent(ingestPath)
    }

    /// Fully-qualified JWT-exchange URL (`baseURL + jwtExchangePath`).
    static var jwtExchangeURL: URL {
        baseURL.appendingPathComponent(jwtExchangePath)
    }

    /// Request timeout interval in seconds.
    static let timeoutInterval: TimeInterval = 30

    /// Maximum number of retry attempts for failed uploads.
    static let maxRetryAttempts = 3

    // MARK: - Private

    private static func envURL(for name: String) -> URL? {
        guard let value = ProcessInfo.processInfo.environment[name] else { return nil }
        return WorkspaceConfig.validatedURL(from: value)
    }
}
