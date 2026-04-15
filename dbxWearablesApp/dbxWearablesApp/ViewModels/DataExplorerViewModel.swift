import UIKit

/// Drives the Data Explorer tab — per-category breakdowns and aggregation stats.
@MainActor
final class DataExplorerViewModel: ObservableObject {

    @Published var stats: SyncStats = .empty

    private var appDelegate: AppDelegate {
        UIApplication.shared.delegate as! AppDelegate
    }

    func loadStats() async {
        let ledger = appDelegate.syncCoordinator.syncLedger
        stats = await ledger.getStats()
    }

    /// Summary rows for the top-level list.
    var categorySummaries: [CategorySummary] {
        let types = ["samples", "workouts", "sleep", "activity_summaries", "deletes"]
        return types.map { type in
            CategorySummary(
                recordType: type,
                displayName: displayName(for: type),
                icon: icon(for: type),
                totalCount: stats.totalRecordsSent[type, default: 0],
                lastSync: stats.lastSyncTimestamp[type]
            )
        }
    }

    /// Per-type breakdown for the detail view.
    func breakdown(for recordType: String) -> [(label: String, count: Int)] {
        let dict: [String: Int]
        switch recordType {
        case "samples":
            dict = stats.sampleBreakdown
        case "workouts":
            dict = stats.workoutBreakdown
        case "deletes":
            dict = stats.deleteBreakdown
        default:
            return []
        }
        return dict
            .sorted { $0.value > $1.value }
            .map { (label: formatTypeIdentifier($0.key), count: $0.value) }
    }

    // MARK: - Helpers

    private func displayName(for type: String) -> String {
        switch type {
        case "samples": return "Health Samples"
        case "workouts": return "Workouts"
        case "sleep": return "Sleep Sessions"
        case "activity_summaries": return "Activity Summaries"
        case "deletes": return "Deletions"
        default: return type
        }
    }

    private func icon(for type: String) -> String {
        switch type {
        case "samples": return "heart.text.square"
        case "workouts": return "figure.run"
        case "sleep": return "bed.double.fill"
        case "activity_summaries": return "circle.circle"
        case "deletes": return "trash"
        default: return "doc"
        }
    }

    /// Convert HK type identifiers to readable labels.
    /// e.g. "HKQuantityTypeIdentifierHeartRate" → "Heart Rate"
    private func formatTypeIdentifier(_ identifier: String) -> String {
        var name = identifier
        // Strip common prefixes
        let prefixes = [
            "HKQuantityTypeIdentifier",
            "HKCategoryTypeIdentifier",
            "HKCorrelationTypeIdentifier",
        ]
        for prefix in prefixes {
            if name.hasPrefix(prefix) {
                name = String(name.dropFirst(prefix.count))
                break
            }
        }
        // Insert spaces before uppercase letters for camelCase → Title Case
        var result = ""
        for char in name {
            if char.isUppercase && !result.isEmpty {
                result.append(" ")
            }
            result.append(char)
        }
        return result.isEmpty ? identifier : result
    }
}

/// Summary data for a single record type row in the Data Explorer.
struct CategorySummary: Identifiable {
    var id: String { recordType }
    let recordType: String
    let displayName: String
    let icon: String
    let totalCount: Int
    let lastSync: Date?
}
