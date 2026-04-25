import UIKit
import OSLog

/// Drives the main dashboard view with sync status, category counts, and recent activity.
@MainActor
final class DashboardViewModel: ObservableObject {

    private let healthKitManager: HealthKitManager
    private let syncCoordinator: SyncCoordinator

    /// Per-record-type cumulative counts for the category grid.
    @Published var categoryCounts: [String: Int] = [:]

    /// Most recent sync events for the activity feed.
    @Published var recentEvents: [SyncRecord] = []

    /// Whether the API endpoint is configured.
    @Published var isEndpointConfigured: Bool = false

    init(healthKitManager: HealthKitManager, syncCoordinator: SyncCoordinator) {
        self.healthKitManager = healthKitManager
        self.syncCoordinator = syncCoordinator
        checkEndpointConfiguration()
    }
    
    private func checkEndpointConfiguration() {
        isEndpointConfigured = ProcessInfo.processInfo.environment["DBX_API_BASE_URL"] != nil
    }

    func requestAuthorization() async {
        do {
            try await healthKitManager.requestAuthorization()
        } catch {
            Log.ui.error("DashboardViewModel: Authorization failed - \(error.localizedDescription)")
        }
    }

    func syncNow() async {
        await syncCoordinator.sync(context: .foreground)
        await loadStats()
    }

    /// Load persisted stats from SyncLedger.
    func loadStats() async {
        let ledger = syncCoordinator.syncLedger
        let stats = await ledger.getStats()
        categoryCounts = stats.totalRecordsSent
        recentEvents = await ledger.getRecentEvents()
    }
}
