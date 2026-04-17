package com.dbxwearables.android.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class WorkoutRecord(
    val id: String,
    @SerialName("exercise_type") val exerciseType: String,
    @SerialName("exercise_type_code") val exerciseTypeCode: Int,
    val title: String? = null,
    @SerialName("start_time") val startTime: String,
    @SerialName("end_time") val endTime: String,
    @SerialName("start_zone_offset") val startZoneOffset: String? = null,
    @SerialName("end_zone_offset") val endZoneOffset: String? = null,
    @SerialName("duration_seconds") val durationSeconds: Double,
    @SerialName("data_origin") val dataOrigin: String,
    @SerialName("last_modified_time") val lastModifiedTime: String,
    val notes: String? = null,
    val metadata: Map<String, String>? = null
)
