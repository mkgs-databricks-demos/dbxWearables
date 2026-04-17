package com.dbxwearables.android.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class DailySummary(
    val date: String,
    val timezone: String,
    @SerialName("total_steps") val totalSteps: Long,
    @SerialName("active_calories_burned_kcal") val activeCaloriesBurnedKcal: Double,
    @SerialName("total_distance_meters") val totalDistanceMeters: Double,
    @SerialName("exercise_duration_minutes") val exerciseDurationMinutes: Double? = null
)
