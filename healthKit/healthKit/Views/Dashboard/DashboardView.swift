import SwiftUI

/// Main dashboard tab showing sync controls, category stats, and recent activity.
struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    heroHeader
                    syncSection
                    categoryGrid
                    recentActivitySection
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .background(DBXColors.dbxLightGray)
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.requestAuthorization()
                await viewModel.loadStats()
            }
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatabricksWordmark(size: 16)

            Text("dbxWearables")
                .font(DBXTypography.heroTitle)
                .foregroundStyle(.white)

            Text("HealthKit \u{2192} ZeroBus")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))

            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.isEndpointConfigured ? DBXColors.dbxGreen : DBXColors.dbxRed)
                    .frame(width: 8, height: 8)
                Text(viewModel.isEndpointConfigured ? "Endpoint configured" : "Endpoint not configured")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(DBXGradients.heroHeader)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Sync Section

    private var syncSection: some View {
        SyncStatusCard(
            isSyncing: viewModel.isSyncing,
            lastSyncDate: viewModel.lastSyncDate,
            lastSyncRecordCount: viewModel.lastSyncRecordCount,
            onSync: { Task { await viewModel.syncNow() } }
        )
    }

    // MARK: - Category Grid

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data Sent")
                .font(DBXTypography.sectionHeader)

            LazyVGrid(columns: gridColumns, spacing: 12) {
                CategoryStatCard(
                    icon: "heart.text.square",
                    label: "Health Samples",
                    count: viewModel.categoryCounts["samples", default: 0]
                )
                CategoryStatCard(
                    icon: "figure.run",
                    label: "Workouts",
                    count: viewModel.categoryCounts["workouts", default: 0]
                )
                CategoryStatCard(
                    icon: "bed.double.fill",
                    label: "Sleep Sessions",
                    count: viewModel.categoryCounts["sleep", default: 0]
                )
                CategoryStatCard(
                    icon: "circle.circle",
                    label: "Activity Days",
                    count: viewModel.categoryCounts["activity_summaries", default: 0]
                )
                CategoryStatCard(
                    icon: "trash",
                    label: "Deletions",
                    count: viewModel.categoryCounts["deletes", default: 0]
                )
            }
        }
    }

    // MARK: - Recent Activity

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(DBXTypography.sectionHeader)

            if viewModel.recentEvents.isEmpty {
                Text("No sync activity yet. Tap Sync Now to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.recentEvents.prefix(5)) { event in
                        recentEventRow(event)
                        if event.id != viewModel.recentEvents.prefix(5).last?.id {
                            Divider()
                        }
                    }
                }
                .dbxCard()
            }
        }
    }

    private func recentEventRow(_ event: SyncRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconForRecordType(event.recordType))
                .foregroundStyle(DBXColors.dbxRed)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayNameForRecordType(event.recordType))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(event.recordCount) records")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(event.timestamp, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func iconForRecordType(_ type: String) -> String {
        switch type {
        case "samples": return "heart.text.square"
        case "workouts": return "figure.run"
        case "sleep": return "bed.double.fill"
        case "activity_summaries": return "circle.circle"
        case "deletes": return "trash"
        default: return "doc"
        }
    }

    private func displayNameForRecordType(_ type: String) -> String {
        switch type {
        case "samples": return "Health Samples"
        case "workouts": return "Workouts"
        case "sleep": return "Sleep Sessions"
        case "activity_summaries": return "Activity Summaries"
        case "deletes": return "Deletions"
        default: return type
        }
    }
}
