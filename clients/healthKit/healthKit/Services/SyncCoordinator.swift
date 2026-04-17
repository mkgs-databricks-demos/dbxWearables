import Foundation
import HealthKit
import OSLog

/// Orchestrates the sync cycle: query HealthKit → map to models → serialize NDJSON → POST → update anchor.
///
/// All sample types are synced concurrently via TaskGroup. Each type runs its own
/// independent query → POST → anchor-persist loop, so they make progress in parallel.
/// URLSession's per-host connection limit (~6) naturally throttles in-flight POSTs.
final class SyncCoordinator: ObservableObject {

    private let queryService: HealthKitQueryService
    private let apiService: APIService
    private let syncStateRepository: SyncStateRepository
    let syncLedger: SyncLedger

    @Published var lastSyncDate: Date?
    @Published var isSyncing = false
    @Published var lastSyncRecordCount = 0

    init(
        healthStore: HKHealthStore,
        apiService: APIService = APIService(),
        syncStateRepository: SyncStateRepository = SyncStateRepository(),
        syncLedger: SyncLedger = SyncLedger()
    ) {
        self.queryService = HealthKitQueryService(healthStore: healthStore)
        self.apiService = apiService
        self.syncStateRepository = syncStateRepository
        self.syncLedger = syncLedger
    }

    /// Run a full sync cycle for all configured HealthKit types concurrently.
    ///
    /// Each type's batch loop (query → POST → advance anchor) runs in its own task.
    /// All types execute in parallel, with URLSession's connection pool managing
    /// the number of simultaneous network requests (~6 per host).
    ///
    /// - Parameter context: `.foreground` when the user triggers sync from the UI (no time
    ///   limit, larger batches); `.background` when triggered by an observer query (~30s
    ///   execution window, smaller batches to maximize per-type progress).
    func sync(context: SyncContext = .background) async {
        await MainActor.run { isSyncing = true }
        defer { Task { @MainActor in isSyncing = false } }

        let batchSize = HealthKitConfiguration.queryBatchSize(for: context)

        let totalRecords = await withTaskGroup(of: Int.self, returning: Int.self) { group in

            // Quantity types — each runs its own batched sync loop concurrently.
            for quantityType in HealthKitConfiguration.quantityTypes {
                group.addTask {
                    await self.syncSampleType(quantityType, batchSize: batchSize, recordType: "samples") { samples in
                        HealthSampleMapper.mapQuantitySamples(samples)
                    }
                }
            }

            // Stand hour — category type, mapped as a HealthSample.
            group.addTask {
                let standHourType = HKCategoryType(.appleStandHour)
                return await self.syncSampleType(standHourType, batchSize: batchSize, recordType: "samples") { samples in
                    HealthSampleMapper.mapCategorySamples(samples)
                }
            }

            // Workouts
            group.addTask {
                let workoutType = HKSeriesType.workoutType()
                return await self.syncSampleType(workoutType, batchSize: batchSize, recordType: "workouts") { samples in
                    WorkoutMapper.mapWorkouts(samples)
                }
            }

            // Sleep — unbatched, but still runs concurrently with the other types.
            group.addTask {
                await self.syncSleep()
            }

            // Activity summaries — date-range query, runs concurrently.
            group.addTask {
                await self.syncActivitySummaries()
            }

            // Aggregate record counts as each type completes.
            var total = 0
            for await count in group {
                total += count
            }
            return total
        }

        await MainActor.run {
            lastSyncDate = Date()
            lastSyncRecordCount = totalRecords
        }
    }

    // MARK: - Per-type batched sync

    /// Generic batched sync for any anchored sample type.
    ///
    /// Loops in batches of the given `batchSize`:
    /// 1. Query up to N samples from the current anchor
    /// 2. Map HKSample objects to Encodable models via the provided transform
    /// 3. POST as NDJSON
    /// 4. Persist the new anchor
    /// 5. If the batch was full (count == limit), there may be more — loop again
    ///
    /// Each batch is an independent commit point. If a POST fails or the background
    /// window expires mid-loop, all previously completed batches are already persisted.
    ///
    /// Returns the total number of records uploaded across all batches.
    private func syncSampleType<T: Encodable>(
        _ sampleType: HKSampleType,
        batchSize: Int,
        recordType: String,
        transform: @Sendable ([HKSample]) -> [T]
    ) async -> Int {
        var currentAnchor = syncStateRepository.anchor(for: sampleType)
        var totalUploaded = 0

        while true {
            // Query the next batch
            let result: (samples: [HKSample], deletedObjects: [HKDeletedObject], newAnchor: HKQueryAnchor?)
            do {
                result = try await queryService.fetchNewSamples(
                    for: sampleType,
                    anchor: currentAnchor,
                    limit: batchSize
                )
            } catch {
                Log.sync.error("\(sampleType.identifier): query failed — \(error.localizedDescription)")
                break
            }

            let mapped = transform(result.samples)
            let deletions = result.deletedObjects.map {
                DeletionRecord(uuid: $0.uuid.uuidString, sampleType: sampleType.identifier)
            }

            if mapped.isEmpty && deletions.isEmpty {
                // No records in this batch — advance anchor and we're done for this type.
                if let newAnchor = result.newAnchor {
                    syncStateRepository.saveAnchor(newAnchor, for: sampleType)
                }
                break
            }

            // POST new/updated records.
            if !mapped.isEmpty {
                let posted = await postBatchWithRetry(
                    mapped,
                    recordType: recordType,
                    label: sampleType.identifier
                )
                guard posted else { break }
            }

            // POST deletions for this batch.
            if !deletions.isEmpty {
                let posted = await postBatchWithRetry(
                    deletions,
                    recordType: "deletes",
                    label: "\(sampleType.identifier)/deletes"
                )
                if !posted {
                    Log.sync.warning("\(sampleType.identifier): deletion POST failed, will retry next sync")
                    // Don't break — the records POST succeeded, but we won't advance
                    // the anchor so deletions are re-sent next time.
                    break
                }
            }

            // Persist anchor immediately — this batch is committed.
            if let newAnchor = result.newAnchor {
                syncStateRepository.saveAnchor(newAnchor, for: sampleType)
                currentAnchor = newAnchor
            }
            totalUploaded += mapped.count

            // If we got fewer than the limit, there's no more data for this type.
            if result.samples.count < batchSize {
                break
            }
        }

        return totalUploaded
    }

