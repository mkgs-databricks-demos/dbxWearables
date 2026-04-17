package com.dbxwearables.android.util

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class DeviceIdentifier @Inject constructor(
    @ApplicationContext context: Context
) {

    companion object {
        const val PREFS_NAME = "dbx_device_prefs"
        const val KEY_DEVICE_ID = "device_id"
    }

    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    val deviceId: String by lazy {
        prefs.getString(KEY_DEVICE_ID, null) ?: UUID.randomUUID().toString().also { id ->
            prefs.edit().putString(KEY_DEVICE_ID, id).apply()
        }
    }
}
