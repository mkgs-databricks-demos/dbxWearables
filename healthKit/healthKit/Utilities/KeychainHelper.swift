import Foundation
import Security

/// Multi-account secure storage for credentials and tokens via the iOS Keychain.
///
/// All items are stored with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so they
/// are available to background-delivered HealthKit sync after the device has been
/// unlocked once since reboot, but never sync to iCloud or other devices.
enum KeychainHelper {

    /// Account keys used by the app. Centralized here to avoid string-literal drift.
    enum Key {
        /// Databricks service-principal client ID (M2M OAuth).
        static let databricksClientID = "databricks_client_id"
        /// Databricks service-principal client secret (M2M OAuth).
        static let databricksClientSecret = "databricks_client_secret"
        /// Cached OAuth access token from the Databricks token endpoint.
        static let oauthAccessToken = "oauth_access_token"
        /// Cached OAuth access token expiry as ISO-8601 string.
        static let oauthAccessTokenExpiry = "oauth_access_token_expiry"
    }

    private static let service = "com.dbxwearables.api"

    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    static func get(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static func exists(for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}
