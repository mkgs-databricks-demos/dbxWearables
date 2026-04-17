package com.dbxwearables.android.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class APIResponse(
    val status: String,
    val message: String? = null,
    @SerialName("record_id") val recordId: String? = null
)
