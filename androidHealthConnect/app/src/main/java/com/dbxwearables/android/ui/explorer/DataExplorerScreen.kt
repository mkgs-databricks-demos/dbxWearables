package com.dbxwearables.android.ui.explorer

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.dbxwearables.android.ui.components.DbxHeaderCard
import com.dbxwearables.android.ui.theme.DbxCardBackground
import com.dbxwearables.android.ui.theme.DbxGradients
import com.dbxwearables.android.ui.theme.DbxGreen
import com.dbxwearables.android.ui.theme.DbxNavy
import com.dbxwearables.android.ui.theme.DbxRed
import com.dbxwearables.android.ui.theme.DbxShapes
import com.dbxwearables.android.ui.theme.DbxTypography

@Composable
fun DataExplorerScreen(viewModel: DataExplorerViewModel = hiltViewModel()) {
    val categories by viewModel.categories.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) { viewModel.refresh() }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(DbxGradients.darkBackground),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            DbxHeaderCard(title = "Data Explorer", subtitle = "Per-category breakdown")
        }

        items(categories) { category ->
            var expanded by remember { mutableStateOf(false) }

            Card(
                shape = DbxShapes.card,
                colors = CardDefaults.cardColors(containerColor = DbxCardBackground),
                modifier = Modifier.clickable { expanded = !expanded }
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(text = category.name, style = DbxTypography.sectionHeader)
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                text = category.count.toString(),
                                style = DbxTypography.sectionHeader,
                                color = DbxRed
                            )
                            Icon(
                                imageVector = if (expanded) Icons.Default.ExpandLess
                                else Icons.Default.ExpandMore,
                                contentDescription = null,
                                tint = Color.White.copy(alpha = 0.5f)
                            )
                        }
                    }

                    AnimatedVisibility(visible = expanded) {
                        Column(modifier = Modifier.padding(top = 12.dp)) {
                            if (category.breakdown.isEmpty()) {
                                Text(
                                    text = "No data yet",
                                    style = DbxTypography.mono,
                                    color = Color.White.copy(alpha = 0.5f)
                                )
                            } else {
                                category.breakdown.entries
                                    .sortedByDescending { it.value }
                                    .forEach { (type, count) ->
                                        Row(
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .background(DbxNavy.copy(alpha = 0.5f))
                                                .padding(horizontal = 12.dp, vertical = 6.dp),
                                            horizontalArrangement = Arrangement.SpaceBetween
                                        ) {
                                            Text(
                                                text = type,
                                                style = DbxTypography.mono,
                                                color = DbxGreen
                                            )
                                            Text(
                                                text = count.toString(),
                                                style = DbxTypography.mono,
                                                color = Color.White
                                            )
                                        }
                                        Spacer(modifier = Modifier.height(2.dp))
                                    }
                            }
                        }
                    }
                }
            }
        }
    }
}
