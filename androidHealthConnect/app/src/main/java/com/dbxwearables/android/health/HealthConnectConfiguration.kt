package com.dbxwearables.android.health

import androidx.health.connect.client.permission.HealthPermission
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
import kotlin.reflect.KClass

object HealthConnectConfiguration {

    val sampleRecordTypes: List<KClass<out Record>> = listOf(
        StepsRecord::class,
        DistanceRecord::class,
        ActiveCaloriesBurnedRecord::class,
        BasalMetabolicRateRecord::class,
        HeartRateRecord::class,
        RestingHeartRateRecord::class,
        HeartRateVariabilityRmssdRecord::class,
        OxygenSaturationRecord::class,
        Vo2MaxRecord::class,
    )

    val workoutRecordType: KClass<out Record> = ExerciseSessionRecord::class
    val sleepRecordType: KClass<out Record> = SleepSessionRecord::class

    val allPermissions: Set<String> = buildSet {
        sampleRecordTypes.forEach { add(HealthPermission.getReadPermission(it)) }
        add(HealthPermission.getReadPermission(workoutRecordType))
        add(HealthPermission.getReadPermission(sleepRecordType))
    }

    const val BATCH_SIZE_FOREGROUND = 2_000
    const val BATCH_SIZE_BACKGROUND = 500
}
