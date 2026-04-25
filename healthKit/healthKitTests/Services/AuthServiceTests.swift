import XCTest
@testable import dbxWearablesApp

final class AuthServiceTests: XCTestCase {

    private let tokenEndpoint = URL(string: "https://test.databricks.com/oidc/v1/token")!
    private let clientIDKey = KeychainHelper.Key.databricksClientID
    private let clientSecretKey = KeychainHelper.Key.databricksClientSecret
    private let accessTokenKey = KeychainHelper.Key.oauthAccessToken
    private let expiryKey = KeychainHelper.Key.oauthAccessTokenExpiry

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        // APIConfiguration.workspaceTokenEndpoint will be derived from this if AuthService
        // is constructed without an explicit override; tests pass the endpoint directly.
        setenv("DBX_WORKSPACE_HOST", "https://test.databricks.com", 1)
        setenv("DBX_API_BASE_URL", "https://test.databricks.com/apps/wearables", 1)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)

        seedCredentials(clientID: "test-client", clientSecret: "test-secret")
        clearCachedToken()
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        clearCachedToken()
        KeychainHelper.delete(for: clientIDKey)
        KeychainHelper.delete(for: clientSecretKey)
        super.tearDown()
    }

    // MARK: - Helpers

    private func seedCredentials(clientID: String, clientSecret: String) {
        KeychainHelper.set(clientID, for: clientIDKey)
        KeychainHelper.set(clientSecret, for: clientSecretKey)
    }

    private func clearCachedToken() {
        KeychainHelper.delete(for: accessTokenKey)
        KeychainHelper.delete(for: expiryKey)
    }

    private func makeService(now: Date = Date()) -> AuthService {
        AuthService(session: session, tokenEndpoint: tokenEndpoint, clock: { now })
    }

    private func tokenResponse(_ accessToken: String, expiresIn: Int) -> Data {
        Data(#"{"access_token":"\#(accessToken)","token_type":"Bearer","expires_in":\#(expiresIn),"scope":"all-apis"}"#.utf8)
    }

    // MARK: - Refresh

    func testFetchesTokenFromEndpointOnFirstCall() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, self.tokenResponse("token-1", expiresIn: 3600))
        }

        let service = makeService()
        let token = try await service.bearerToken()

        XCTAssertEqual(token, "token-1")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertTrue(capturedRequest?.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") ?? false)
    }

    func testCachesTokenAcrossCallsWithinExpiry() async throws {
        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, self.tokenResponse("token-cached", expiresIn: 3600))
        }

        let service = makeService()
        _ = try await service.bearerToken()
        _ = try await service.bearerToken()
        _ = try await service.bearerToken()

        XCTAssertEqual(requestCount, 1, "Cached token should be reused for subsequent calls within expiry")
    }

    func testRefreshesWhenTokenIsWithinLeadTimeOfExpiry() async throws {
        // Token expires in 30s — less than the 60s refresh lead time, so should refresh.
        var requestCount = 0
        var responseToken = "token-1"
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, self.tokenResponse(responseToken, expiresIn: 30))
        }

        let now = Date()
        let service = makeService(now: now)
        let first = try await service.bearerToken()
        XCTAssertEqual(first, "token-1")

        responseToken = "token-2"
        let second = try await service.bearerToken()
        XCTAssertEqual(second, "token-2", "Should have refreshed because token was within lead time")
        XCTAssertEqual(requestCount, 2)
    }

    func testInvalidateForcesRefreshOnNextCall() async throws {
        var requestCount = 0
        var responseToken = "token-1"
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, self.tokenResponse(responseToken, expiresIn: 3600))
        }

        let service = makeService()
        _ = try await service.bearerToken()
        await service.invalidateCachedToken()
        responseToken = "token-after-invalidate"
        let token = try await service.bearerToken()

        XCTAssertEqual(token, "token-after-invalidate")
        XCTAssertEqual(requestCount, 2)
    }

    // MARK: - Errors

    func testThrowsWhenCredentialsMissing() async {
        KeychainHelper.delete(for: clientIDKey)
        let service = makeService()

        do {
            _ = try await service.bearerToken()
            XCTFail("Expected missingCredentials error")
        } catch let error as AuthError {
            if case .missingCredentials = error {
                // expected
            } else {
                XCTFail("Expected .missingCredentials, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testThrowsOnNon2xxFromTokenEndpoint() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = makeService()
        do {
            _ = try await service.bearerToken()
            XCTFail("Expected tokenEndpointFailed error")
        } catch let error as AuthError {
            if case .tokenEndpointFailed(let code) = error {
                XCTAssertEqual(code, 401)
            } else {
                XCTFail("Expected .tokenEndpointFailed, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testThrowsOnMalformedTokenResponse() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("not json".utf8))
        }

        let service = makeService()
        do {
            _ = try await service.bearerToken()
            XCTFail("Expected invalidTokenResponse error")
        } catch let error as AuthError {
            if case .invalidTokenResponse = error {
                // expected
            } else {
                XCTFail("Expected .invalidTokenResponse, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
