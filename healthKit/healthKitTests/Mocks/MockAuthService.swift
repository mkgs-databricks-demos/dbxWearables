import Foundation
@testable import dbxWearablesApp

/// Test double for `AuthProviding` that returns a configurable token and records
/// the number of `bearerToken()` and `invalidateCachedToken()` calls.
actor MockAuthService: AuthProviding {

    var tokenResult: Result<String, Error>
    private(set) var bearerCallCount = 0
    private(set) var invalidateCallCount = 0

    init(token: String = "mock-token") {
        self.tokenResult = .success(token)
    }

    func bearerToken() async throws -> String {
        bearerCallCount += 1
        return try tokenResult.get()
    }

    func invalidateCachedToken() async {
        invalidateCallCount += 1
    }

    /// Configure the next `bearerToken()` call to throw.
    func setError(_ error: Error) {
        tokenResult = .failure(error)
    }

    /// Configure the next `bearerToken()` call to return the given token.
    func setToken(_ token: String) {
        tokenResult = .success(token)
    }
}
