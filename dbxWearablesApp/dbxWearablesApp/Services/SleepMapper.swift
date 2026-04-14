import Foundation
import HealthKit

/// Maps HKCategorySample (sleepAnalysis) entries into grouped SleepRecord models.
///
/// HealthKit stores sleep as individual category samples — one per stage interval
/// (asleepCore, asleepDeep, asleepREM, awake, inBed). This mapper groups contiguous
/// samples into cohesive sleep sessions by detecting time gaps between them.
enum SleepMapper {

    /// Maximum gap between consecutive sleep samples before they're treated as
    /// separate sessions. 30 minutes covers brief interruptions (bathroom, etc.)
    /// without merging distinct sleep periods (e.g., a nap and overnight sleep).
    private static let sessionGapThreshold: TimeInterval = 30 * 60

    /// Convert a batch of HKSample results into SleepRecord models.
    /// Samples are sorted by start date, grouped into sessions, then each
    /// session's individual stages are preserved in order.
    static func mapSleepSamples(_ samples: [HKSample]) -> [SleepRecord] {
        let categorySamples = samples
            .compactMap { $0 as? HKCategorySample }
            .filter { $0.categoryType.identifier == HKCategoryTypeIdentifier.sleepAnalysis.rawValue }
            .sorted { $0.startDate < $1.startDate }

        guard !categorySamples.isEmpty else { return [] }

        return groupIntoSessions(categorySamples).map(buildRecord)
    }

    /// Group sorted sleep samples into sessions by detecting gaps.
    private static func groupIntoSessions(_ sorted: [HKCategorySample]) -> [[HKCategorySample]] {
        var sessions: [[HKCategorySample]] = []
        var current: [HKCategorySample] = [sorted[0]]

        for i in 1..<sorted.count {
            let previous = current.last!
            let gap = sorted[i].startDate.timeIntervalSince(previous.endDate)

            if gap > sessionGapThreshold {
                sessions.append(current)
                current = [sorted[i]]
            } else {
                current.append(sorted[i])
            }
        }
        sessions.append(current)

        return sessions
    }

    /// Build a SleepRecord from a group of samples belonging to one session.
    private static func buildRecord(from sessionSamples: [HKCategorySample]) -> SleepRecord {
        let sessionStart = sessionSamples.map(\.startDate).min()!
        let sessionEnd = sessionSamples.map(\.endDate).max()!

        let stages = sessionSamples.map { sample in
            SleepStage(
                uuid: sample.uuid.uuidString,
                stage: sleepStageName(for: sample.value),
                startDate: sample.startDate,
                endDate: sample.endDate
            )
        }

        return SleepRecord(
            startDate: sessionStart,
            endDate: sessionEnd,
            stages: stages
        )
    }

    /// Map HKCategoryValueSleepAnalysis integer values to readable stage names.
    private static func sleepStageName(for value: Int) -> String {
        switch value {
        case HKCategoryValueSleepAnalysis.inBed.rawValue:
            return "inBed"
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
            return "asleepUnspecified"
        case HKCategoryValueSleepAnalysis.awake.rawValue:
            return "awake"
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
            return "asleepCore"
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
            return "asleepDeep"
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            return "asleepREM"
        default:
            return "unknown_\(value)"
        }
    }
}
