import Foundation

/// Runtime workspace configuration set via QR scan or manual entry in
/// `CredentialsConfigView`. Persisted to `UserDefaults` (URLs are not secrets;
/// the matching SPN client_id/secret live in the Keychain).
///
/// `APIConfiguration` reads from here first and falls back to the
/// `DBX_API_BASE_URL` / `DBX_WORKSPACE_HOST` environment variables (which the
/// Xcode schemes still set for dev builds and UI tests).
enum WorkspaceConfig {

    enum Key {
        static let apiBaseURL = "workspace_api_base_url"
        static let host = "workspace_host"
        static let label = "workspace_label"
    }

    /// Returns the persisted URL for `key` if it parses as a valid http(s) URL.
    static func storedURL(for key: String) -> URL? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        return validatedURL(from: raw)
    }

    /// Optional human-readable label (e.g. "Field Eng Demo") used in the UI.
    static var label: String? {
        UserDefaults.standard.string(forKey: Key.label)
    }

    /// True when both URLs are present and valid.
    static var isFullyConfigured: Bool {
        storedURL(for: Key.apiBaseURL) != nil && storedURL(for: Key.host) != nil
    }

    /// Atomically write the two workspace URLs and an optional label.
    /// Caller is responsible for invalidating any cached OAuth/JWT tokens.
    static func set(apiBaseURL: URL, host: URL, label: String?) {
        let defaults = UserDefaults.standard
        defaults.set(apiBaseURL.absoluteString, forKey: Key.apiBaseURL)
        defaults.set(host.absoluteString, forKey: Key.host)
        if let label, !label.isEmpty {
            defaults.set(label, forKey: Key.label)
        } else {
            defaults.removeObject(forKey: Key.label)
        }
    }

    /// Remove all persisted workspace URLs and the label.
    static func clear() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Key.apiBaseURL)
        defaults.removeObject(forKey: Key.host)
        defaults.removeObject(forKey: Key.label)
    }

    /// Parse and validate a user-entered URL string. Requires an http(s) scheme
    /// and a non-empty host so we don't silently accept garbage from QR or
    /// manual entry.
    static func validatedURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else {
            return nil
        }
        return url
    }
}
