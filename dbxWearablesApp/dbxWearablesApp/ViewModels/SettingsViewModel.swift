import Foundation

/// Drives the Settings view with API configuration state.
@MainActor
final class SettingsViewModel: ObservableObject {

    @Published var apiBaseURL: String = ""

    init() {
        apiBaseURL = ProcessInfo.processInfo.environment["DBX_API_BASE_URL"] ?? "(not configured)"
    }
}
