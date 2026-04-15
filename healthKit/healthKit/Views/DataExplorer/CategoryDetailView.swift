import SwiftUI

/// Drill-down detail for a single record type showing breakdowns and stats.
struct CategoryDetailView: View {
    let summary: CategorySummary
    let breakdown: [(label: String, count: Int)]
    let stats: SyncStats

    var body: some View {
        List {
            // Overview section
            Section("Overview") {
                HStack {
                    Text("Total Records Sent")
                    Spacer()
                    Text("\(summary.totalCount)")
                        .fontWeight(.semibold)
                        .foregroundStyle(DBXColors.dbxRed)
                }

                if let lastSync = summary.lastSync {
                    HStack {
                        Text("Last Sent")
                        Spacer()
                        Text(lastSync, style: .relative)
                            .foregroundStyle(.secondary)
                        + Text(" ago")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Type-specific sections
            switch summary.recordType {
            case "samples":
                samplesBreakdownSection
            case "workouts":
                workoutsBreakdownSection
            case "sleep":
                sleepDetailSection
            case "activity_summaries":
                activityDetailSection
            case "deletes":
                deletesBreakdownSection
            default:
                EmptyView()
            }
        }
        .navigationTitle(summary.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Samples

    @ViewBuilder
    private var samplesBreakdownSection: some View {
        if breakdown.isEmpty {
            Section("By Type") {
                Text("No breakdown data available")
                    .foregroundStyle(.secondary)
            }
        } else {
            Section("By HealthKit Type (\(breakdown.count) types)") {
                ForEach(breakdown, id: \.label) { item in
                    HStack {
                        Text(item.label)
                            .font(.subheadline)
                        Spacer()
                        Text("\(item.count)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Workouts

    @ViewBuilder
    private var workoutsBreakdownSection: some View {
        if breakdown.isEmpty {
            Section("By Activity Type") {
                Text("No breakdown data available")
                    .foregroundStyle(.secondary)
            }
        } else {
            Section("By Activity Type (\(breakdown.count) types)") {
                ForEach(breakdown, id: \.label) { item in
                    HStack {
                        Text(item.label.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.subheadline)
                        Spacer()
                        Text("\(item.count)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Sleep

    private var sleepDetailSection: some View {
        Section("Summary") {
            HStack {
                Text("Sessions Sent")
                Spacer()
                Text("\(stats.sleepSessionCount)")
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Activity Summaries

    private var activityDetailSection: some View {
        Section("Summary") {
            HStack {
                Text("Days Sent")
                Spacer()
                Text("\(stats.activitySummaryDayCount)")
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Deletes

    @ViewBuilder
    private var deletesBreakdownSection: some View {
        if breakdown.isEmpty {
            Section("By Sample Type") {
                Text("No breakdown data available")
                    .foregroundStyle(.secondary)
            }
        } else {
            Section("By Sample Type (\(breakdown.count) types)") {
                ForEach(breakdown, id: \.label) { item in
                    HStack {
                        Text(item.label)
                            .font(.subheadline)
                        Spacer()
                        Text("\(item.count)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
