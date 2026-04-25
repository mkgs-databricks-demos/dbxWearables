import Foundation

/// Configuration for the Databricks REST API endpoint.
/// Base URL and paths are loaded from environment or runtime config — never hardcoded secrets.
enum APIConfiguration {
    /// Base URL of the Databricks App REST API (e.g., "https://<workspace>.databricks.com/apps/<app-name>").
    /// Set via scheme environment variable or Settings bundle at runtime.
    static var baseURL: URL {
        guard let urlString = ProcessInfo.processInfo.environment["DBX_API_BASE_URL"],
              let url = URL(string: urlString) else {
            fatalError("DBX_API_BASE_URL environment variable is not set or is invalid.")
        }
        return url
    }

    /// Workspace hostname used for the OAuth token endpoint (e.g., "https://<workspace>.cloud.databricks.com").
    /// This is distinct from `baseURL` because Databricks Apps run on `*.databricksapps.com` while the
    /// workspace OIDC endpoint lives on the workspace host.
    static var workspaceHost: URL {
        guard let urlString = ProcessInfo.processInfo.environment["DBX_WORKSPACE_HOST"],
              let url = URL(string: urlString) else {
            fatalError("DBX_WORKSPACE_HOST environment variable is not set or is invalid.")
        }
        return url
    }

    /// OAuth 2.0 token endpoint for the Databricks workspace (`POST /oidc/v1/token`).
    static var workspaceTokenEndpoint: URL {
        workspaceHost.appendingPathComponent("oidc/v1/token")
    }

    /// OAuth scope requested for the M2M client_credentials flow.
    static let oauthScope = "all-apis"

    /// Endpoint path for posting HealthKit payloads.
    static let ingestPath = "/api/v1/healthkit/ingest"

    /// Request timeout interval in seconds.
    static let timeoutInterval: TimeInterval = 30

    /// Maximum number of retry attempts for failed uploads.
    static let maxRetryAttempts = 3
}
