import SwiftUI

/// Tab 2: Per-category breakdown of data sent to Databricks.
struct DataExplorerView: View {
    @EnvironmentObject private var syncCoordinator: SyncCoordinator
    @StateObject private var viewModel: DataExplorerViewModel
    @State private var isVisible = false
    
    init() {
        // Create with a temporary SyncLedger - will be replaced in task
        _viewModel = StateObject(wrappedValue: DataExplorerViewModel(syncLedger: SyncLedger()))
    }

    var body: some View {
        NavigationStack {
            dataExplorerContent(viewModel: viewModel)
                .task {
                    // Replace the dummy syncLedger with the real one
                    viewModel.syncLedger = syncCoordinator.syncLedger
                    await viewModel.loadStats()
                }
        }
    }
    
    @ViewBuilder
    private func dataExplorerContent(viewModel: DataExplorerViewModel) -> some View {
        List {
            ForEach(viewModel.categorySummaries) { summary in
                NavigationLink {
                    CategoryDetailView(
                        summary: summary,
                        breakdown: viewModel.breakdown(for: summary.recordType),
                        stats: viewModel.stats
                    )
                } label: {
                    categoryRow(summary)
                }
            }
        }
        .navigationTitle("Data Explorer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.loadStats() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .refreshable {
            await viewModel.loadStats()
        }
        .onAppear {
            isVisible = true
            Task { await viewModel.loadStats() }
        }
        .onDisappear {
            isVisible = false
        }
        .onChange(of: syncCoordinator.lastSyncDate) { _, _ in
            // Reload stats whenever a sync completes
            if isVisible {
                Task { await viewModel.loadStats() }
            }
        }
    }

    private func categoryRow(_ summary: CategorySummary) -> some View {
        HStack(spacing: 14) {
            Image(systemName: summary.icon)
                .font(.system(size: 20))
                .foregroundStyle(DBXColors.dbxRed)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let lastSync = summary.lastSync {
                    Text("Last sent: \(lastSync, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No data sent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("\(summary.totalCount)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(summary.totalCount > 0 ? DBXColors.dbxRed : .secondary)
        }
        .padding(.vertical, 4)
    }
}
