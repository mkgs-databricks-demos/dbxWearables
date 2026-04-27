import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

/// Manages Sign in with Apple authentication flow for Databricks JWT authentication.
///
/// Flow:
/// 1. View hosts a native `SignInWithAppleButton`. On tap, the system invokes
///    `prepareRequest(_:)` which sets scopes and a SHA256-hashed nonce on the
///    request. The raw nonce is retained so it can be sent with the exchange.
/// 2. On completion, the view calls `completeSignIn(result:)`. We extract the
///    Apple ID token, then POST it (with the raw nonce) to the Databricks
///    JWT-exchange endpoint, authenticated with the SPN bearer token.
/// 3. The response carries the workspace JWT and an `expires_in` value (in
///    seconds). We persist the JWT in Keychain and the user record in
///    UserDefaults with the server-provided expiry.
@MainActor
final class AppleSignInManager: ObservableObject {

    @Published var authState: AuthState = .unauthenticated
    @Published var currentUser: AuthenticatedUser?

    enum AuthState {
        case unauthenticated
        case signingIn
        case authenticated
        case error(String)

        var isAuthenticated: Bool {
            if case .authenticated = self {
                return true
            }
            return false
        }
    }

    struct AuthenticatedUser: Codable {
        let userId: String
        let email: String?
        let fullName: PersonNameComponents?
        let authenticatedAt: Date
        let jwtExpiresAt: Date

        var isJWTExpired: Bool {
            Date() > jwtExpiresAt
        }
    }

    private let authService: AuthProviding
    private let urlSession: URLSession

    /// Raw nonce generated for the in-flight Sign in with Apple request.
    /// Retained between `prepareRequest` and `completeSignIn` so the server
    /// can verify the SHA256 claim Apple embedded in the ID token.
    private var pendingNonce: String?

    /// Block-based notification observer tokens. Block observers must be
    /// removed by token, not by `removeObserver(self)` — that call only
    /// matches selector-based registrations.
    private var notificationObservers: [NSObjectProtocol] = []

    init(
        authService: AuthProviding = AuthService(),
        urlSession: URLSession = .shared
    ) {
        self.authService = authService
        self.urlSession = urlSession

        restoreSession()
        observeCredentialRevocation()
        observeForegroundForCredentialCheck()
    }

