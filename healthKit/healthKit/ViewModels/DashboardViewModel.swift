import UIKit
import Combine

/// Drives the main dashboard view with sync status, category counts, and recent activity.
@MainActor
final class DashboardViewModel: ObservableObject {

    private var appDelegate: AppDelegate? {
        UIApplication.shared.delegate as? AppDelegate
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
    
    private var cancellables = Set<AnyCancellable>()

    init() {
        observeSyncCoordinator()
        checkEndpointConfiguration()
    }
    
    private func observeSyncCoordinator() {
        guard let coordinator = appDelegate?.syncCoordinator else { return }
        
        // Observe sync state changes from the coordinator
        coordinator.$isSyncing
            .receive(on: DispatchQueue.main)
            .assign(to: &$isSyncing)
        
        coordinator.$lastSyncDate
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastSyncDate)
        
        coordinator.$lastSyncRecordCount
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastSyncRecordCount)
    }
    
    private func checkEndpointConfiguration() {
        isEndpointConfigured = ProcessInfo.processInfo.environment["DBX_API_BASE_URL"] != nil
    }

    func requestAuthorization() async {
        guard let appDelegate else {
            print("Warning: AppDelegate not available")
            return
        }
        try? await appDelegate.healthKitManager.requestAuthorization()
    }

    func syncNow() async {
        guard let appDelegate else {
            print("Warning: AppDelegate not available")
            return
        }
        await appDelegate.syncCoordinator.sync(context: .foreground)
        await loadStats()
    }

    /// Load persisted stats from SyncLedger.
    func loadStats() async {
        guard let appDelegate else {
            print("Warning: AppDelegate not available")
            return
        }
        
        let ledger = appDelegate.syncCoordinator.syncLedger
        let stats = await ledger.getStats()
        categoryCounts = stats.totalRecordsSent
        recentEvents = await ledger.getRecentEvents()
    }
}
