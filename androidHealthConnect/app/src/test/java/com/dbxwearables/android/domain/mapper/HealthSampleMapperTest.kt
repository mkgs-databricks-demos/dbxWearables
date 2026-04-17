package com.dbxwearables.android.domain.mapper

import com.dbxwearables.android.data.model.HealthSample
import com.dbxwearables.android.util.NDJSONSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Test

class HealthSampleMapperTest {

    @Test
    fun `empty input returns empty output`() {
        val result = HealthSampleMapper.mapRecords(emptyList())
        assertEquals(0, result.size)
    }

    @Test
    fun `health sample encodes with native HC fields`() {
        val sample = HealthSample(
            id = "sample-001",
            type = "StepsRecord",
            value = 1243.0,
            unit = "steps",
            startTime = "2026-04-16T08:00:00Z",
            endTime = "2026-04-16T09:00:00Z",
            startZoneOffset = "-07:00",
            endZoneOffset = "-07:00",
            dataOrigin = "com.google.android.apps.fitness",
            lastModifiedTime = "2026-04-16T09:01:00Z"
        )

        val ndjson = NDJSONSerializer.encodeToString(listOf(sample))
        val json = Json.parseToJsonElement(ndjson.trim()) as JsonObject

        assertEquals("\"sample-001\"", json["id"].toString())
        assertEquals("\"StepsRecord\"", json["type"].toString())
        assertEquals("1243.0", json["value"].toString())
        assertEquals("\"steps\"", json["unit"].toString())
        assertNotNull(json["start_time"])
        assertNotNull(json["end_time"])
        assertEquals("\"com.google.android.apps.fitness\"", json["data_origin"].toString())
        assertNotNull(json["last_modified_time"])
        assertEquals("\"-07:00\"", json["start_zone_offset"].toString())
    }
}
