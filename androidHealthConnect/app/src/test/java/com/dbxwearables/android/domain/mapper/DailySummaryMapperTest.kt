package com.dbxwearables.android.domain.mapper

import com.dbxwearables.android.util.NDJSONSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.time.LocalDate

class DailySummaryMapperTest {

    @Test
    fun `builds summary with correct date format`() {
        val summary = DailySummaryMapper.buildSummary(
            date = LocalDate.of(2026, 4, 16),
            timezone = "America/Los_Angeles",
            steps = 8472,
            activeCaloriesKcal = 312.5,
            distanceMeters = 6240.0,
            exerciseMinutes = 35.2
        )

        assertEquals("2026-04-16", summary.date)
        assertEquals("America/Los_Angeles", summary.timezone)
        assertEquals(8472L, summary.totalSteps)
        assertEquals(312.5, summary.activeCaloriesBurnedKcal)
        assertEquals(6240.0, summary.totalDistanceMeters)
        assertEquals(35.2, summary.exerciseDurationMinutes)
    }

    @Test
    fun `summary encodes to correct NDJSON`() {
        val summary = DailySummaryMapper.buildSummary(
            date = LocalDate.of(2026, 4, 16),
            timezone = "America/New_York",
            steps = 10000,
            activeCaloriesKcal = 400.0,
            distanceMeters = 8000.0,
            exerciseMinutes = null
        )

        val ndjson = NDJSONSerializer.encodeToString(listOf(summary))
        val json = Json.parseToJsonElement(ndjson.trim()) as JsonObject

        assertEquals("\"2026-04-16\"", json["date"].toString())
        assertEquals("\"America/New_York\"", json["timezone"].toString())
        assertEquals("10000", json["total_steps"].toString())
    }
}
