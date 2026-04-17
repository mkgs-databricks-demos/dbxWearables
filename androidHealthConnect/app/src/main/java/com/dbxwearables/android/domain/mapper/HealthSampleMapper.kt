package com.dbxwearables.android.domain.mapper

import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.BasalMetabolicRateRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord
import androidx.health.connect.client.records.OxygenSaturationRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.Vo2MaxRecord
import com.dbxwearables.android.data.model.HealthSample
import com.dbxwearables.android.util.DateFormatters

/**
 * Maps various Health Connect record types to the app's [HealthSample] data model
 * for NDJSON serialization.
 *
 * HeartRateRecord is flattened: each sample within the record produces a separate
 * HealthSample with an indexed id suffix.
 */
object HealthSampleMapper {

    /**
     * Converts a heterogeneous list of Health Connect [Record] objects into
     * a list of [HealthSample] instances. Unknown record types are silently skipped.
     */
    fun mapRecords(records: List<Record>): List<HealthSample> {
        return records.flatMap { record -> mapRecord(record) }
    }

    private fun mapRecord(record: Record): List<HealthSample> {
        return when (record) {
            is StepsRecord -> listOf(
                HealthSample(
                    id = record.metadata.id,
                    type = "StepsRecord",
                    value = record.count.toDouble(),
                    unit = "steps",
                    startTime = DateFormatters.formatInstant(record.startTime),
                    endTime = DateFormatters.formatInstant(record.endTime),
                    startZoneOffset = DateFormatters.formatZoneOffset(record.startZoneOffset),
                    endZoneOffset = DateFormatters.formatZoneOffset(record.endZoneOffset),
                    dataOrigin = record.metadata.dataOrigin.packageName,
                    lastModifiedTime = DateFormatters.formatInstant(record.metadata.lastModifiedTime)
                )
            )

            is DistanceRecord -> listOf(
                HealthSample(
                    id = record.metadata.id,
                    type = "DistanceRecord",
                    value = record.distance.inMeters,
                    unit = "meters",
                    startTime = DateFormatters.formatInstant(record.startTime),
                    endTime = DateFormatters.formatInstant(record.endTime),
                    startZoneOffset = DateFormatters.formatZoneOffset(record.startZoneOffset),
                    endZoneOffset = DateFormatters.formatZoneOffset(record.endZoneOffset),
                    dataOrigin = record.metadata.dataOrigin.packageName,
                    lastModifiedTime = DateFormatters.formatInstant(record.metadata.lastModifiedTime)
                )
            )

            is ActiveCaloriesBurnedRecord -> listOf(
                HealthSample(
                    id = record.metadata.id,
                    type = "ActiveCaloriesBurnedRecord",
                    value = record.energy.inKilocalories,
                    unit = "kcal",
                    startTime = DateFormatters.formatInstant(record.startTime),
                    endTime = DateFormatters.formatInstant(record.endTime),
                    startZoneOffset = DateFormatters.formatZoneOffset(record.startZoneOffset),
                    endZoneOffset = DateFormatters.formatZoneOffset(record.endZoneOffset),
                    dataOrigin = record.metadata.dataOrigin.packageName,
                    lastModifiedTime = DateFormatters.formatInstant(record.metadata.lastModifiedTime)
                )
            )

            is BasalMetabolicRateRecord -> listOf(
                HealthSample(
                    id = record.metadata.id,
                    type = "BasalMetabolicRateRecord",
                    value = record.basalMetabolicRate.inKilocaloriesPerDay,
                    unit = "kcal_per_day",
                    startTime = DateFormatters.formatInstant(record.time),
                    endTime = DateFormatters.formatInstant(record.time),
                    startZoneOffset = DateFormatters.formatZoneOffset(record.zoneOffset),
                    endZoneOffset = DateFormatters.formatZoneOffset(record.zoneOffset),
                    dataOrigin = record.metadata.dataOrigin.packageName,
                    lastModifiedTime = DateFormatters.formatInstant(record.metadata.lastModifiedTime)
                )
            )

            is HeartRateRecord -> record.samples.mapIndexed { index, sample ->
                HealthSample(
                    id = "${record.metadata.id}-$index",
                    type = "HeartRateRecord",
                    value = sample.beatsPerMinute.toDouble(),
                    unit = "bpm",
                    startTime = DateFormatters.formatInstant(sample.time),
                    endTime = DateFormatters.formatInstant(sample.time),
                    startZoneOffset = DateFormatters.formatZoneOffset(record.startZoneOffset),
                    endZoneOffset = DateFormatters.formatZoneOffset(record.endZoneOffset),
                    dataOrigin = record.metadata.dataOrigin.packageName,
                    lastModifiedTime = DateFormatters.formatInstant(record.metadata.lastModifiedTime)
                )
            }

            is RestingHeartRateRecord -> listOf(
                HealthSample(
                    id = record.metadata.id,
                    type = "RestingHeartRateRecord",
                    value = record.beatsPerMinute.toDouble(),
                    unit = "bpm",
                    startTime = DateFormatters.formatInstant(record.time),
                    endTime = DateFormatters.formatInstant(record.time),
                    startZoneOffset = DateFormatters.formatZoneOffset(record.zoneOffset),
                    endZoneOffset = DateFormatters.formatZoneOffset(record.zoneOffset),
                    dataOrigin = record.metadata.dataOrigin.packageName,
                    lastModifiedTime = DateFormatters.formatInstant(record.metadata.lastModifiedTime)
                )
            )

            is HeartRateVariabilityRmssdRecord -> listOf(
                HealthSample(
                    id = record.metadata.id,
                    type = "HeartRateVariabilityRmssdRecord",
                    value = record.heartRateVariabilityMillis,
                    unit = "milliseconds",
                    startTime = DateFormatters.formatInstant(record.time),
                    endTime = DateFormatters.formatInstant(record.time),
                    startZoneOffset = DateFormatters.formatZoneOffset(record.zoneOffset),
                    endZoneOffset = DateFormatters.formatZoneOffset(record.zoneOffset),
                    dataOrigin = record.metadata.dataOrigin.packageName,
                    lastModifiedTime = DateFormatters.formatInstant(record.metadata.lastModifiedTime)
                )
            )

            is OxygenSaturationRecord -> listOf(
                HealthSample(
                    id = record.metadata.id,
                    type = "OxygenSaturationRecord",
                    value = record.percentage.value,
                    unit = "percent",
                    startTime = DateFormatters.formatInstant(record.time),
                    endTime = DateFormatters.formatInstant(record.time),
                    startZoneOffset = DateFormatters.formatZoneOffset(record.zoneOffset),
                    endZoneOffset = DateFormatters.formatZoneOffset(record.zoneOffset),
                    dataOrigin = record.metadata.dataOrigin.packageName,
                    lastModifiedTime = DateFormatters.formatInstant(record.metadata.lastModifiedTime)
                )
            )

            is Vo2MaxRecord -> listOf(
                HealthSample(
                    id = record.metadata.id,
                    type = "Vo2MaxRecord",
                    value = record.vo2MillilitersPerMinuteKilogram,
                    unit = "mL/kg/min",
                    startTime = DateFormatters.formatInstant(record.time),
                    endTime = DateFormatters.formatInstant(record.time),
                    startZoneOffset = DateFormatters.formatZoneOffset(record.zoneOffset),
                    endZoneOffset = DateFormatters.formatZoneOffset(record.zoneOffset),
                    dataOrigin = record.metadata.dataOrigin.packageName,
                    lastModifiedTime = DateFormatters.formatInstant(record.metadata.lastModifiedTime)
                )
            )

            else -> emptyList()
        }
    }
}
