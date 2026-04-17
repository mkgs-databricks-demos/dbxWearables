package com.dbxwearables.android.util

import com.dbxwearables.android.data.model.HealthSample
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class NDJSONSerializerTest {

    @Test
    fun `encode produces one line per record`() {
        val samples = listOf(
            makeSample(id = "test-001", type = "StepsRecord", value = 1243.0, unit = "steps"),
            makeSample(id = "test-002", type = "HeartRateRecord", value = 72.0, unit = "bpm"),
        )

        val ndjson = NDJSONSerializer.encodeToString(samples)
        val lines = ndjson.split("\n").filter { it.isNotBlank() }

        assertEquals(2, lines.size, "NDJSON should have one line per sample")

        lines.forEach { line ->
            val parsed = Json.parseToJsonElement(line)
            assertTrue(parsed is JsonObject, "Each line should be valid JSON")
        }
    }

    @Test
    fun `encode empty array produces empty string`() {
        val result = NDJSONSerializer.encodeToString(emptyList<HealthSample>())
        assertTrue(result.isEmpty())
    }

    @Test
    fun `encode empty array produces empty byte array`() {
        val result = NDJSONSerializer.encode(emptyList<HealthSample>())
        assertTrue(result.isEmpty())
    }

    @Test
    fun `each line contains expected Health Connect fields`() {
        val sample = makeSample(
            id = "test-003",
            type = "StepsRecord",
            value = 500.0,
            unit = "steps"
        )

        val ndjson = NDJSONSerializer.encodeToString(listOf(sample))
        val line = ndjson.trim()
        val json = Json.parseToJsonElement(line) as JsonObject

        assertEquals("\"StepsRecord\"", json["type"].toString())
        assertEquals("500.0", json["value"].toString())
        assertEquals("\"steps\"", json["unit"].toString())
        assertEquals("\"com.google.fitness\"", json["data_origin"].toString())
        assertNotNull(json["start_time"])
        assertNotNull(json["end_time"])
        assertNotNull(json["last_modified_time"])
    }

    @Test
    fun `keys are sorted alphabetically`() {
        val sample = makeSample(id = "test-004", type = "StepsRecord", value = 100.0, unit = "steps")
        val ndjson = NDJSONSerializer.encodeToString(listOf(sample))
        val line = ndjson.trim()
        val json = Json.parseToJsonElement(line) as JsonObject
        val keys = json.keys.toList()
        assertEquals(keys.sorted(), keys, "JSON keys should be sorted alphabetically")
    }

    private fun makeSample(
        id: String = "test-id",
        type: String = "StepsRecord",
        value: Double = 100.0,
        unit: String = "steps"
    ) = HealthSample(
        id = id,
        type = type,
        value = value,
        unit = unit,
        startTime = "2026-04-16T08:00:00Z",
        endTime = "2026-04-16T09:00:00Z",
        dataOrigin = "com.google.fitness",
        lastModifiedTime = "2026-04-16T09:01:00Z"
    )
}
