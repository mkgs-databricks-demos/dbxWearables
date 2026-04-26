import XCTest
@testable import dbxWearablesApp

/// Round-trip and validation tests for the runtime workspace store and the
/// `APIConfiguration` precedence rule (UserDefaults override > env var).
final class WorkspaceConfigTests: XCTestCase {

    private let envAPIBase = "https://env.databricksapps.com/wearables"
    private let envHost = "https://env.cloud.databricks.com"

    override func setUp() {
        super.setUp()
        // Establish the env-var fallback so we can verify the override layer
        // wins when UserDefaults is populated.
        setenv("DBX_API_BASE_URL", envAPIBase, 1)
        setenv("DBX_WORKSPACE_HOST", envHost, 1)
        WorkspaceConfig.clear()
    }

    override func tearDown() {
        WorkspaceConfig.clear()
        super.tearDown()
    }

    // MARK: - validatedURL

    func testValidatedURLAcceptsHTTPSWithHost() {
        XCTAssertNotNil(WorkspaceConfig.validatedURL(from: "https://x.databricksapps.com/app"))
    }

    func testValidatedURLAcceptsHTTP() {
        XCTAssertNotNil(WorkspaceConfig.validatedURL(from: "http://localhost:8080/app"))
    }

    func testValidatedURLTrimsWhitespace() {
        XCTAssertNotNil(WorkspaceConfig.validatedURL(from: "  https://x.databricksapps.com/app\n"))
    }

    func testValidatedURLRejectsEmpty() {
        XCTAssertNil(WorkspaceConfig.validatedURL(from: ""))
        XCTAssertNil(WorkspaceConfig.validatedURL(from: "   "))
    }

    func testValidatedURLRejectsMissingScheme() {
        XCTAssertNil(WorkspaceConfig.validatedURL(from: "x.databricksapps.com"))
    }

    func testValidatedURLRejectsNonHTTPScheme() {
        XCTAssertNil(WorkspaceConfig.validatedURL(from: "ftp://x.databricksapps.com"))
        XCTAssertNil(WorkspaceConfig.validatedURL(from: "javascript://x"))
    }

    func testValidatedURLRejectsMissingHost() {
        XCTAssertNil(WorkspaceConfig.validatedURL(from: "https://"))
    }

    // MARK: - Round-trip

    func testSetAndReadRoundTrip() {
        let api = URL(string: "https://demo.databricksapps.com/wearables")!
        let host = URL(string: "https://demo.cloud.databricks.com")!
        WorkspaceConfig.set(apiBaseURL: api, host: host, label: "Demo")

        XCTAssertEqual(WorkspaceConfig.storedURL(for: WorkspaceConfig.Key.apiBaseURL), api)
        XCTAssertEqual(WorkspaceConfig.storedURL(for: WorkspaceConfig.Key.host), host)
        XCTAssertEqual(WorkspaceConfig.label, "Demo")
        XCTAssertTrue(WorkspaceConfig.isFullyConfigured)
    }

    func testEmptyLabelClearsLabel() {
        let api = URL(string: "https://demo.databricksapps.com/wearables")!
        let host = URL(string: "https://demo.cloud.databricks.com")!
        WorkspaceConfig.set(apiBaseURL: api, host: host, label: "Demo")
        WorkspaceConfig.set(apiBaseURL: api, host: host, label: nil)
        XCTAssertNil(WorkspaceConfig.label)
    }

    func testClearRemovesAllKeys() {
        let api = URL(string: "https://demo.databricksapps.com/wearables")!
        let host = URL(string: "https://demo.cloud.databricks.com")!
        WorkspaceConfig.set(apiBaseURL: api, host: host, label: "Demo")
        WorkspaceConfig.clear()

        XCTAssertNil(WorkspaceConfig.storedURL(for: WorkspaceConfig.Key.apiBaseURL))
        XCTAssertNil(WorkspaceConfig.storedURL(for: WorkspaceConfig.Key.host))
        XCTAssertNil(WorkspaceConfig.label)
        XCTAssertFalse(WorkspaceConfig.isFullyConfigured)
    }

    // MARK: - APIConfiguration precedence

    func testAPIConfigurationFallsBackToEnvWhenWorkspaceUnset() {
        XCTAssertEqual(APIConfiguration.configuredBaseURL?.absoluteString, envAPIBase)
        XCTAssertEqual(APIConfiguration.configuredWorkspaceHost?.absoluteString, envHost)
    }

    func testAPIConfigurationPrefersWorkspaceOverEnv() {
        let api = URL(string: "https://override.databricksapps.com/app")!
        let host = URL(string: "https://override.cloud.databricks.com")!
        WorkspaceConfig.set(apiBaseURL: api, host: host, label: nil)

        XCTAssertEqual(APIConfiguration.configuredBaseURL, api)
        XCTAssertEqual(APIConfiguration.configuredWorkspaceHost, host)
    }

    func testAPIConfigurationDerivedURLsUseOverride() {
        let api = URL(string: "https://override.databricksapps.com/app")!
        let host = URL(string: "https://override.cloud.databricks.com")!
        WorkspaceConfig.set(apiBaseURL: api, host: host, label: nil)

        XCTAssertEqual(
            APIConfiguration.ingestURL.absoluteString,
            "https://override.databricksapps.com/app/api/v1/healthkit/ingest"
        )
        XCTAssertEqual(
            APIConfiguration.jwtExchangeURL.absoluteString,
            "https://override.databricksapps.com/app/api/v1/auth/apple/exchange"
        )
        XCTAssertEqual(
            APIConfiguration.workspaceTokenEndpoint.absoluteString,
            "https://override.cloud.databricks.com/oidc/v1/token"
        )
    }

    func testIsFullyConfiguredAcrossLayers() {
        XCTAssertTrue(APIConfiguration.isFullyConfigured, "env vars alone should satisfy")
        let api = URL(string: "https://override.databricksapps.com/app")!
        let host = URL(string: "https://override.cloud.databricks.com")!
        WorkspaceConfig.set(apiBaseURL: api, host: host, label: nil)
        XCTAssertTrue(APIConfiguration.isFullyConfigured)
    }
}
