import XCTest
@testable import dbxWearablesApp

/// Unit tests for `AppleSignInManager`.
///
/// We can't construct a real `ASAuthorizationAppleIDCredential` from a test, so
/// we drive the testable JWT-exchange code path (`performExchange`) directly
/// and cover the persistence/restore lifecycle by manipulating Keychain +
/// UserDefaults the way a successful exchange would.
@MainActor
final class AppleSignInManagerTests: XCTestCase {

    private var session: URLSession!
    private var mockAuth: MockAuthService!
    private let userKey = AppleSignInManager.authenticatedUserKey

    override func setUp() {
        super.setUp()

        // APIConfiguration.jwtExchangeURL is derived from DBX_API_BASE_URL when
        // no UserDefaults override is set. Clearing WorkspaceConfig keeps the
        // env-var fallback in charge regardless of which other tests ran first.
        setenv("DBX_API_BASE_URL", "https://test.databricks.com/apps/wearables", 1)
        setenv("DBX_WORKSPACE_HOST", "https://test.databricks.com", 1)
        WorkspaceConfig.clear()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        mockAuth = MockAuthService(token: "spn-token-xyz")

        clearAuthState()
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        clearAuthState()
        session = nil
        mockAuth = nil
        super.tearDown()
    }

    private func clearAuthState() {
        KeychainHelper.delete(for: KeychainHelper.Key.userJWT)
        KeychainHelper.delete(for: KeychainHelper.Key.userJWTExpiry)
        UserDefaults.standard.removeObject(forKey: userKey)
    }

    private func makeManager() -> AppleSignInManager {
        AppleSignInManager(authService: mockAuth, urlSession: session)
    }

    private func encodeExchangeResponse(jwt: String, expiresIn: Int, userId: String) -> Data {
        let response = JWTExchangeResponse(jwt: jwt, expiresIn: expiresIn, userId: userId)
        return try! JSONEncoder().encode(response)
    }

    // MARK: - performExchange

