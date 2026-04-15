import SwiftUI

@main
struct dbxWearablesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .onAppear {
                    if !hasCompletedOnboarding {
                        showOnboarding = true
                    }
                }
                .sheet(isPresented: $showOnboarding, onDismiss: {
                    hasCompletedOnboarding = true
                }) {
                    OnboardingView(isPresented: $showOnboarding)
                }
        }
    }
}
