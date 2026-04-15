import UIKit

/// Manages the HealthKit authorization flow state for PermissionsView.
@MainActor
final class PermissionsViewModel: ObservableObject {

    private var healthKitManager: HealthKitManager {
        (UIApplication.shared.delegate as! AppDelegate).healthKitManager
    }

    @Published var isAuthorized = false
    @Published var errorMessage: String?

    func requestAuthorization() async {
        do {
            try await healthKitManager.requestAuthorization()
            isAuthorized = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
