package com.dbxwearables.android.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class HealthSample(
    val id: String,
    val type: String,
    val value: Double,
    val unit: String,
    @SerialName("start_time") val startTime: String,
    @SerialName("end_time") val endTime: String,
    @SerialName("start_zone_offset") val startZoneOffset: String? = null,
    @SerialName("end_zone_offset") val endZoneOffset: String? = null,
    @SerialName("data_origin") val dataOrigin: String,
    @SerialName("last_modified_time") val lastModifiedTime: String,
    val metadata: Map<String, String>? = null
)
