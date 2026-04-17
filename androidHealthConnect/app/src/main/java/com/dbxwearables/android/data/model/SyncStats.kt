package com.dbxwearables.android.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class SyncStats(
    @SerialName("total_records_sent") val totalRecordsSent: MutableMap<String, Int> = mutableMapOf(),
    @SerialName("last_sync_timestamp") val lastSyncTimestamp: MutableMap<String, String> = mutableMapOf(),
    @SerialName("sample_breakdown") val sampleBreakdown: MutableMap<String, Int> = mutableMapOf(),
    @SerialName("workout_breakdown") val workoutBreakdown: MutableMap<String, Int> = mutableMapOf(),
    @SerialName("sleep_session_count") var sleepSessionCount: Int = 0,
    @SerialName("daily_summary_day_count") var dailySummaryDayCount: Int = 0,
    @SerialName("delete_breakdown") val deleteBreakdown: MutableMap<String, Int> = mutableMapOf()
) {
    companion object {
        fun empty() = SyncStats()
    }
}
