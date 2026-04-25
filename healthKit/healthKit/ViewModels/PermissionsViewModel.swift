import UIKit
import Combine

/// Manages the HealthKit authorization flow state for PermissionsView.
@MainActor
final class PermissionsViewModel: ObservableObject {

    private var appDelegate: AppDelegate? {
        UIApplication.shared.delegate as? AppDelegate
    }
    
    private var healthKitManager: HealthKitManager? {
        appDelegate?.healthKitManager
    }

    @Published var isAuthorized = false
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        observeHealthKitManager()
    }
    
    private func observeHealthKitManager() {
        guard let healthKitManager else { return }
        
        // Observe the authorization state from HealthKitManager
        healthKitManager.$isAuthorized
            .receive(on: DispatchQueue.main)
            .assign(to: &$isAuthorized)
    }

    func requestAuthorization() async {
        guard let healthKitManager else {
            errorMessage = "Health Kit manager not available"
            return
        }
        
        do {
            try await healthKitManager.requestAuthorization()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
