import Foundation
import HealthKit
import OSLog

/// Orchestrates the sync cycle: query HealthKit → map to models → serialize NDJSON → POST → update anchor.
///
/// Each sample type is synced independently with its own query → POST → anchor-persist cycle.
/// This means each type makes independent progress within a background execution window (~30s).
/// If time runs out after syncing 6 of 14 types, those 6 are done — the next wake picks up
/// the remaining 8 from their last anchors.
final class SyncCoordinator: ObservableObject {

    private let queryService: HealthKitQueryService
    private let apiService: APIService
    private let syncStateRepository: SyncStateRepository

    @Published var lastSyncDate: Date?
    @Published var isSyncing = false
    @Published var lastSyncRecordCount = 0

    init(
        healthStore: HKHealthStore,
        apiService: APIService = APIService(),
        syncStateRepository: SyncStateRepository = SyncStateRepository()
    ) {
        self.queryService = HealthKitQueryService(healthStore: healthStore)
        self.apiService = apiService
        self.syncStateRepository = syncStateRepository
    }

    /// Run a full sync cycle for all configured HealthKit types.
    /// Each type is queried, posted, and its anchor persisted independently.
    func sync() async {
        await MainActor.run { isSyncing = true }
        defer { Task { @MainActor in isSyncing = false } }

        var totalRecords = 0

        // Quantity types — one POST per type (stepCount, heartRate, etc.)
        for quantityType in HealthKitConfiguration.quantityTypes {
            totalRecords += await syncSampleType(quantityType, recordType: "samples") { samples in
                HealthSampleMapper.mapQuantitySamples(samples)
            }
        }

        // Stand hour — category type, mapped as a HealthSample
        let standHourType = HKCategoryType(.appleStandHour)
        totalRecords += await syncSampleType(standHourType, recordType: "samples") { samples in
            HealthSampleMapper.mapCategorySamples(samples)
        }

        // Workouts
        let workoutType = HKSeriesType.workoutType()
        totalRecords += await syncSampleType(workoutType, recordType: "workouts") { samples in
            WorkoutMapper.mapWorkouts(samples)
        }

        // Sleep — stage samples grouped into sessions
        let sleepType = HKCategoryType(.sleepAnalysis)
        totalRecords += await syncSampleType(sleepType, recordType: "sleep") { samples in
            SleepMapper.mapSleepSamples(samples)
        }

        // Activity summaries — date-range query (no anchored query support)
        totalRecords += await syncActivitySummaries()

        await MainActor.run {
            lastSyncDate = Date()
            lastSyncRecordCount = totalRecords
        }
    }

    // MARK: - Per-type sync

    /// Generic sync for any anchored sample type.
    /// 1. Load persisted anchor (nil on first sync → fetches all history)
    /// 2. Run anchored query to get new samples
    /// 3. Map HKSample objects to Encodable models via the provided transform
    /// 4. POST as NDJSON
    /// 5. Persist the new anchor on success
    ///
    /// Returns the number of records uploaded.
    private func syncSampleType<T: Encodable>(
        _ sampleType: HKSampleType,
        recordType: String,
        transform: ([HKSample]) -> [T]
    ) async -> Int {
        let currentAnchor = syncStateRepository.anchor(for: sampleType)

        let result: (samples: [HKSample], deletedObjects: [HKDeletedObject], newAnchor: HKQueryAnchor?)
        do {
            result = try await queryService.fetchNewSamples(for: sampleType, anchor: currentAnchor)
        } catch {
            Log.sync.error("Query failed for \(sampleType.identifier): \(error.localizedDescription)")
            return 0
        }

        let mapped = transform(result.samples)
        guard !mapped.isEmpty else {
            // Still persist the anchor even with no records — the query succeeded
            // and advancing the anchor avoids re-scanning the same empty range.
            if let newAnchor = result.newAnchor {
                syncStateRepository.saveAnchor(newAnchor, for: sampleType)
            }
            return 0
        }

        do {
            let response = try await apiService.postRecords(mapped, recordType: recordType)
            Log.sync.info("\(sampleType.identifier): uploaded \(mapped.count) records — \(response.status)")

            if let newAnchor = result.newAnchor {
                syncStateRepository.saveAnchor(newAnchor, for: sampleType)
            }
            return mapped.count
        } catch {
            Log.sync.error("\(sampleType.identifier): upload failed (\(mapped.count) records) — \(error.localizedDescription)")
            // Anchor NOT persisted — next sync re-fetches these records.
            return 0
        }
    }

    // MARK: - Activity summaries (rings)

    /// Fetch activity summaries since the last sync date. Unlike sample types, activity
    /// summaries don't support anchored queries — we track the last sync date instead.
    private func syncActivitySummaries() async -> Int {
        let syncKey = "activity_summaries"
        let startDate = syncStateRepository.lastSyncDate(for: syncKey)
            ?? Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let endDate = Date()

        do {
            let summaries = try await queryService.fetchActivitySummaries(from: startDate, to: endDate)
            let mapped = ActivitySummaryMapper.mapSummaries(summaries)

            guard !mapped.isEmpty else { return 0 }

            let response = try await apiService.postRecords(mapped, recordType: "activity_summaries")
            Log.sync.info("Activity summaries: uploaded \(mapped.count) records — \(response.status)")

            syncStateRepository.saveLastSyncDate(endDate, for: syncKey)
            return mapped.count
        } catch {
            Log.sync.error("Activity summary sync failed: \(error.localizedDescription)")
            return 0
        }
    }
}
