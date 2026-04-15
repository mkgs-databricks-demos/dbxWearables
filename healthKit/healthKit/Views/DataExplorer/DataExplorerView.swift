import SwiftUI

/// Tab 2: Per-category breakdown of data sent to Databricks.
struct DataExplorerView: View {
    @StateObject private var viewModel = DataExplorerViewModel()

    var body: some View {
        NavigationStack {
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
            .task {
                await viewModel.loadStats()
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
