import UIKit
import HealthKit

class AppDelegate: NSObject, UIApplicationDelegate {

    let healthKitManager = HealthKitManager()
    private(set) lazy var syncCoordinator = SyncCoordinator(healthStore: healthKitManager.healthStore)

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Wire the sync coordinator into the HealthKit manager so observer
        // queries trigger a sync cycle when new data arrives in the background.
        healthKitManager.syncCoordinator = syncCoordinator

        // Register background delivery and observer queries for all configured types.
        // This must be called at every app launch — registrations do not persist.
        healthKitManager.registerBackgroundDelivery()
        return true
    }
}
