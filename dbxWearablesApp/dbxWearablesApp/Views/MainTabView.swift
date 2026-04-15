import SwiftUI

/// Root tab bar with Databricks branding. Shown after onboarding is complete.
struct MainTabView: View {
    @State private var selectedTab = Tab.dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar.fill")
                }
                .tag(Tab.dashboard)

            DataExplorerView()
                .tabItem {
                    Label("Data", systemImage: "doc.text.fill")
                }
                .tag(Tab.data)

            PayloadInspectorView()
                .tabItem {
                    Label("Payloads", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .tag(Tab.payloads)

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle.fill")
                }
                .tag(Tab.about)
        }
        .tint(DBXColors.dbxRed)
    }

    enum Tab {
        case dashboard, data, payloads, about
    }
}
