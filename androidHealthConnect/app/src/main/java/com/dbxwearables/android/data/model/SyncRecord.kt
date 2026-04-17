package com.dbxwearables.android.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class SyncRecord(
    val id: String,
    @SerialName("record_type") val recordType: String,
    val timestamp: String,
    @SerialName("record_count") val recordCount: Int,
    @SerialName("http_status_code") val httpStatusCode: Int,
    val success: Boolean,
    @SerialName("ndjson_payload") val ndjsonPayload: String? = null,
    @SerialName("request_headers") val requestHeaders: Map<String, String> = emptyMap()
)
