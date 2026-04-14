import UIKit

/// Drives the main dashboard view with sync status and summary data.
@MainActor
final class DashboardViewModel: ObservableObject {

    private var appDelegate: AppDelegate {
        UIApplication.shared.delegate as! AppDelegate
    }

    @Published var lastSyncDate: Date?
    @Published var lastSyncRecordCount = 0
    @Published var isSyncing = false

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
    }
}
