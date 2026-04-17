package com.dbxwearables.android.ui.payloads

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.dbxwearables.android.ui.components.DbxHeaderCard
import com.dbxwearables.android.ui.components.DbxSecondaryButton
import com.dbxwearables.android.ui.components.NdjsonLineView
import com.dbxwearables.android.ui.theme.DbxCardBackground
import com.dbxwearables.android.ui.theme.DbxGradients
import com.dbxwearables.android.ui.theme.DbxNavy
import com.dbxwearables.android.ui.theme.DbxRed
import com.dbxwearables.android.ui.theme.DbxShapes
import com.dbxwearables.android.ui.theme.DbxTypography

@Composable
fun PayloadInspectorScreen(viewModel: PayloadInspectorViewModel = hiltViewModel()) {
    val selectedCategory by viewModel.selectedCategory.collectAsStateWithLifecycle()
    val payload by viewModel.currentPayload.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val expandedLines = remember { mutableStateMapOf<Int, Boolean>() }

    LaunchedEffect(Unit) { viewModel.refresh() }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(DbxGradients.darkBackground),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            DbxHeaderCard(title = "Payload Inspector", subtitle = "Last-sent NDJSON per record type")
        }

        item {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                viewModel.categories.forEach { category ->
                    FilterChip(
                        selected = category == selectedCategory,
                        onClick = {
                            expandedLines.clear()
                            viewModel.selectCategory(category)
                        },
                        label = { Text(category, style = DbxTypography.mono) },
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = DbxRed,
                            selectedLabelColor = Color.White,
                            containerColor = DbxCardBackground,
                            labelColor = Color.White.copy(alpha = 0.7f)
                        )
                    )
                }
            }
        }

        val currentPayload = payload
        if (currentPayload != null) {
            item {
                Card(
                    shape = DbxShapes.card,
                    colors = CardDefaults.cardColors(containerColor = DbxCardBackground)
                ) {
                    Column(modifier = Modifier.padding(12.dp)) {
                        Text(text = "Request Headers", style = DbxTypography.mono, color = DbxRed)
                        Spacer(modifier = Modifier.height(4.dp))
                        currentPayload.requestHeaders.forEach { (key, value) ->
                            Text(
                                text = "$key: $value",
                                style = DbxTypography.mono,
                                color = Color.White.copy(alpha = 0.6f)
                            )
                        }
                    }
                }
            }

            val lines = currentPayload.ndjsonPayload?.split("\n")
                ?.filter { it.isNotBlank() } ?: emptyList()

            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = "${lines.size} lines",
                        style = DbxTypography.mono,
                        color = Color.White.copy(alpha = 0.5f)
                    )
                    DbxSecondaryButton(
                        text = "Copy",
                        onClick = {
                            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                            clipboard.setPrimaryClip(ClipData.newPlainText("NDJSON", currentPayload.ndjsonPayload))
                            Toast.makeText(context, "Copied to clipboard", Toast.LENGTH_SHORT).show()
                        }
                    )
                }
            }

            itemsIndexed(lines) { index, line ->
                NdjsonLineView(
                    lineNumber = index + 1,
                    jsonLine = line,
                    isExpanded = expandedLines[index] == true,
                    onToggle = { expandedLines[index] = expandedLines[index] != true }
                )
            }
        } else {
            item {
                Card(
                    shape = DbxShapes.card,
                    colors = CardDefaults.cardColors(containerColor = DbxCardBackground)
                ) {
                    Text(
                        text = "No payload data yet. Tap Sync Now on the Dashboard.",
                        style = DbxTypography.mono,
                        color = Color.White.copy(alpha = 0.5f),
                        modifier = Modifier.padding(16.dp)
                    )
                }
            }
        }
    }
}
