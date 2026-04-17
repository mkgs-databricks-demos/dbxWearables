package com.dbxwearables.android.health

import androidx.health.connect.client.changes.Change
import androidx.health.connect.client.changes.DeletionChange
import androidx.health.connect.client.changes.UpsertionChange
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
import androidx.health.connect.client.request.ChangesTokenRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Instant
import java.time.LocalDate
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.reflect.KClass

data class ChangeResult(
    val upsertedRecords: List<Record>,
    val deletedIds: List<String>,
    val nextToken: String
)

@Singleton
class HealthConnectQueryService @Inject constructor(
    private val healthConnectManager: HealthConnectManager
) {
    private val client get() = healthConnectManager.client

    suspend fun getChangesToken(recordType: KClass<out Record>): String {
        val response = client.getChangesToken(
            ChangesTokenRequest(recordTypes = setOf(recordType))
        )
        return response
    }

    suspend fun getChanges(token: String): ChangeResult {
        val upserted = mutableListOf<Record>()
        val deleted = mutableListOf<String>()
        var currentToken = token
        var hasMore = true

        while (hasMore) {
            val response = client.getChanges(currentToken)
            for (change in response.changes) {
                when (change) {
                    is UpsertionChange -> upserted.add(change.record)
                    is DeletionChange -> deleted.add(change.deletedRecordId)
                }
            }
            currentToken = response.nextChangesToken
            hasMore = response.hasMore
        }

        return ChangeResult(
            upsertedRecords = upserted,
            deletedIds = deleted,
            nextToken = currentToken
        )
    }

    suspend fun readSleepSessions(
        startTime: Instant,
        endTime: Instant = Instant.now()
    ): List<SleepSessionRecord> {
        val response = client.readRecords(
            ReadRecordsRequest(
                recordType = SleepSessionRecord::class,
                timeRangeFilter = TimeRangeFilter.between(startTime, endTime)
            )
        )
        return response.records
    }

    suspend fun readExerciseSessions(
        startTime: Instant,
        endTime: Instant = Instant.now()
    ): List<ExerciseSessionRecord> {
        val response = client.readRecords(
            ReadRecordsRequest(
                recordType = ExerciseSessionRecord::class,
                timeRangeFilter = TimeRangeFilter.between(startTime, endTime)
            )
        )
        return response.records
    }

    suspend fun aggregateSteps(startTime: Instant, endTime: Instant): Long {
        val response = client.aggregate(
            androidx.health.connect.client.request.AggregateRequest(
                metrics = setOf(StepsRecord.COUNT_TOTAL),
                timeRangeFilter = TimeRangeFilter.between(startTime, endTime)
            )
        )
        return response[StepsRecord.COUNT_TOTAL] ?: 0L
    }

    suspend fun aggregateActiveCalories(startTime: Instant, endTime: Instant): Double {
        val response = client.aggregate(
            androidx.health.connect.client.request.AggregateRequest(
                metrics = setOf(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL),
                timeRangeFilter = TimeRangeFilter.between(startTime, endTime)
            )
        )
        return response[ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL]
            ?.inKilocalories ?: 0.0
    }

    suspend fun aggregateDistance(startTime: Instant, endTime: Instant): Double {
        val response = client.aggregate(
            androidx.health.connect.client.request.AggregateRequest(
                metrics = setOf(DistanceRecord.DISTANCE_TOTAL),
                timeRangeFilter = TimeRangeFilter.between(startTime, endTime)
            )
        )
        return response[DistanceRecord.DISTANCE_TOTAL]?.inMeters ?: 0.0
    }
}
