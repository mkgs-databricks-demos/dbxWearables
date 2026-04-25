import UIKit
import Combine
import OSLog

/// Drives the main dashboard view with sync status, category counts, and recent activity.
@MainActor
final class DashboardViewModel: ObservableObject {

    private let healthKitManager: HealthKitManager
    private let syncCoordinator: SyncCoordinator

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

    init(healthKitManager: HealthKitManager, syncCoordinator: SyncCoordinator) {
        self.healthKitManager = healthKitManager
        self.syncCoordinator = syncCoordinator
        observeSyncCoordinator()
        checkEndpointConfiguration()
    }
    
    /// Convenience initializer that gets dependencies from AppDelegate
    convenience init() {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            fatalError("AppDelegate not available - ensure the app is properly initialized")
        }
        self.init(
            healthKitManager: appDelegate.healthKitManager,
            syncCoordinator: appDelegate.syncCoordinator
        )
    }
    
    private func observeSyncCoordinator() {
        // Observe sync state changes from the coordinator
        syncCoordinator.$isSyncing
            .receive(on: DispatchQueue.main)
            .assign(to: &$isSyncing)
        
        syncCoordinator.$lastSyncDate
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastSyncDate)
        
        syncCoordinator.$lastSyncRecordCount
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastSyncRecordCount)
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
