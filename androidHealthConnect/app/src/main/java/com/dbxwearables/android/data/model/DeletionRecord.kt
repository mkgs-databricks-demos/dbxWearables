package com.dbxwearables.android.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class DeletionRecord(
    val id: String,
    @SerialName("record_type") val recordType: String,
    @SerialName("deleted_time") val deletedTime: String? = null
)
