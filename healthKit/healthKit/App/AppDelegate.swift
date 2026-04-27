import UIKit
import HealthKit

class AppDelegate: NSObject, UIApplicationDelegate {

    let healthKitManager = HealthKitManager()
    private(set) lazy var syncCoordinator = SyncCoordinator(healthStore: healthKitManager.healthStore)

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // UI tests pass `-resetForUITests YES` to wipe persisted state at launch
        // so each test sees a deterministic empty SyncLedger and no @AppStorage
        // residue from prior runs.
        if UserDefaults.standard.bool(forKey: "resetForUITests") {
            wipePersistedStateForUITests()
        }

        // UI-test fixtures for the gated onboarding flow. These let tests
        // satisfy individual gates without exercising real network/Apple flows.
        if UserDefaults.standard.bool(forKey: "onboardingPrefillCredentials") {
            prefillCredentialsForUITests()
        }
        if UserDefaults.standard.bool(forKey: "onboardingSimulateSignedIn") {
            simulateSignedInForUITests()
        }

        // Wire the sync coordinator into the HealthKit manager so observer
        // queries trigger a sync cycle when new data arrives in the background.
        healthKitManager.syncCoordinator = syncCoordinator

        // Register background delivery and observer queries for all configured types.
        // This must be called at every app launch — registrations do not persist.
        healthKitManager.registerBackgroundDelivery()
        return true
    }

    private func wipePersistedStateForUITests() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        if let ledgerDir = docs?.appendingPathComponent("sync_ledger", isDirectory: true) {
            try? FileManager.default.removeItem(at: ledgerDir)
        }
    }

    /// Seeds Keychain + WorkspaceConfig with synthetic SPN credentials so the
    /// onboarding credentials gate (`credentialsConfigured`) reports true at
    /// launch. Used by UI tests; the values are not valid for real auth.
    private func prefillCredentialsForUITests() {
        _ = KeychainHelper.set("uitest-client-id", for: KeychainHelper.Key.databricksClientID)
        _ = KeychainHelper.set("uitest-client-secret", for: KeychainHelper.Key.databricksClientSecret)
        if let api = URL(string: "https://test.databricks.com/apps/wearables"),
           let host = URL(string: "https://test.cloud.databricks.com") {
            WorkspaceConfig.set(apiBaseURL: api, host: host, label: "UITest Workspace")
        }
    }

    /// Seeds Keychain + UserDefaults with a non-expired JWT and AuthenticatedUser
    /// so AppleSignInManager.restoreSession() lands in `.authenticated` at
    /// launch — satisfying the onboarding sign-in gate without invoking SIWA.
    private func simulateSignedInForUITests() {
        let formatter = ISO8601DateFormatter()
        let expiry = Date().addingTimeInterval(3600)
        _ = KeychainHelper.set("uitest-jwt", for: KeychainHelper.Key.userJWT)
        _ = KeychainHelper.set(formatter.string(from: expiry), for: KeychainHelper.Key.userJWTExpiry)

        let user = AppleSignInManager.AuthenticatedUser(
            userId: "uitest-user",
            email: "uitest@example.com",
            fullName: nil,
            authenticatedAt: Date(),
            jwtExpiresAt: expiry
        )
        if let encoded = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(encoded, forKey: AppleSignInManager.authenticatedUserKey)
        }
    }
}
