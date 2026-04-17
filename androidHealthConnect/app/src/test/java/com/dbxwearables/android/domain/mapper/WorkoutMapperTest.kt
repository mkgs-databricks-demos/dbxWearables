package com.dbxwearables.android.domain.mapper

import com.dbxwearables.android.data.model.WorkoutRecord
import com.dbxwearables.android.util.NDJSONSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Test

class WorkoutMapperTest {

    @Test
    fun `empty input returns empty output`() {
        val result = WorkoutMapper.mapWorkouts(emptyList())
        assertEquals(0, result.size)
    }

    @Test
    fun `workout record encodes to NDJSON with HC fields`() {
        val record = WorkoutRecord(
            id = "workout-001",
            exerciseType = "running",
            exerciseTypeCode = 56,
            title = "Morning Run",
            startTime = "2026-04-16T07:00:00Z",
            endTime = "2026-04-16T07:35:12Z",
            durationSeconds = 2112.0,
            dataOrigin = "com.google.fitness",
            lastModifiedTime = "2026-04-16T07:36:00Z"
        )

        val ndjson = NDJSONSerializer.encodeToString(listOf(record))
        val lines = ndjson.split("\n").filter { it.isNotBlank() }
        assertEquals(1, lines.size)

        val json = Json.parseToJsonElement(lines[0]) as JsonObject
        assertEquals("\"running\"", json["exercise_type"].toString())
        assertEquals("56", json["exercise_type_code"].toString())
        assertEquals("2112.0", json["duration_seconds"].toString())
        assertNotNull(json["title"])
    }
}
