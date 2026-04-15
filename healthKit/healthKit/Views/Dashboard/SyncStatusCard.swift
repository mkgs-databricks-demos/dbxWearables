import SwiftUI

/// The prominent sync button and status display for the Dashboard.
struct SyncStatusCard: View {
    let isSyncing: Bool
    let lastSyncDate: Date?
    let lastSyncRecordCount: Int
    let onSync: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Sync button
            Button(action: onSync) {
                HStack(spacing: 10) {
                    if isSyncing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(isSyncing ? "Syncing..." : "Sync Now")
                }
            }
            .buttonStyle(DBXPrimaryButtonStyle(isFullWidth: true))
            .disabled(isSyncing)

            // Status details
            if let lastSync = lastSyncDate {
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DBXColors.dbxGreen)
                        Text("Last sync: \(lastSync, style: .relative) ago")
                            .font(.subheadline)
                    }

                    Text("\(lastSyncRecordCount) records uploaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !isSyncing {
                HStack {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                    Text("Not yet synced")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .dbxGlassCard()
    }
}
