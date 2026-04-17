package com.dbxwearables.android.data.model

import com.dbxwearables.android.util.NDJSONSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class DeletionRecordTest {

    @Test
    fun `deletion record encodes to NDJSON with HC fields`() {
        val deletions = listOf(
            DeletionRecord(id = "del-001", recordType = "HeartRateRecord", deletedTime = "2026-04-16T10:00:00Z"),
            DeletionRecord(id = "del-002", recordType = "StepsRecord", deletedTime = "2026-04-16T10:01:00Z"),
        )

        val ndjson = NDJSONSerializer.encodeToString(deletions)
        val lines = ndjson.split("\n").filter { it.isNotBlank() }

        assertEquals(2, lines.size)

        val json = Json.parseToJsonElement(lines[0]) as JsonObject
        assertEquals("\"del-001\"", json["id"].toString())
        assertEquals("\"HeartRateRecord\"", json["record_type"].toString())
    }

    @Test
    fun `deletion record is lightweight`() {
        val deletion = DeletionRecord(
            id = "del-001",
            recordType = "HeartRateRecord",
            deletedTime = "2026-04-16T10:00:00Z"
        )
        val data = NDJSONSerializer.encode(listOf(deletion))
        assertTrue(data.size < 200, "A deletion record should be under 200 bytes, was ${data.size}")
    }
}
