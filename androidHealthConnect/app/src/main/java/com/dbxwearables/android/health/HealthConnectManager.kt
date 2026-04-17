package com.dbxwearables.android.health

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class HealthConnectManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private var _client: HealthConnectClient? = null

    val isAvailable: Boolean
        get() = HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_AVAILABLE

    val client: HealthConnectClient
        get() {
            if (_client == null) {
                _client = HealthConnectClient.getOrCreate(context)
            }
            return _client!!
        }

    suspend fun hasAllPermissions(): Boolean {
        val granted = client.permissionController.getGrantedPermissions()
        return HealthConnectConfiguration.allPermissions.all { it in granted }
    }

    suspend fun getGrantedPermissions(): Set<String> {
        return client.permissionController.getGrantedPermissions()
    }

    fun getRequiredPermissions(): Set<String> = HealthConnectConfiguration.allPermissions
}
