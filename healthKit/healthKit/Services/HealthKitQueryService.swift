import Foundation
import HealthKit

/// Executes HealthKit queries (anchored object, statistics, activity summary).
final class HealthKitQueryService {

    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
    }

    /// Fetch new samples since the given anchor using an anchored object query.
    ///
    /// - Parameters:
    ///   - sampleType: The HealthKit sample type to query.
    ///   - anchor: The anchor from the previous query (nil fetches from the beginning).
    ///   - limit: Maximum number of samples to return. When the result count equals the limit,
    ///     there may be more data — call again with the returned anchor to get the next batch.
    ///     Defaults to `HealthKitConfiguration.queryBatchSize`.
    ///
    /// - Returns: The new/updated samples, deleted objects, and an anchor for the next query.
    func fetchNewSamples(
        for sampleType: HKSampleType,
        anchor: HKQueryAnchor?,
        limit: Int = HealthKitConfiguration.queryBatchSize
    ) async throws -> (samples: [HKSample], deletedObjects: [HKDeletedObject], newAnchor: HKQueryAnchor?) {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: sampleType,
                predicate: nil,
                anchor: anchor,
                limit: limit
            ) { _, added, deleted, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (added ?? [], deleted ?? [], newAnchor))
                }
            }
            healthStore.execute(query)
        }
    }

    /// Fetch activity summaries for a date range.
    func fetchActivitySummaries(
        from startDate: Date,
        to endDate: Date
    ) async throws -> [HKActivitySummary] {
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
        let endComponents = calendar.dateComponents([.year, .month, .day], from: endDate)

        let predicate = HKQuery.predicate(
            forActivitySummariesBetweenStart: startComponents,
            end: endComponents
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: summaries ?? [])
                }
            }
            healthStore.execute(query)
        }
    }
}
