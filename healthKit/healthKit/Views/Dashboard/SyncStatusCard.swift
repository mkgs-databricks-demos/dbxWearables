import SwiftUI

/// The prominent sync button and status display for the Dashboard.
/// Now with enhanced status tracking, progress, and error handling.
struct SyncStatusCard: View {
    let syncStatus: SyncStatus
    let lastSyncDate: Date?
    let lastSyncRecordCount: Int
    let onSync: () -> Void
    let onRetry: (() -> Void)?
    
    // Legacy initializer for compatibility
    init(
        isSyncing: Bool,
        lastSyncDate: Date?,
        lastSyncRecordCount: Int,
        onSync: @escaping () -> Void
    ) {
        self.syncStatus = isSyncing ? 
            .syncing(progress: SyncProgress(currentType: "Syncing...", completedTypes: 0, totalTypes: 1, recordsUploaded: 0)) : 
            .idle
        self.lastSyncDate = lastSyncDate
        self.lastSyncRecordCount = lastSyncRecordCount
        self.onSync = onSync
        self.onRetry = nil
    }
    
    // New initializer with enhanced status
    init(
        syncStatus: SyncStatus,
        lastSyncDate: Date?,
        lastSyncRecordCount: Int,
        onSync: @escaping () -> Void,
        onRetry: (() -> Void)? = nil
    ) {
        self.syncStatus = syncStatus
        self.lastSyncDate = lastSyncDate
        self.lastSyncRecordCount = lastSyncRecordCount
        self.onSync = onSync
        self.onRetry = onRetry
    }

    var body: some View {
        VStack(spacing: 16) {
            // Main sync button
            syncButton
            
            // Status details
            statusDetails
        }
        .dbxGlassCard()
    }
    
    // MARK: - Sync Button
    
    private var syncButton: some View {
        Button(action: syncStatus.isActive ? {} : onSync) {
            HStack(spacing: 10) {
                buttonIcon
                Text(buttonText)
            }
        }
        .buttonStyle(DBXPrimaryButtonStyle(isFullWidth: true))
        .disabled(syncStatus.isActive)
    }
    
    private var buttonIcon: some View {
        Group {
            switch syncStatus {
            case .syncing:
                ProgressView()
                    .tint(.white)
            case .retrying:
                ProgressView()
                    .tint(.white)
            case .failed:
                Image(systemName: "exclamationmark.triangle")
            case .success:
                Image(systemName: "checkmark.circle")
            case .idle:
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        }
    }
    
    private var buttonText: String {
        switch syncStatus {
        case .syncing:
            return "Syncing..."
        case .retrying(let attempt, _):
            return "Retrying (\(attempt))..."
        case .failed:
            return "Sync Failed"
        case .success:
            return "Sync Again"
        case .idle:
            return "Sync Now"
        }
    }
    
    // MARK: - Status Details
    
    @ViewBuilder
    private var statusDetails: some View {
        switch syncStatus {
        case .idle:
            idleState
            
        case .syncing(let progress):
            syncingState(progress: progress)
            
        case .retrying(let attempt, let reason):
            retryingState(attempt: attempt, reason: reason)
            
        case .success(let summary):
            successState(summary: summary)
            
        case .failed(let error):
            failedState(error: error)
        }
    }
    
    private var idleState: some View {
        Group {
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
            } else {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Tap Sync Now to start")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private func syncingState(progress: SyncProgress) -> some View {
        VStack(spacing: 8) {
            Text(progress.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DBXColors.dbxRed)
                        .frame(width: geometry.size.width * progress.percentage, height: 6)
                }
            }
            .frame(height: 6)
            
            if progress.recordsUploaded > 0 {
                Text("\(progress.recordsUploaded) records uploaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func retryingState(attempt: Int, reason: String) -> some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(DBXColors.dbxYellow)
                Text("Retrying after error...")
                    .font(.subheadline)
                    .foregroundStyle(DBXColors.dbxYellow)
            }
            
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private func successState(summary: SyncSummary) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DBXColors.dbxGreen)
                Text("Sync completed!")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text("\(summary.totalRecords)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .monospacedDigit()
                    Text("records")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Divider()
                    .frame(height: 30)
                
                VStack(spacing: 2) {
                    Text(summary.formattedDuration)
                        .font(.title3)
                        .fontWeight(.bold)
                        .monospacedDigit()
                    Text("duration")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private func failedState(error: SyncError) -> some View {
        VStack(spacing: 12) {
            // Error message
            VStack(spacing: 4) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Sync Failed")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.red)
                }
                
                Text(error.userMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Suggested action
            if let action = error.suggestedAction {
                Text(action)
                    .font(.caption2)
                    .foregroundStyle(DBXColors.dbxRed)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(DBXColors.dbxRed.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // Retry button
            if error.isRetryable, let retry = onRetry {
                Button {
                    retry()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry Now")
                    }
                    .font(.subheadline)
                }
                .buttonStyle(DBXSecondaryButtonStyle())
            }
        }
    }
}
