package com.dbxwearables.android.ui.explorer

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.dbxwearables.android.data.model.SyncStats
import com.dbxwearables.android.data.repository.SyncLedger
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class CategoryInfo(
    val name: String,
    val count: Int,
    val breakdown: Map<String, Int>
)

@HiltViewModel
class DataExplorerViewModel @Inject constructor(
    private val syncLedger: SyncLedger
) : ViewModel() {

    private val _categories = MutableStateFlow<List<CategoryInfo>>(emptyList())
    val categories: StateFlow<List<CategoryInfo>> = _categories.asStateFlow()

    fun refresh() {
        viewModelScope.launch {
            val stats = syncLedger.getStats()
            _categories.value = buildCategories(stats)
        }
    }

    private fun buildCategories(stats: SyncStats): List<CategoryInfo> = listOf(
        CategoryInfo(
            name = "Samples",
            count = stats.totalRecordsSent["samples"] ?: 0,
            breakdown = stats.sampleBreakdown.toMap()
        ),
        CategoryInfo(
            name = "Workouts",
            count = stats.totalRecordsSent["workouts"] ?: 0,
            breakdown = stats.workoutBreakdown.toMap()
        ),
        CategoryInfo(
            name = "Sleep",
            count = stats.totalRecordsSent["sleep"] ?: 0,
            breakdown = mapOf("sessions" to stats.sleepSessionCount)
        ),
        CategoryInfo(
            name = "Daily Summaries",
            count = stats.totalRecordsSent["daily_summaries"] ?: 0,
            breakdown = mapOf("days" to stats.dailySummaryDayCount)
        ),
        CategoryInfo(
            name = "Deletes",
            count = stats.totalRecordsSent["deletes"] ?: 0,
            breakdown = stats.deleteBreakdown.toMap()
        ),
    )
}