    deinit {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func observeCredentialRevocation() {
        let token = NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.signOut()
            }
        }
        notificationObservers.append(token)
    }

    /// Re-check Apple ID credential state every time the app returns to the
    /// foreground. Catches revocations that happened on another device or
    /// while the app was backgrounded (no `credentialRevokedNotification`
    /// fires across cold starts).
    private func observeForegroundForCredentialCheck() {
        let token = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.checkCredentialState()
            }
        }
        notificationObservers.append(token)
    }

    // MARK: - Sign In (called by SignInWithAppleButton)

    /// Configure the Apple authorization request just before presentation.
    ///
    /// Generates a raw nonce, stores it on `pendingNonce`, and sets the SHA256
    /// hash on the request so Apple's ID token will include the same hash
    /// claim — letting the server verify origin without the raw nonce ever
    /// touching Apple.
    func prepareRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.generateNonce()
        pendingNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
        authState = .signingIn
    }

    /// Handle the result of the native Sign in with Apple flow.
    func completeSignIn(result: Result<ASAuthorization, Error>) async {
        defer { pendingNonce = nil }

        switch result {
        case .failure(let error):
            authState = .error(error.localizedDescription)
            return
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                authState = .error(AppleAuthError.invalidCredentialType.localizedDescription)
                return
            }
            guard let identityToken = credential.identityToken,
                  let tokenString = String(data: identityToken, encoding: .utf8) else {
                authState = .error(AppleAuthError.invalidAppleToken.localizedDescription)
                return
            }
            guard let rawNonce = pendingNonce else {
                authState = .error(AppleAuthError.missingNonce.localizedDescription)
                return
            }

            do {
                let exchange = try await performExchange(
                    identityToken: tokenString,
                    userId: credential.user,
                    rawNonce: rawNonce
                )
                try storeAuthentication(
                    jwt: exchange.jwt,
                    expiresIn: exchange.expiresIn,
                    userId: credential.user,
                    email: credential.email,
                    fullName: credential.fullName
                )
                authState = .authenticated
            } catch {
                authState = .error(error.localizedDescription)
            }
        }
    }

    /// Reset to `.unauthenticated` so the view re-renders the button.
    /// Used by "Try Again" after an error.
    func resetForRetry() {
        pendingNonce = nil
        authState = .unauthenticated
    }

    // MARK: - JWT Exchange (testable)

    /// Exchange an Apple ID token (plus raw nonce) for a Databricks workspace JWT.
    /// Returns the JWT string and the server-reported lifetime in seconds.
    func performExchange(
        identityToken: String,
        userId: String,
        rawNonce: String
    ) async throws -> (jwt: String, expiresIn: Int) {
        let url = APIConfiguration.jwtExchangeURL

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let spnToken = try await authService.bearerToken()
        request.setValue("Bearer \(spnToken)", forHTTPHeaderField: "Authorization")

        let body = JWTExchangeRequest(
            appleIdToken: identityToken,
            nonce: rawNonce,
            userId: userId,
            deviceId: DeviceIdentifier.current
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AppleAuthError.jwtExchangeFailed(statusCode: statusCode)
        }

        let decoded: JWTExchangeResponse
        do {
            decoded = try JSONDecoder().decode(JWTExchangeResponse.self, from: data)
        } catch {
            throw AppleAuthError.invalidExchangeResponse
        }

        return (decoded.jwt, decoded.expiresIn)
    }

    /// Persist JWT + user record using the server-provided expiry.
    private func storeAuthentication(
        jwt: String,
        expiresIn: Int,
        userId: String,
        email: String?,
        fullName: PersonNameComponents?
    ) throws {
        KeychainHelper.set(jwt, for: KeychainHelper.Key.userJWT)

        let expiryDate = Date().addingTimeInterval(TimeInterval(expiresIn))
        let expiryString = ISO8601DateFormatter().string(from: expiryDate)
        KeychainHelper.set(expiryString, for: KeychainHelper.Key.userJWTExpiry)

        // Apple only provides email and fullName on the FIRST sign-in.
        // On subsequent sign-ins, they may be nil. Preserve existing values.
        let existingUser = currentUser
        
        let user = AuthenticatedUser(
            userId: userId,
            email: email ?? existingUser?.email,
            fullName: fullName ?? existingUser?.fullName,
            authenticatedAt: Date(),
            jwtExpiresAt: expiryDate
        )

        if let encoded = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(encoded, forKey: Self.authenticatedUserKey)
        }

        currentUser = user
    }

    // MARK: - Sign Out

    func signOut() {
        KeychainHelper.delete(for: KeychainHelper.Key.userJWT)
        KeychainHelper.delete(for: KeychainHelper.Key.userJWTExpiry)
        UserDefaults.standard.removeObject(forKey: Self.authenticatedUserKey)

        currentUser = nil
        authState = .unauthenticated
    }

    // MARK: - Session Management

    private func restoreSession() {
        guard let data = UserDefaults.standard.data(forKey: Self.authenticatedUserKey),
              let user = try? JSONDecoder().decode(AuthenticatedUser.self, from: data),
              KeychainHelper.exists(for: KeychainHelper.Key.userJWT) else {
            return
        }

        if user.isJWTExpired {
            signOut()
            return
        }

        currentUser = user
        authState = .authenticated
    }

    func refreshJWTIfNeeded() async throws {
        guard let user = currentUser, user.isJWTExpired else {
            return
        }
        signOut()
        throw AppleAuthError.jwtExpired
    }
    
    /// Check if the user's Apple ID credential is still valid.
    /// Should be called on app foreground and periodically during use.
    func checkCredentialState() async {
        guard let user = currentUser else { return }
        
        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: user.userId)
            switch state {
            case .revoked, .notFound, .transferred:
                // Credential is no longer usable for this app — revoked from
                // Settings, never granted, or transferred to another Apple ID.
                signOut()
                authState = .error("Your Apple ID authentication is no longer valid. Please sign in again.")
            case .authorized:
                break
            @unknown default:
                break
            }
        } catch {
            Log.ui.error("Failed to check Apple ID credential state: \(error)")
        }
    }

    func getCurrentJWT() throws -> String {
        guard let jwt = KeychainHelper.get(for: KeychainHelper.Key.userJWT) else {
            throw AppleAuthError.notAuthenticated
        }
        if let user = currentUser, user.isJWTExpired {
            throw AppleAuthError.jwtExpired
        }
        return jwt
    }

    // MARK: - Helpers

    static let authenticatedUserKey = "authenticatedUser"

    static func generateNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if status != errSecSuccess {
                random = UInt8.random(in: 0...UInt8.max)
            }
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Models

struct JWTExchangeRequest: Codable {
    let appleIdToken: String
    /// Raw nonce. Server SHA256s and compares against the `nonce` claim Apple
    /// embedded in the ID token to confirm this exchange is for the request
    /// the client just made.
    let nonce: String
    let userId: String
    let deviceId: String
}

struct JWTExchangeResponse: Codable {
    let jwt: String
    let expiresIn: Int
    let userId: String
}

// MARK: - Errors

enum AppleAuthError: Error, LocalizedError {
    case notAuthenticated
    case invalidAppleToken
    case invalidCredentialType
    case missingNonce
    case jwtExchangeFailed(statusCode: Int)
    case invalidExchangeResponse
    case jwtExpired
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated. Please sign in with Apple."
        case .invalidAppleToken:
            return "Invalid Apple ID token received."
        case .invalidCredentialType:
            return "Unexpected credential type from Apple."
        case .missingNonce:
            return "Sign in with Apple completed without a matching nonce. Please try again."
        case .jwtExchangeFailed(let statusCode):
            return "Failed to exchange Apple token for JWT. Status: \(statusCode)"
        case .invalidExchangeResponse:
            return "JWT exchange response was malformed."
        case .jwtExpired:
            return "Your session has expired. Please sign in again."
        case .missingCredentials:
            return "Service principal credentials not configured."
        }
    }
}
