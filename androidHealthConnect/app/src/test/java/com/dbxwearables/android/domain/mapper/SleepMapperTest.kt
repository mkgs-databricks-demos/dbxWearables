package com.dbxwearables.android.domain.mapper

import com.dbxwearables.android.data.model.SleepRecord
import com.dbxwearables.android.data.model.SleepStage
import com.dbxwearables.android.util.NDJSONSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class SleepMapperTest {

    @Test
    fun `empty input returns empty output`() {
        val result = SleepMapper.mapSleepSessions(emptyList())
        assertEquals(0, result.size)
    }

    @Test
    fun `sleep record encodes with HC stage names`() {
        val record = SleepRecord(
            id = "sleep-001",
            startTime = "2026-04-15T22:30:00Z",
            endTime = "2026-04-16T06:45:00Z",
            durationSeconds = 29700.0,
            dataOrigin = "com.google.fitness",
            lastModifiedTime = "2026-04-16T07:00:00Z",
            stages = listOf(
                SleepStage(stage = "light", stageCode = 4, startTime = "2026-04-15T22:30:00Z", endTime = "2026-04-15T23:15:00Z"),
                SleepStage(stage = "deep", stageCode = 5, startTime = "2026-04-15T23:15:00Z", endTime = "2026-04-16T00:00:00Z"),
                SleepStage(stage = "rem", stageCode = 6, startTime = "2026-04-16T00:00:00Z", endTime = "2026-04-16T00:45:00Z"),
            )
        )

        val ndjson = NDJSONSerializer.encodeToString(listOf(record))
        val lines = ndjson.split("\n").filter { it.isNotBlank() }
        assertEquals(1, lines.size, "One sleep record should produce one NDJSON line")

        val json = Json.parseToJsonElement(lines[0]) as JsonObject
        val stages = json["stages"]?.jsonArray
        assertEquals(3, stages?.size)

        val firstStage = stages?.get(0) as? JsonObject
        assertEquals("\"light\"", firstStage?.get("stage").toString())
        assertEquals("4", firstStage?.get("stage_code").toString())
    }

    @Test
    fun `sleep record has session-level id`() {
        val record = SleepRecord(
            id = "session-abc",
            startTime = "2026-04-15T22:30:00Z",
            endTime = "2026-04-16T06:45:00Z",
            durationSeconds = 29700.0,
            dataOrigin = "com.google.fitness",
            lastModifiedTime = "2026-04-16T07:00:00Z",
            stages = emptyList()
        )

        val ndjson = NDJSONSerializer.encodeToString(listOf(record))
        val json = Json.parseToJsonElement(ndjson.trim()) as JsonObject
        assertEquals("\"session-abc\"", json["id"].toString())
    }
}
