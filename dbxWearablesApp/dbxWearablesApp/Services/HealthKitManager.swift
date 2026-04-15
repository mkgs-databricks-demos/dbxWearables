import Foundation
import HealthKit
import OSLog

/// Central manager for HealthKit store access, authorization, background delivery,
/// and observer queries that trigger sync when new data arrives.
final class HealthKitManager: ObservableObject {

    let healthStore = HKHealthStore()

    @Published var isAuthorized = false

    /// The sync coordinator to trigger when observer queries fire.
    /// Set by the AppDelegate after both objects are initialized.
    var syncCoordinator: SyncCoordinator?

    /// Request read-only authorization for all configured HealthKit types.
    /// Note: HealthKit does not reveal which types the user actually granted — `success`
    /// only indicates the authorization dialog was presented.
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        try await healthStore.requestAuthorization(
            toShare: [],
            read: HealthKitConfiguration.allReadTypes
        )
        await MainActor.run { isAuthorized = true }
    }

    /// Register background delivery and observer queries for all configured sample types.
    /// Must be called at every app launch — registrations do not persist across terminations.
    ///
    /// When new samples arrive, the observer query callback triggers a sync cycle.
    /// The completion handler MUST be called to tell HealthKit we're done — failing
    /// to do so causes HealthKit to stop delivering updates.
    func registerBackgroundDelivery() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        for sampleType in HealthKitConfiguration.allSampleTypes {
            // Enable background delivery so observer queries fire while the app is suspended.
            healthStore.enableBackgroundDelivery(
                for: sampleType,
                frequency: HealthKitConfiguration.backgroundDeliveryFrequency
            ) { success, error in
                if let error {
                    Log.healthKit.error("Background delivery registration failed for \(sampleType.identifier): \(error.localizedDescription)")
                }
            }

            // Register an observer query that fires when new samples of this type arrive.
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completionHandler, error in
                if let error {
                    Log.healthKit.error("Observer query error for \(sampleType.identifier): \(error.localizedDescription)")
                    completionHandler()
                    return
                }

                Log.healthKit.info("Observer query fired for \(sampleType.identifier)")

                guard let coordinator = self?.syncCoordinator else {
                    completionHandler()
                    return
                }

                // Run sync in a Task — background execution time is limited (~30s).
                Task {
                    await coordinator.sync()
                    completionHandler()
                }
            }
            healthStore.execute(query)
        }
    }
}