    func testPerformExchangeReturnsServerJWTAndExpiresIn() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let body = self.encodeExchangeResponse(jwt: "ws-jwt-1", expiresIn: 7200, userId: "u-1")
            return (response, body)
        }

        let manager = makeManager()
        let result = try await manager.performExchange(
            identityToken: "apple-id-token",
            userId: "u-1",
            rawNonce: "nonce-raw"
        )

        XCTAssertEqual(result.jwt, "ws-jwt-1")
        XCTAssertEqual(result.expiresIn, 7200)
    }

    func testPerformExchangeIncludesRawNonceAndAuthHeader() async throws {
        var capturedRequest: URLRequest?
        var capturedBody: Data?

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            capturedBody = APIServiceTests.readBody(from: request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let body = self.encodeExchangeResponse(jwt: "ws-jwt", expiresIn: 3600, userId: "u-1")
            return (response, body)
        }

        let manager = makeManager()
        _ = try await manager.performExchange(
            identityToken: "apple-id-token",
            userId: "u-99",
            rawNonce: "raw-nonce-abc"
        )

        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer spn-token-xyz")
        XCTAssertEqual(capturedRequest?.url?.path, "/apps/wearables/api/v1/auth/apple/exchange")

        let decoded = try JSONDecoder().decode(JWTExchangeRequest.self, from: capturedBody ?? Data())
        XCTAssertEqual(decoded.appleIdToken, "apple-id-token")
        XCTAssertEqual(decoded.nonce, "raw-nonce-abc")
        XCTAssertEqual(decoded.userId, "u-99")
        XCTAssertFalse(decoded.deviceId.isEmpty, "deviceId should be populated from DeviceIdentifier")
    }

    func testPerformExchangeThrowsOnNon2xx() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let manager = makeManager()
        do {
            _ = try await manager.performExchange(
                identityToken: "tok",
                userId: "u",
                rawNonce: "n"
            )
            XCTFail("Expected jwtExchangeFailed")
        } catch let error as AppleAuthError {
            guard case .jwtExchangeFailed(let statusCode) = error else {
                return XCTFail("Wrong AppleAuthError: \(error)")
            }
            XCTAssertEqual(statusCode, 503)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPerformExchangeThrowsOnMalformedResponse() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("not json".utf8))
        }

        let manager = makeManager()
        do {
            _ = try await manager.performExchange(
                identityToken: "tok",
                userId: "u",
                rawNonce: "n"
            )
            XCTFail("Expected invalidExchangeResponse")
        } catch let error as AppleAuthError {
            if case .invalidExchangeResponse = error {
                // expected
            } else {
                XCTFail("Wrong AppleAuthError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - signOut

    func testSignOutClearsKeychainAndUserDefaults() {
        // Seed as if a prior exchange had succeeded.
        KeychainHelper.set("stale-jwt", for: KeychainHelper.Key.userJWT)
        KeychainHelper.set("2099-01-01T00:00:00Z", for: KeychainHelper.Key.userJWTExpiry)
        UserDefaults.standard.set(Data("{}".utf8), forKey: userKey)

        let manager = makeManager()
        manager.signOut()

        XCTAssertNil(KeychainHelper.get(for: KeychainHelper.Key.userJWT))
        XCTAssertNil(KeychainHelper.get(for: KeychainHelper.Key.userJWTExpiry))
        XCTAssertNil(UserDefaults.standard.data(forKey: userKey))
        XCTAssertNil(manager.currentUser)
        if case .unauthenticated = manager.authState {
            // expected
        } else {
            XCTFail("Expected .unauthenticated after signOut, got \(manager.authState)")
        }
    }

    // MARK: - restoreSession

    func testRestoreSessionWithExpiredJWTSignsOut() {
        let expired = AppleSignInManager.AuthenticatedUser(
            userId: "u-1",
            email: nil,
            fullName: nil,
            authenticatedAt: Date(timeIntervalSinceNow: -7200),
            jwtExpiresAt: Date(timeIntervalSinceNow: -3600)
        )
        let encoded = try! JSONEncoder().encode(expired)
        UserDefaults.standard.set(encoded, forKey: userKey)
        KeychainHelper.set("expired-jwt", for: KeychainHelper.Key.userJWT)

        let manager = makeManager()

        XCTAssertNil(manager.currentUser, "Expired session should be cleared during init")
        XCTAssertNil(KeychainHelper.get(for: KeychainHelper.Key.userJWT))
        XCTAssertNil(UserDefaults.standard.data(forKey: userKey))
        if case .unauthenticated = manager.authState {
            // expected
        } else {
            XCTFail("Expected .unauthenticated after expired restore, got \(manager.authState)")
        }
    }

    func testRestoreSessionWithValidJWTRehydrates() {
        let valid = AppleSignInManager.AuthenticatedUser(
            userId: "u-1",
            email: "u@example.com",
            fullName: nil,
            authenticatedAt: Date(),
            jwtExpiresAt: Date(timeIntervalSinceNow: 3600)
        )
        let encoded = try! JSONEncoder().encode(valid)
        UserDefaults.standard.set(encoded, forKey: userKey)
        KeychainHelper.set("valid-jwt", for: KeychainHelper.Key.userJWT)

        let manager = makeManager()

        XCTAssertEqual(manager.currentUser?.userId, "u-1")
        if case .authenticated = manager.authState {
            // expected
        } else {
            XCTFail("Expected .authenticated after valid restore, got \(manager.authState)")
        }
    }

    // MARK: - resetForRetry

    func testResetForRetryReturnsToUnauthenticated() {
        let manager = makeManager()
        // Drive into an error state via completeSignIn(.failure(...)).
        let failure = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "boom"])

        let exp = expectation(description: "completeSignIn finished")
        Task {
            await manager.completeSignIn(result: .failure(failure))
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        if case .error = manager.authState {
            // expected
        } else {
            XCTFail("Expected .error before reset, got \(manager.authState)")
        }

        manager.resetForRetry()

        if case .unauthenticated = manager.authState {
            // expected
        } else {
            XCTFail("Expected .unauthenticated after resetForRetry, got \(manager.authState)")
        }
    }

    // MARK: - Nonce helper

    func testGenerateNonceProducesRequestedLengthFromAllowedCharset() {
        let allowed = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = AppleSignInManager.generateNonce(length: 32)

        XCTAssertEqual(nonce.count, 32)
        for ch in nonce {
            XCTAssertTrue(allowed.contains(ch), "Nonce contains disallowed character: \(ch)")
        }
    }

    func testGenerateNonceIsUnpredictable() {
        let a = AppleSignInManager.generateNonce()
        let b = AppleSignInManager.generateNonce()
        XCTAssertNotEqual(a, b, "Two nonces in a row should not collide")
    }
}
