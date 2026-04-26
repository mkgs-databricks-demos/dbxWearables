import UIKit
import Combine
import OSLog

/// Manages the HealthKit authorization flow state for PermissionsView.
@MainActor
final class PermissionsViewModel: ObservableObject {

    private let healthKitManager: HealthKitManager

    @Published var isAuthorized = false
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    init(healthKitManager: HealthKitManager) {
        self.healthKitManager = healthKitManager
        observeHealthKitManager()
    }
    
    private func observeHealthKitManager() {
        // Observe the authorization state from HealthKitManager
        healthKitManager.$isAuthorized
            .receive(on: DispatchQueue.main)
            .assign(to: &$isAuthorized)
    }

    func requestAuthorization() async {
        do {
            try await healthKitManager.requestAuthorization()
            errorMessage = nil
        } catch {
            Log.ui.error("PermissionsViewModel: Authorization failed - \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }
}
