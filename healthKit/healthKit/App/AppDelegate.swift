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
}
