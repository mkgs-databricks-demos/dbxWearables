import SwiftUI

/// Main dashboard showing sync status and data summary.
struct ContentView: View {
    @StateObject private var viewModel = DashboardViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section("Sync Status") {
                    if viewModel.isSyncing {
                        HStack {
                            ProgressView()
                            Text("Syncing...")
                        }
                    } else if let lastSync = viewModel.lastSyncDate {
                        Text("Last sync: \(lastSync, style: .relative) ago")
                        Text("\(viewModel.lastSyncRecordCount) records uploaded")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not yet synced")
                    }

                    Button("Sync Now") {
                        Task { await viewModel.syncNow() }
                    }
                    .disabled(viewModel.isSyncing)
                }

                Section {
                    NavigationLink("Settings") {
                        SettingsView()
                    }
                    NavigationLink("Sync History") {
                        SyncHistoryView()
                    }
                }
            }
            .navigationTitle("dbxWearables")
            .task {
                await viewModel.requestAuthorization()
            }
        }
    }
}
