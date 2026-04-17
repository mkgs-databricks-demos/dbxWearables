package com.dbxwearables.android.domain.mapper

import androidx.health.connect.client.records.ExerciseSessionRecord
import com.dbxwearables.android.data.model.WorkoutRecord
import com.dbxwearables.android.util.DateFormatters
import java.time.Duration

/**
 * Maps Health Connect [ExerciseSessionRecord] instances to the app's
 * [WorkoutRecord] data model for NDJSON serialization.
 */
object WorkoutMapper {

    /**
     * Converts a list of [ExerciseSessionRecord] objects into [WorkoutRecord] instances.
     */
    fun mapWorkouts(records: List<ExerciseSessionRecord>): List<WorkoutRecord> {
        return records.map { record -> mapWorkout(record) }
    }

    private fun mapWorkout(record: ExerciseSessionRecord): WorkoutRecord {
        val durationSeconds = Duration.between(record.startTime, record.endTime).toMillis() / 1000.0

        return WorkoutRecord(
            id = record.metadata.id,
            exerciseType = ExerciseTypeMapper.fromCode(record.exerciseType),
            exerciseTypeCode = record.exerciseType,
            title = record.title,
            startTime = DateFormatters.formatInstant(record.startTime),
            endTime = DateFormatters.formatInstant(record.endTime),
            startZoneOffset = DateFormatters.formatZoneOffset(record.startZoneOffset),
            endZoneOffset = DateFormatters.formatZoneOffset(record.endZoneOffset),
            durationSeconds = durationSeconds,
            dataOrigin = record.metadata.dataOrigin.packageName,
            lastModifiedTime = DateFormatters.formatInstant(record.metadata.lastModifiedTime),
            notes = record.notes
        )
    }
}
