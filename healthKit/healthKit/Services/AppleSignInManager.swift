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
        Log.ui.info("Sign in with Apple: Preparing request...")
        
        // Log configuration status for debugging
        Log.ui.info("Sign in with Apple: API Base URL configured: \(APIConfiguration.configuredBaseURL?.absoluteString ?? "NOT SET")")
        Log.ui.info("Sign in with Apple: Workspace Host configured: \(APIConfiguration.configuredWorkspaceHost?.absoluteString ?? "NOT SET")")
        
        let credentials = checkOAuthCredentials()
        Log.ui.info("Sign in with Apple: Client ID in keychain: \(credentials.hasClientID) (length: \(credentials.clientIDLength))")
        Log.ui.info("Sign in with Apple: Client Secret in keychain: \(credentials.hasClientSecret) (length: \(credentials.secretLength))")
        
        if credentials.hasClientID && credentials.hasClientSecret {
            Log.ui.info("Sign in with Apple: ✅ OAuth credentials appear valid")
        } else {
            Log.ui.warning("Sign in with Apple: ⚠️ OAuth credentials may be incomplete")
        }
        
        let nonce = Self.generateNonce()
        pendingNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
        authState = .signingIn
        Log.ui.info("Sign in with Apple: Request prepared, presenting Apple UI...")
    }

    /// Handle the result of the native Sign in with Apple flow.
    func completeSignIn(result: Result<ASAuthorization, Error>) async {
        defer { pendingNonce = nil }

        switch result {
        case .failure(let error):
            let nsError = error as NSError
            Log.ui.error("Sign in with Apple failed: \(error.localizedDescription)")
            Log.ui.error("Sign in with Apple error domain: \(nsError.domain), code: \(nsError.code)")
            
            // Log underlying error if available
            if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                Log.ui.error("Underlying error domain: \(underlyingError.domain), code: \(underlyingError.code)")
            }
            
            // Provide better error messages for common issues
            let userMessage: String
            if nsError.domain == "com.apple.AuthenticationServices.AuthorizationError" {
                switch nsError.code {
                case 1000:
                    // Code 1000 is "unknown" - often masks underlying AKAuthenticationError
                    if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
                       underlyingError.domain == "AKAuthenticationError" && underlyingError.code == -7026 {
                        #if targetEnvironment(simulator)
                        userMessage = "Sign in with Apple requires a properly configured Apple ID in Settings.\n\nTip: This error is common on simulators. For best results, test on a real device."
                        #else
                        userMessage = "Apple authentication failed. Please verify:\n1. You're signed into iCloud in Settings\n2. Your app has 'Sign in with Apple' capability enabled\n3. Your App ID is properly configured on developer.apple.com"
                        #endif
                    } else {
                        userMessage = "Sign in was cancelled or failed. Please try again."
                    }
                case 1001:
                    userMessage = "Sign in failed. Please check your Apple ID settings and try again."
                case 1002:
                    userMessage = "Unknown error occurred. Please try again later."
                case 1003:
                    userMessage = "Sign in was cancelled by the system."
                case 1004:
                    userMessage = "Sign in not handled. Please update the app."
                default:
                    userMessage = "Sign in failed with error code \(nsError.code). Please try again."
                }
            } else if nsError.domain == "AKAuthenticationError" {
                switch nsError.code {
                case -7026:
                    #if targetEnvironment(simulator)
                    userMessage = "Apple ID authentication failed.\n\nSimulator tip: Ensure you're signed into iCloud in Settings → Apple ID. Consider testing on a real device for more reliable results."
                    #else
                    userMessage = "Apple authentication failed. Please verify:\n1. You're signed into iCloud in Settings\n2. Sign in with Apple capability is enabled in Xcode\n3. Your provisioning profile is up to date"
                    #endif
                default:
                    userMessage = "Apple ID authentication error (code \(nsError.code)). Please check your Apple ID settings."
                }
            } else {
                userMessage = error.localizedDescription
            }
            
            authState = .error(userMessage)
            return
            
        case .success(let authorization):
            Log.ui.info("Sign in with Apple succeeded, processing credential...")
            
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                Log.ui.error("Invalid credential type received from Apple")
                authState = .error(AppleAuthError.invalidCredentialType.localizedDescription)
                return
            }
            
            Log.ui.info("Apple ID credential received for user: \(credential.user)")
            
            guard let identityToken = credential.identityToken,
                  let tokenString = String(data: identityToken, encoding: .utf8) else {
                Log.ui.error("Failed to extract identity token from Apple credential")
                authState = .error(AppleAuthError.invalidAppleToken.localizedDescription)
                return
            }
            
            Log.ui.info("Identity token extracted, length: \(tokenString.count)")
            
            guard let rawNonce = pendingNonce else {
                Log.ui.error("Missing nonce for Apple sign in completion")
                authState = .error(AppleAuthError.missingNonce.localizedDescription)
                return
            }

            Log.ui.info("Starting JWT exchange with Databricks...")
            
            do {
                let exchange = try await performExchange(
                    identityToken: tokenString,
                    userId: credential.user,
                    rawNonce: rawNonce
                )
                
                Log.ui.info("JWT exchange successful, storing authentication (expires in \(exchange.expiresIn)s)")
                
                try storeAuthentication(
                    jwt: exchange.jwt,
                    expiresIn: exchange.expiresIn,
                    userId: credential.user,
                    email: credential.email,
                    fullName: credential.fullName
                )
                
                Log.ui.info("Sign in with Apple completed successfully")
                authState = .authenticated
            } catch {
                Log.ui.error("JWT exchange or storage failed: \(error.localizedDescription)")
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
        // Check configuration before attempting network call
        guard APIConfiguration.configuredBaseURL != nil else {
            Log.api.error("JWT exchange: API base URL is not configured")
            throw AppleAuthError.missingCredentials
        }
        
        guard let configuredHost = APIConfiguration.configuredWorkspaceHost else {
            Log.api.error("JWT exchange: Workspace host is not configured")
            throw AppleAuthError.missingCredentials
        }
        
        let url = APIConfiguration.jwtExchangeURL
        Log.api.info("JWT exchange: URL = \(url.absoluteString)")
        Log.api.info("JWT exchange: Workspace host = \(configuredHost.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30 // Add explicit timeout

        Log.api.info("JWT exchange: Requesting SPN bearer token...")
        let spnToken: String
        do {
            let tokenStart = Date()
            spnToken = try await authService.bearerToken()
            let tokenDuration = Date().timeIntervalSince(tokenStart)
            Log.api.info("JWT exchange: SPN bearer token obtained in \(String(format: "%.2f", tokenDuration))s (length: \(spnToken.count))")
        } catch {
            Log.api.error("JWT exchange: Failed to obtain SPN bearer token: \(error.localizedDescription)")
            Log.api.error("JWT exchange: Error type: \(type(of: error))")
            if let authError = error as? AuthError {
                Log.api.error("JWT exchange: AuthError details: \(authError)")
            }
            throw error
        }
        
        request.setValue("Bearer \(spnToken)", forHTTPHeaderField: "Authorization")

        let body = JWTExchangeRequest(
            appleIdToken: identityToken,
            nonce: rawNonce,
            userId: userId,
            deviceId: DeviceIdentifier.current
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        request.httpBody = try encoder.encode(body)
        
        Log.api.info("JWT exchange: Sending request to Databricks (userId: \(userId))")
        Log.api.info("JWT exchange: Request headers: \(request.allHTTPHeaderFields ?? [:])")
        if let bodyData = request.httpBody, let bodyString = String(data: bodyData, encoding: .utf8) {
            // Log body but redact the actual token
            Log.api.info("JWT exchange: Request body structure: appleIdToken (length: \(identityToken.count)), nonce, userId, deviceId")
        }

        let requestStart = Date()
        let (data, response) = try await urlSession.data(for: request)
        let requestDuration = Date().timeIntervalSince(requestStart)
        Log.api.info("JWT exchange: Request completed in \(String(format: "%.2f", requestDuration))s")

        guard let http = response as? HTTPURLResponse else {
            Log.api.error("JWT exchange: Response is not HTTP")
            throw AppleAuthError.jwtExchangeFailed(statusCode: -1)
        }
        
        Log.api.info("JWT exchange: Received response with status \(http.statusCode)")
        
        guard (200...299).contains(http.statusCode) else {
            Log.api.error("JWT exchange: HTTP \(http.statusCode) - Response body: \(String(data: data, encoding: .utf8) ?? "(unable to decode)")")
            throw AppleAuthError.jwtExchangeFailed(statusCode: http.statusCode)
        }

        let decoded: JWTExchangeResponse
        do {
            decoded = try JSONDecoder().decode(JWTExchangeResponse.self, from: data)
            Log.api.info("JWT exchange: Successfully decoded response (expiresIn: \(decoded.expiresIn)s)")
        } catch {
            Log.api.error("JWT exchange: Failed to decode response body: \(error.localizedDescription)")
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
    
    /// Diagnostic function to check if OAuth credentials are properly configured
    func checkOAuthCredentials() -> (hasClientID: Bool, hasClientSecret: Bool, clientIDLength: Int, secretLength: Int) {
        let clientID = KeychainHelper.get(for: KeychainHelper.Key.databricksClientID) ?? ""
        let clientSecret = KeychainHelper.get(for: KeychainHelper.Key.databricksClientSecret) ?? ""
        
        return (
            hasClientID: !clientID.isEmpty,
            hasClientSecret: !clientSecret.isEmpty,
            clientIDLength: clientID.count,
            secretLength: clientSecret.count
        )
    }

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
