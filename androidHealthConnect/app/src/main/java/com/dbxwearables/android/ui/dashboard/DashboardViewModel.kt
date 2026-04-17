package com.dbxwearables.android.ui.dashboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.dbxwearables.android.data.model.SyncRecord
import com.dbxwearables.android.data.model.SyncStats
import com.dbxwearables.android.data.repository.SyncLedger
import com.dbxwearables.android.domain.sync.SyncCoordinator
import com.dbxwearables.android.health.HealthConnectManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.Instant
import javax.inject.Inject

@HiltViewModel
class DashboardViewModel @Inject constructor(
    private val syncCoordinator: SyncCoordinator,
    private val syncLedger: SyncLedger,
    private val healthConnectManager: HealthConnectManager,
) : ViewModel() {

    val isSyncing: StateFlow<Boolean> = syncCoordinator.isSyncing
    val lastSyncDate: StateFlow<Instant?> = syncCoordinator.lastSyncDate

    private val _stats = MutableStateFlow(SyncStats.empty())
    val stats: StateFlow<SyncStats> = _stats.asStateFlow()

    private val _recentEvents = MutableStateFlow<List<SyncRecord>>(emptyList())
    val recentEvents: StateFlow<List<SyncRecord>> = _recentEvents.asStateFlow()

    private val _hasPermissions = MutableStateFlow(false)
    val hasPermissions: StateFlow<Boolean> = _hasPermissions.asStateFlow()

    val isAvailable: Boolean get() = healthConnectManager.isAvailable

    fun syncNow() {
        viewModelScope.launch {
            syncCoordinator.syncAll()
            refresh()
        }
    }

    fun refresh() {
        viewModelScope.launch {
            _stats.value = syncLedger.getStats()
            _recentEvents.value = syncLedger.getRecentEvents()
            try {
                _hasPermissions.value = healthConnectManager.hasAllPermissions()
            } catch (_: Exception) {
                _hasPermissions.value = false
            }
        }
    }
}
