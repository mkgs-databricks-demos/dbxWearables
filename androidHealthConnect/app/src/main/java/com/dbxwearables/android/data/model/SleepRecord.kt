package com.dbxwearables.android.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class SleepRecord(
    val id: String,
    @SerialName("start_time") val startTime: String,
    @SerialName("end_time") val endTime: String,
    @SerialName("start_zone_offset") val startZoneOffset: String? = null,
    @SerialName("end_zone_offset") val endZoneOffset: String? = null,
    @SerialName("duration_seconds") val durationSeconds: Double,
    @SerialName("data_origin") val dataOrigin: String,
    @SerialName("last_modified_time") val lastModifiedTime: String,
    val title: String? = null,
    val notes: String? = null,
    val stages: List<SleepStage>
)

@Serializable
data class SleepStage(
    val stage: String,
    @SerialName("stage_code") val stageCode: Int,
    @SerialName("start_time") val startTime: String,
    @SerialName("end_time") val endTime: String
)
