import SwiftUI

@main
struct dbxWearablesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(appDelegate.healthKitManager)
                .environmentObject(appDelegate.syncCoordinator)
                .onAppear {
                    if !hasCompletedOnboarding {
                        showOnboarding = true
                    }
                }
                .fullScreenCover(isPresented: $showOnboarding) {
                    OnboardingView(
                        isPresented: $showOnboarding,
                        hasCompletedOnboarding: $hasCompletedOnboarding,
                        healthKitManager: appDelegate.healthKitManager
                    )
                    .environmentObject(appDelegate.healthKitManager)
                }
        }
    }
}
