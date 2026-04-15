import SwiftUI

/// Displays a log of past sync attempts with success/failure status.
struct SyncHistoryView: View {

    var body: some View {
        List {
            Text("Sync history will appear here once syncing is implemented.")
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Sync History")
    }
}
