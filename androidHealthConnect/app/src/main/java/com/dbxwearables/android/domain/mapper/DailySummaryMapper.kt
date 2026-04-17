package com.dbxwearables.android.domain.mapper

import com.dbxwearables.android.data.model.DailySummary
import com.dbxwearables.android.util.DateFormatters
import java.time.LocalDate

/**
 * Builds a [DailySummary] from pre-aggregated values returned by
 * Health Connect aggregate queries. Called by SyncCoordinator after
 * querying daily aggregates for steps, calories, distance, and exercise duration.
 */
object DailySummaryMapper {

    /**
     * Constructs a [DailySummary] instance from the given aggregated values.
     *
     * @param date The calendar date for the summary.
     * @param timezone The timezone identifier (e.g., "America/New_York") for the summary period.
     * @param steps Total step count for the day.
     * @param activeCaloriesKcal Total active calories burned in kilocalories.
     * @param distanceMeters Total distance covered in meters.
     * @param exerciseMinutes Total exercise duration in minutes, or null if unavailable.
     * @return A [DailySummary] with the date formatted as yyyy-MM-dd.
     */
    fun buildSummary(
        date: LocalDate,
        timezone: String,
        steps: Long,
        activeCaloriesKcal: Double,
        distanceMeters: Double,
        exerciseMinutes: Double?
    ): DailySummary {
        return DailySummary(
            date = DateFormatters.formatDate(date),
            timezone = timezone,
            totalSteps = steps,
            activeCaloriesBurnedKcal = activeCaloriesKcal,
            totalDistanceMeters = distanceMeters,
            exerciseDurationMinutes = exerciseMinutes
        )
    }
}
