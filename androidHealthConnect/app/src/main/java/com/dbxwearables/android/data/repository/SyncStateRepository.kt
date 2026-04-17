package com.dbxwearables.android.data.repository

import android.content.Context
import android.content.SharedPreferences
import dagger.hilt.android.qualifiers.ApplicationContext
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Persists Health Connect change tokens and last sync dates.
 *
 * Uses SharedPreferences for lightweight key-value storage. Change tokens enable
 * incremental sync via Health Connect's Changes API, analogous to HealthKit's
 * anchored object queries on iOS.
 */
@Singleton
class SyncStateRepository @Inject constructor(
    @ApplicationContext context: Context
) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // ---- Change Tokens ----

    /**
     * Returns the stored change token for [recordType], or null if no prior sync.
     * Health Connect change tokens track the position in the change stream so
     * subsequent syncs only fetch new/modified/deleted records.
     */
    fun getChangeToken(recordType: String): String? {
        return prefs.getString("$CHANGE_TOKEN_PREFIX$recordType", null)
    }

    /**
     * Persists a change token after a successful sync for [recordType].
     */
    fun saveChangeToken(recordType: String, token: String) {
        prefs.edit().putString("$CHANGE_TOKEN_PREFIX$recordType", token).apply()
    }

    /**
     * Removes the stored change token for [recordType].
     * Call this when the token has expired or is invalid so the next sync
     * falls back to a full read.
     */
    fun clearChangeToken(recordType: String) {
        prefs.edit().remove("$CHANGE_TOKEN_PREFIX$recordType").apply()
    }

    // ---- Last Sync Dates ----

    /**
     * Returns the last successful sync date for [key], or null if never synced.
     * Dates are stored as ISO 8601 strings and parsed back to [Instant].
     */
    fun getLastSyncDate(key: String): Instant? {
        val iso = prefs.getString("$LAST_SYNC_PREFIX$key", null) ?: return null
        return try {
            Instant.parse(iso)
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Stores the last successful sync date for [key] as an ISO 8601 string.
     */
    fun saveLastSyncDate(key: String, date: Instant) {
        prefs.edit().putString("$LAST_SYNC_PREFIX$key", date.toString()).apply()
    }

    companion object {
        private const val PREFS_NAME = "dbx_sync_state"
        private const val CHANGE_TOKEN_PREFIX = "change_token_"
        private const val LAST_SYNC_PREFIX = "last_sync_"
    }
}
