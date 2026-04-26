import Foundation
import AuthenticationServices
import CryptoKit

/// Manages Sign in with Apple authentication flow for Databricks JWT authentication.
///
/// Flow:
/// 1. User initiates Sign in with Apple
/// 2. Apple returns ID token
/// 3. Exchange Apple token + SPN credentials with Databricks
/// 4. Databricks returns JWT for HealthKit data uploads
/// 5. JWT stored in Keychain for authenticated requests
@MainActor
final class AppleSignInManager: NSObject, ObservableObject {
    
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
    private let apiConfiguration: DatabricksAPIConfiguration
    
    init(authService: AuthProviding = AuthService(),
         apiConfiguration: DatabricksAPIConfiguration = .production) {
        self.authService = authService
        self.apiConfiguration = apiConfiguration
        super.init()
        
        // Restore previous session if available
        restoreSession()
    }
    
    // MARK: - Sign In
    
    /// Initiate Sign in with Apple flow
    func signIn() async {
        authState = .signingIn
        
        do {
            // 1. Get Apple ID credential
            let appleIDCredential = try await performAppleSignIn()
            
            // 2. Exchange with Databricks for JWT
            let jwt = try await exchangeAppleTokenForJWT(appleIDCredential)
            
            // 3. Store JWT and user info
            try storeAuthentication(jwt: jwt, credential: appleIDCredential)
            
            authState = .authenticated
            
        } catch {
            authState = .error(error.localizedDescription)
        }
    }
    
    /// Perform Apple Sign In and get credential
    private func performAppleSignIn() async throws -> ASAuthorizationAppleIDCredential {
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        
        // Generate nonce for security
        let nonce = generateNonce()
        request.nonce = sha256(nonce)
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = SignInDelegate(continuation: continuation)
            authorizationController.delegate = delegate
            authorizationController.presentationContextProvider = delegate
            authorizationController.performRequests()
            
            // Keep delegate alive
            objc_setAssociatedObject(authorizationController, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// Exchange Apple ID token for Databricks JWT
    private func exchangeAppleTokenForJWT(_ credential: ASAuthorizationAppleIDCredential) async throws -> String {
        guard let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw AppleAuthError.invalidAppleToken
        }
        
        // Build request to Databricks JWT endpoint
        let url = apiConfiguration.jwtExchangeEndpoint
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Include SPN credentials for authorization
        let spnToken = try await authService.bearerToken()
        request.setValue("Bearer \(spnToken)", forHTTPHeaderField: "Authorization")
        
        // Request body with Apple ID token
        let body = JWTExchangeRequest(
            appleIdToken: tokenString,
            userId: credential.user,
            deviceId: DeviceIdentifier.current
        )
        request.httpBody = try JSONEncoder().encode(body)
        
        // Execute request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AppleAuthError.jwtExchangeFailed(statusCode: statusCode)
        }
        
        let jwtResponse = try JSONDecoder().decode(JWTExchangeResponse.self, from: data)
        return jwtResponse.jwt
    }
    
    /// Store authentication data in Keychain
    private func storeAuthentication(jwt: String, credential: ASAuthorizationAppleIDCredential) throws {
        // Store JWT
        KeychainHelper.set(jwt, for: KeychainHelper.Key.userJWT)
        
        // Store JWT expiry (typically 1 hour)
        let expiryDate = Date().addingTimeInterval(3600)
        let expiryString = ISO8601DateFormatter().string(from: expiryDate)
        KeychainHelper.set(expiryString, for: KeychainHelper.Key.userJWTExpiry)
        
        // Store user info
        let user = AuthenticatedUser(
            userId: credential.user,
            email: credential.email,
            fullName: credential.fullName,
            authenticatedAt: Date(),
            jwtExpiresAt: expiryDate
        )
        
        if let encoded = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(encoded, forKey: "authenticatedUser")
        }
        
        currentUser = user
    }
    
    // MARK: - Sign Out
    
    func signOut() {
        // Clear JWT
        KeychainHelper.delete(for: KeychainHelper.Key.userJWT)
        KeychainHelper.delete(for: KeychainHelper.Key.userJWTExpiry)
        
        // Clear user info
        UserDefaults.standard.removeObject(forKey: "authenticatedUser")
        
        currentUser = nil
        authState = .unauthenticated
    }
    
    // MARK: - Session Management
    
    /// Restore previous authentication session
    private func restoreSession() {
        guard let data = UserDefaults.standard.data(forKey: "authenticatedUser"),
              let user = try? JSONDecoder().decode(AuthenticatedUser.self, from: data),
              KeychainHelper.exists(for: KeychainHelper.Key.userJWT) else {
            return
        }
        
        // Check if JWT is expired
        if user.isJWTExpired {
            signOut()
            return
        }
        
        currentUser = user
        authState = .authenticated
    }
    
    /// Refresh JWT if expired
    func refreshJWTIfNeeded() async throws {
        guard let user = currentUser, user.isJWTExpired else {
            return
        }
        
        // JWT expired - need to re-authenticate
        signOut()
        throw AppleAuthError.jwtExpired
    }
    
    /// Get current JWT for API requests
    func getCurrentJWT() throws -> String {
        guard let jwt = KeychainHelper.get(for: KeychainHelper.Key.userJWT) else {
            throw AppleAuthError.notAuthenticated
        }
        
        // Check expiry
        if let user = currentUser, user.isJWTExpired {
            throw AppleAuthError.jwtExpired
        }
        
        return jwt
    }
    
    // MARK: - Helpers
    
    private func generateNonce() -> String {
        let nonce = UUID().uuidString
        return nonce
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Sign In Delegate

private class SignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    
    let continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>
    
    init(continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>) {
        self.continuation = continuation
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            continuation.resume(returning: appleIDCredential)
        } else {
            continuation.resume(throwing: AppleAuthError.invalidCredentialType)
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation.resume(throwing: error)
    }
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            fatalError("No window available for Sign in with Apple")
        }
        return window
    }
}

// MARK: - Models

struct JWTExchangeRequest: Codable {
    let appleIdToken: String
    let userId: String
    let deviceId: String
}

struct JWTExchangeResponse: Codable {
    let jwt: String
    let expiresIn: Int
    let userId: String
}

// MARK: - Configuration

struct DatabricksAPIConfiguration {
    let jwtExchangeEndpoint: URL
    
    static var production: DatabricksAPIConfiguration {
        let baseURL = ProcessInfo.processInfo.environment["DBX_API_BASE_URL"] ?? ""
        let url = URL(string: baseURL)!.appendingPathComponent("/api/v1/auth/apple/exchange")
        return DatabricksAPIConfiguration(jwtExchangeEndpoint: url)
    }
}

// MARK: - Errors

enum AppleAuthError: Error, LocalizedError {
    case notAuthenticated
    case invalidAppleToken
    case invalidCredentialType
    case jwtExchangeFailed(statusCode: Int)
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
        case .jwtExchangeFailed(let statusCode):
            return "Failed to exchange Apple token for JWT. Status: \(statusCode)"
        case .jwtExpired:
            return "Your session has expired. Please sign in again."
        case .missingCredentials:
            return "Service principal credentials not configured."
        }
    }
}
