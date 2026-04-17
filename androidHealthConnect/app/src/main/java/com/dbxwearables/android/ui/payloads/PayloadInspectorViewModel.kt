package com.dbxwearables.android.ui.payloads

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.dbxwearables.android.data.model.SyncRecord
import com.dbxwearables.android.data.repository.SyncLedger
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class PayloadInspectorViewModel @Inject constructor(
    private val syncLedger: SyncLedger
) : ViewModel() {

    val categories = listOf("samples", "workouts", "sleep", "daily_summaries", "deletes")

    private val _selectedCategory = MutableStateFlow("samples")
    val selectedCategory: StateFlow<String> = _selectedCategory.asStateFlow()

    private val _currentPayload = MutableStateFlow<SyncRecord?>(null)
    val currentPayload: StateFlow<SyncRecord?> = _currentPayload.asStateFlow()

    fun selectCategory(category: String) {
        _selectedCategory.value = category
        loadPayload(category)
    }

    fun refresh() {
        loadPayload(_selectedCategory.value)
    }

    private fun loadPayload(category: String) {
        viewModelScope.launch {
            _currentPayload.value = syncLedger.getLastPayload(category)
        }
    }
}
