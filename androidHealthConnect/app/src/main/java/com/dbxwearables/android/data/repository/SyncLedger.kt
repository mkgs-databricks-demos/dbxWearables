package com.dbxwearables.android.data.repository

import android.content.Context
import android.util.Log
import com.dbxwearables.android.data.model.SyncRecord
import com.dbxwearables.android.data.model.SyncStats
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import java.io.File
import java.time.Instant
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * File-based persistence for sync payloads and cumulative statistics.
 *
 * Stores:
 * - Cumulative stats (record counts, breakdowns by type) in `stats.json`
 * - Last NDJSON payload per record type in `last_payload_{type}.json`
 * - Recent sync events (last 20, without payloads) in `recent_events.json`
 *
 * Thread-safe via [Mutex]. Files live in the app's internal storage under `sync_ledger/`.
 * This is the Android equivalent of the iOS SyncLedger actor.
 */
@Singleton
class SyncLedger @Inject constructor(
    @ApplicationContext context: Context
) {

    private val ledgerDir: File =
        File(context.filesDir, "sync_ledger").also { it.mkdirs() }

    private val json = Json {
        prettyPrint = true
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private val mutex = Mutex()

    companion object {
        private const val TAG = "SyncLedger"
        private const val MAX_RECENT_EVENTS = 20
        private const val STATS_FILE = "stats.json"
        private const val RECENT_EVENTS_FILE = "recent_events.json"
    }

    // ---- Public API ----

    /**
     * Record a sync POST result: updates cumulative stats, saves the last payload
     * for the given [recordType], and appends to the recent events list.
     */
    suspend fun recordSync(
        recordType: String,
        recordCount: Int,
        httpStatusCode: Int,
        success: Boolean,
        ndjsonPayload: String?,
        requestHeaders: Map<String, String>
    ) = mutex.withLock {
        val record = SyncRecord(
            id = UUID.randomUUID().toString(),
            recordType = recordType,
            timestamp = Instant.now().toString(),
            recordCount = recordCount,
            httpStatusCode = httpStatusCode,
            success = success,
            ndjsonPayload = ndjsonPayload,
            requestHeaders = requestHeaders
        )

        // Load and update cumulative stats
        val stats = loadStats()
        stats.totalRecordsSent[recordType] =
            (stats.totalRecordsSent[recordType] ?: 0) + recordCount
        stats.lastSyncTimestamp[recordType] = record.timestamp
        updateBreakdowns(stats, recordType, ndjsonPayload, recordCount)
        saveFile(STATS_FILE, json.encodeToString(stats))

        // Save full record (with payload) as last payload for this record type
        saveFile(
            "last_payload_${recordType}.json",
            json.encodeToString(record)
        )

        // Append to recent events (without payload to save space)
        val recentEvents = loadRecentEvents().toMutableList()
        val eventRecord = record.copy(ndjsonPayload = null)
        recentEvents.add(0, eventRecord)
        val trimmed = if (recentEvents.size > MAX_RECENT_EVENTS) {
            recentEvents.take(MAX_RECENT_EVENTS)
        } else {
            recentEvents
        }
        saveFile(RECENT_EVENTS_FILE, json.encodeToString(trimmed))
    }

    /**
     * Returns cumulative sync stats, or [SyncStats.empty] if none persisted.
     */
    suspend fun getStats(): SyncStats = mutex.withLock {
        loadStats()
    }

    /**
     * Returns the last payload record for [recordType], or null if none stored.
     */
    suspend fun getLastPayload(recordType: String): SyncRecord? = mutex.withLock {
        loadFile<SyncRecord>("last_payload_${recordType}.json")
    }

    /**
     * Returns the list of recent sync events (most recent first, without payloads).
     */
    suspend fun getRecentEvents(): List<SyncRecord> = mutex.withLock {
        loadRecentEvents()
    }

    // ---- Breakdown Parsing ----

    /**
     * Parse NDJSON lines to extract type fields and update per-category breakdowns.
     */
    private fun updateBreakdowns(
        stats: SyncStats,
        recordType: String,
        ndjsonPayload: String?,
        recordCount: Int
    ) {
        when (recordType) {
            "samples" -> {
                if (ndjsonPayload != null) {
                    for (type in parseNdjsonField(ndjsonPayload, "type")) {
                        stats.sampleBreakdown[type] =
                            (stats.sampleBreakdown[type] ?: 0) + 1
                    }
                }
            }
            "workouts" -> {
                if (ndjsonPayload != null) {
                    for (exerciseType in parseNdjsonField(ndjsonPayload, "exercise_type")) {
                        stats.workoutBreakdown[exerciseType] =
                            (stats.workoutBreakdown[exerciseType] ?: 0) + 1
                    }
                }
            }
            "sleep" -> {
                stats.sleepSessionCount += recordCount
            }
            "daily_summaries" -> {
                stats.dailySummaryDayCount += recordCount
            }
            "deletes" -> {
                if (ndjsonPayload != null) {
                    for (rt in parseNdjsonField(ndjsonPayload, "record_type")) {
                        stats.deleteBreakdown[rt] =
                            (stats.deleteBreakdown[rt] ?: 0) + 1
                    }
                }
            }
        }
    }

    /**
     * Splits NDJSON by newline, parses each line as a JSON object, and extracts
     * the string value of [fieldName]. Lines that fail to parse or lack the field
     * are silently skipped.
     */
    private fun parseNdjsonField(ndjson: String, fieldName: String): List<String> {
        return ndjson.split("\n")
            .filter { it.isNotBlank() }
            .mapNotNull { line ->
                try {
                    val element = Json.parseToJsonElement(line)
                    element.jsonObject[fieldName]?.jsonPrimitive?.content
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to parse NDJSON line for field '$fieldName': ${e.message}")
                    null
                }
            }
    }

    // ---- File I/O Helpers ----

    private fun loadStats(): SyncStats {
        return loadFile(STATS_FILE) ?: SyncStats.empty()
    }

    private fun loadRecentEvents(): List<SyncRecord> {
        return loadFile(RECENT_EVENTS_FILE) ?: emptyList()
    }

    private inline fun <reified T> loadFile(fileName: String): T? {
        val file = File(ledgerDir, fileName)
        if (!file.exists()) return null
        return try {
            json.decodeFromString<T>(file.readText())
        } catch (e: Exception) {
            Log.w(TAG, "Failed to load $fileName: ${e.message}")
            null
        }
    }

    private fun saveFile(fileName: String, content: String) {
        try {
            File(ledgerDir, fileName).writeText(content)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to write $fileName: ${e.message}")
        }
    }
}
