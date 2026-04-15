import Foundation
import Security

/// Generates and persists a stable per-installation device identifier via Keychain.
/// This is NOT a hardware ID — it's a UUID created on first launch and preserved
/// across app updates (but not across uninstall/reinstall).
enum DeviceIdentifier {

    private static let service = "com.dbxwearables.device"
    private static let account = "device_id"

    /// Returns the persistent device ID, creating one on first access.
    static var current: String {
        if let existing = retrieve() {
            return existing
        }
        let newId = UUID().uuidString
        save(newId)
        return newId
    }

    private static func retrieve() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func save(_ id: String) {
        guard let data = id.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }
}
