package com.dbxwearables.android.domain.mapper

import androidx.health.connect.client.records.SleepSessionRecord
import com.dbxwearables.android.data.model.SleepRecord
import com.dbxwearables.android.data.model.SleepStage
import com.dbxwearables.android.util.DateFormatters
import java.time.Duration

/**
 * Maps Health Connect [SleepSessionRecord] instances to the app's
 * [SleepRecord] data model for NDJSON serialization.
 */
object SleepMapper {

    /**
     * Converts a list of [SleepSessionRecord] objects into [SleepRecord] instances.
     */
    fun mapSleepSessions(records: List<SleepSessionRecord>): List<SleepRecord> {
        return records.map { record -> mapSleepSession(record) }
    }

    private fun mapSleepSession(record: SleepSessionRecord): SleepRecord {
        val durationSeconds = Duration.between(record.startTime, record.endTime).toMillis() / 1000.0

        val stages = record.stages.map { stage ->
            SleepStage(
                stage = stageNameFromCode(stage.stage),
                stageCode = stage.stage,
                startTime = DateFormatters.formatInstant(stage.startTime),
                endTime = DateFormatters.formatInstant(stage.endTime)
            )
        }

        return SleepRecord(
            id = record.metadata.id,
            startTime = DateFormatters.formatInstant(record.startTime),
            endTime = DateFormatters.formatInstant(record.endTime),
            startZoneOffset = DateFormatters.formatZoneOffset(record.startZoneOffset),
            endZoneOffset = DateFormatters.formatZoneOffset(record.endZoneOffset),
            durationSeconds = durationSeconds,
            dataOrigin = record.metadata.dataOrigin.packageName,
            lastModifiedTime = DateFormatters.formatInstant(record.metadata.lastModifiedTime),
            title = record.title,
            notes = record.notes,
            stages = stages
        )
    }

    private fun stageNameFromCode(code: Int): String {
        return when (code) {
            SleepSessionRecord.STAGE_TYPE_UNKNOWN -> "unknown"
            SleepSessionRecord.STAGE_TYPE_AWAKE -> "awake"
            SleepSessionRecord.STAGE_TYPE_SLEEPING -> "sleeping"
            SleepSessionRecord.STAGE_TYPE_OUT_OF_BED -> "out_of_bed"
            SleepSessionRecord.STAGE_TYPE_LIGHT -> "light"
            SleepSessionRecord.STAGE_TYPE_DEEP -> "deep"
            SleepSessionRecord.STAGE_TYPE_REM -> "rem"
            else -> "unknown_$code"
        }
    }
}
