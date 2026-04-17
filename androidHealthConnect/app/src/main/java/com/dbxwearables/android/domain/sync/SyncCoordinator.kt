package com.dbxwearables.android.domain.sync

import android.util.Log
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.BasalMetabolicRateRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord
import androidx.health.connect.client.records.OxygenSaturationRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.Vo2MaxRecord
import com.dbxwearables.android.data.model.DeletionRecord
import com.dbxwearables.android.data.remote.APIError
import com.dbxwearables.android.data.remote.APIService
import com.dbxwearables.android.data.repository.SyncLedger
import com.dbxwearables.android.data.repository.SyncStateRepository
import com.dbxwearables.android.domain.mapper.DailySummaryMapper
import com.dbxwearables.android.domain.mapper.HealthSampleMapper
import com.dbxwearables.android.domain.mapper.SleepMapper
import com.dbxwearables.android.domain.mapper.WorkoutMapper
import com.dbxwearables.android.health.HealthConnectConfiguration
import com.dbxwearables.android.health.HealthConnectQueryService
import com.dbxwearables.android.util.DateFormatters
import com.dbxwearables.android.util.NDJSONSerializer
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.reflect.KClass

private const val TAG = "SyncCoordinator"

@Singleton
class SyncCoordinator @Inject constructor(
    private val queryService: HealthConnectQueryService,
    private val apiService: APIService,
    private val syncStateRepo: SyncStateRepository,
    private val syncLedger: SyncLedger,
) {
    private val _isSyncing = MutableStateFlow(false)
    val isSyncing: StateFlow<Boolean> = _isSyncing.asStateFlow()

    private val _lastSyncDate = MutableStateFlow<Instant?>(null)
    val lastSyncDate: StateFlow<Instant?> = _lastSyncDate.asStateFlow()

    private val batchSize = HealthConnectConfiguration.BATCH_SIZE_FOREGROUND

    suspend fun syncAll() {
        if (_isSyncing.value) return
        _isSyncing.value = true
        try {
            coroutineScope {
                val sampleJobs = HealthConnectConfiguration.sampleRecordTypes.map { type ->
                    async { syncRecordType(type) }
                }
                val workoutJob = async { syncWorkouts() }
                val sleepJob = async { syncSleep() }
                val summaryJob = async { syncDailySummaries() }

                sampleJobs.forEach { it.await() }
                workoutJob.await()
                sleepJob.await()
                summaryJob.await()
            }
            _lastSyncDate.value = Instant.now()
        } catch (e: Exception) {
            Log.e(TAG, "Sync failed", e)
        } finally {
            _isSyncing.value = false
        }
    }

    private suspend fun syncRecordType(recordType: KClass<out Record>) {
        val typeName = recordType.simpleName ?: return
        try {
            var token = syncStateRepo.getChangeToken(typeName)
            if (token == null) {
                token = queryService.getChangesToken(recordType)
                syncStateRepo.saveChangeToken(typeName, token)
                return
            }

            val result = queryService.getChanges(token)

            if (result.upsertedRecords.isNotEmpty()) {
                val batches = result.upsertedRecords.chunked(batchSize)
                for (batch in batches) {
                    val samples = HealthSampleMapper.mapRecords(batch)
                    if (samples.isNotEmpty()) {
                        val ndjson = NDJSONSerializer.encodeToString(samples)
                        postWithRetry(ndjson, "samples", samples.size)
                    }
                }
            }

            if (result.deletedIds.isNotEmpty()) {
                val deletions = result.deletedIds.map { id ->
                    DeletionRecord(
                        id = id,
                        recordType = typeName,
                        deletedTime = DateFormatters.formatInstant(Instant.now())
                    )
                }
                val ndjson = NDJSONSerializer.encodeToString(deletions)
                postWithRetry(ndjson, "deletes", deletions.size)
            }

            syncStateRepo.saveChangeToken(typeName, result.nextToken)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to sync $typeName", e)
            if (isTokenExpired(e)) {
                syncStateRepo.clearChangeToken(typeName)
            }
        }
    }

    private suspend fun syncWorkouts() {
        val typeName = ExerciseSessionRecord::class.simpleName ?: return
        try {
            var token = syncStateRepo.getChangeToken(typeName)
            if (token == null) {
                token = queryService.getChangesToken(ExerciseSessionRecord::class)
                syncStateRepo.saveChangeToken(typeName, token)
                return
            }

            val result = queryService.getChanges(token)

            if (result.upsertedRecords.isNotEmpty()) {
                val sessions = result.upsertedRecords.filterIsInstance<ExerciseSessionRecord>()
                val workouts = WorkoutMapper.mapWorkouts(sessions)
                if (workouts.isNotEmpty()) {
                    val ndjson = NDJSONSerializer.encodeToString(workouts)
                    postWithRetry(ndjson, "workouts", workouts.size)
                }
            }

            if (result.deletedIds.isNotEmpty()) {
                val deletions = result.deletedIds.map { id ->
                    DeletionRecord(id = id, recordType = typeName, deletedTime = DateFormatters.formatInstant(Instant.now()))
                }
                val ndjson = NDJSONSerializer.encodeToString(deletions)
                postWithRetry(ndjson, "deletes", deletions.size)
            }

            syncStateRepo.saveChangeToken(typeName, result.nextToken)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to sync workouts", e)
            if (isTokenExpired(e)) syncStateRepo.clearChangeToken(typeName)
        }
    }

    private suspend fun syncSleep() {
        val typeName = SleepSessionRecord::class.simpleName ?: return
        try {
            var token = syncStateRepo.getChangeToken(typeName)
            if (token == null) {
                token = queryService.getChangesToken(SleepSessionRecord::class)
                syncStateRepo.saveChangeToken(typeName, token)
                return
            }

            val result = queryService.getChanges(token)

            if (result.upsertedRecords.isNotEmpty()) {
                val sessions = result.upsertedRecords.filterIsInstance<SleepSessionRecord>()
                val sleepRecords = SleepMapper.mapSleepSessions(sessions)
                if (sleepRecords.isNotEmpty()) {
                    val ndjson = NDJSONSerializer.encodeToString(sleepRecords)
                    postWithRetry(ndjson, "sleep", sleepRecords.size)
                }
            }

            if (result.deletedIds.isNotEmpty()) {
                val deletions = result.deletedIds.map { id ->
                    DeletionRecord(id = id, recordType = typeName, deletedTime = DateFormatters.formatInstant(Instant.now()))
                }
                val ndjson = NDJSONSerializer.encodeToString(deletions)
                postWithRetry(ndjson, "deletes", deletions.size)
            }

            syncStateRepo.saveChangeToken(typeName, result.nextToken)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to sync sleep", e)
            if (isTokenExpired(e)) syncStateRepo.clearChangeToken(typeName)
        }
    }

    private suspend fun syncDailySummaries() {
        try {
            val lastSync = syncStateRepo.getLastSyncDate("daily_summaries")
            val startDate = lastSync?.atZone(ZoneId.systemDefault())?.toLocalDate()
                ?: LocalDate.now().minusDays(7)
            val today = LocalDate.now()
            val zone = ZoneId.systemDefault()
            val timezone = zone.id

            var date = startDate
            val summaries = mutableListOf<com.dbxwearables.android.data.model.DailySummary>()

            while (!date.isAfter(today)) {
                val dayStart = date.atStartOfDay(zone).toInstant()
                val dayEnd = date.plusDays(1).atStartOfDay(zone).toInstant()

                val steps = queryService.aggregateSteps(dayStart, dayEnd)
                val calories = queryService.aggregateActiveCalories(dayStart, dayEnd)
                val distance = queryService.aggregateDistance(dayStart, dayEnd)

                summaries.add(
                    DailySummaryMapper.buildSummary(
                        date = date,
                        timezone = timezone,
                        steps = steps,
                        activeCaloriesKcal = calories,
                        distanceMeters = distance,
                        exerciseMinutes = null
                    )
                )
                date = date.plusDays(1)
            }

            if (summaries.isNotEmpty()) {
                val ndjson = NDJSONSerializer.encodeToString(summaries)
                postWithRetry(ndjson, "daily_summaries", summaries.size)
            }

            syncStateRepo.saveLastSyncDate("daily_summaries", Instant.now())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to sync daily summaries", e)
        }
    }

    private suspend fun postWithRetry(ndjson: String, recordType: String, count: Int) {
        val headers = apiService.buildRequestHeaders(recordType)
        try {
            val response = apiService.postRecords(ndjson, recordType)
            syncLedger.recordSync(recordType, count, 200, true, ndjson, headers)
        } catch (e: APIError.HttpError) {
            syncLedger.recordSync(recordType, count, e.statusCode, false, ndjson, headers)
            if (e.isRetryable) {
                delay(2000)
                try {
                    apiService.postRecords(ndjson, recordType)
                    syncLedger.recordSync(recordType, count, 200, true, ndjson, headers)
                } catch (retryError: Exception) {
                    Log.e(TAG, "Retry failed for $recordType", retryError)
                }
            }
        } catch (e: Exception) {
            syncLedger.recordSync(recordType, count, 0, false, ndjson, headers)
            Log.e(TAG, "POST failed for $recordType", e)
        }
    }

    private fun isTokenExpired(e: Exception): Boolean {
        return e.javaClass.simpleName.contains("ChangesTokenExpired", ignoreCase = true)
    }
}
