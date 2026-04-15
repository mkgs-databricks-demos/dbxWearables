import UIKit

/// Drives the main dashboard view with sync status, category counts, and recent activity.
@MainActor
final class DashboardViewModel: ObservableObject {

    private var appDelegate: AppDelegate {
        UIApplication.shared.delegate as! AppDelegate
    }

    @Published var lastSyncDate: Date?
    @Published var lastSyncRecordCount = 0
    @Published var isSyncing = false

    /// Per-record-type cumulative counts for the category grid.
    @Published var categoryCounts: [String: Int] = [:]

    /// Most recent sync events for the activity feed.
    @Published var recentEvents: [SyncRecord] = []

    /// Whether the API endpoint is configured.
    @Published var isEndpointConfigured: Bool = false

    func requestAuthorization() async {
        try? await appDelegate.healthKitManager.requestAuthorization()
    }

    func syncNow() async {
        isSyncing = true
        let coordinator = appDelegate.syncCoordinator
        await coordinator.sync(context: .foreground)
        lastSyncDate = coordinator.lastSyncDate
        lastSyncRecordCount = coordinator.lastSyncRecordCount
        isSyncing = false
        await loadStats()
    }

    /// Load persisted stats from SyncLedger.
    func loadStats() async {
        let ledger = appDelegate.syncCoordinator.syncLedger
        let stats = await ledger.getStats()
        categoryCounts = stats.totalRecordsSent
        recentEvents = await ledger.getRecentEvents()
        isEndpointConfigured = ProcessInfo.processInfo.environment["DBX_API_BASE_URL"] != nil
    }
}