    // MARK: - Sleep (unbatched)

    /// Sleep requires all stage samples in a single query so SleepMapper can group
    /// contiguous stages into complete sessions. Batching would split a session's
    /// stages across batches, producing two broken records instead of one.
    ///
    /// This is safe because sleep volume is low — a full year is ~3-5K stage samples
    /// (~1 MB of NDJSON), well within memory and upload time budgets.
    private func syncSleep() async -> Int {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let currentAnchor = syncStateRepository.anchor(for: sleepType)

        do {
            let result = try await queryService.fetchNewSamples(
                for: sleepType,
                anchor: currentAnchor,
                limit: HKObjectQueryNoLimit
            )

            let mapped = SleepMapper.mapSleepSamples(result.samples)
            let deletions = result.deletedObjects.map {
                DeletionRecord(uuid: $0.uuid.uuidString, sampleType: sleepType.identifier)
            }

            if mapped.isEmpty && deletions.isEmpty {
                if let newAnchor = result.newAnchor {
                    syncStateRepository.saveAnchor(newAnchor, for: sleepType)
                }
                return 0
            }

            if !mapped.isEmpty {
                let posted = await postBatchWithRetry(mapped, recordType: "sleep", label: "sleep")
                guard posted else { return 0 }
            }

            if !deletions.isEmpty {
                let posted = await postBatchWithRetry(deletions, recordType: "deletes", label: "sleep/deletes")
                guard posted else { return 0 }
            }

            if let newAnchor = result.newAnchor {
                syncStateRepository.saveAnchor(newAnchor, for: sleepType)
            }
            return mapped.count
        } catch {
            Log.sync.error("Sleep query failed: \(error.localizedDescription)")
            return 0
        }
    }

    // MARK: - POST with retry

    /// Attempt to POST a batch of records. On retryable errors (429, 5xx), wait
    /// briefly and retry once. On non-retryable errors (4xx), fail immediately
    /// to avoid wasting the background execution window.
    ///
    /// Returns `true` if the POST succeeded (first attempt or retry).
    /// On success, records the payload and metadata in SyncLedger for demo inspection.
    private func postBatchWithRetry<T: Encodable>(
        _ records: [T],
        recordType: String,
        label: String
    ) async -> Bool {
        // Capture the NDJSON string before posting so we can store it in the ledger.
        let ndjsonString: String
        do {
            ndjsonString = try NDJSONSerializer.encodeToString(records)
        } catch {
            Log.sync.error("\(label): NDJSON serialization failed — \(error.localizedDescription)")
            return false
        }

        let headers = apiService.buildRequestHeaders(for: recordType)

        do {
            let response = try await apiService.postRecords(records, recordType: recordType)
            Log.sync.info("\(label): batch uploaded \(records.count) records — \(response.status)")
            await syncLedger.recordSync(
                recordType: recordType,
                recordCount: records.count,
                httpStatusCode: 200,
                ndjsonPayload: ndjsonString,
                requestHeaders: headers
            )
            return true
        } catch let error as APIError where error.isRetryable {
            Log.sync.warning("\(label): retryable error (\(error.localizedDescription)), retrying in 2s...")
            try? await Task.sleep(for: .seconds(2))

            do {
                let response = try await apiService.postRecords(records, recordType: recordType)
                Log.sync.info("\(label): retry succeeded (\(records.count) records) — \(response.status)")
                await syncLedger.recordSync(
                    recordType: recordType,
                    recordCount: records.count,
                    httpStatusCode: 200,
                    ndjsonPayload: ndjsonString,
                    requestHeaders: headers
                )
                return true
            } catch {
                Log.sync.error("\(label): retry failed (\(records.count) records) — \(error.localizedDescription)")
                return false
            }
        } catch {
            Log.sync.error("\(label): non-retryable error (\(records.count) records) — \(error.localizedDescription)")
            return false
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

            let posted = await postBatchWithRetry(mapped, recordType: "activity_summaries", label: "activity_summaries")
            guard posted else { return 0 }

            syncStateRepository.saveLastSyncDate(endDate, for: syncKey)
            return mapped.count
        } catch {
            Log.sync.error("Activity summary query failed: \(error.localizedDescription)")
            return 0
        }
    }
}
