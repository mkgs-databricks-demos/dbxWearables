package com.dbxwearables.android.ui.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.dbxwearables.android.ui.components.CategoryStatCard
import com.dbxwearables.android.ui.components.DbxHeaderCard
import com.dbxwearables.android.ui.components.DbxPrimaryButton
import com.dbxwearables.android.ui.components.SyncStatusCard
import com.dbxwearables.android.ui.theme.DbxCardBackground
import com.dbxwearables.android.ui.theme.DbxGradients
import com.dbxwearables.android.ui.theme.DbxGreen
import com.dbxwearables.android.ui.theme.DbxRed
import com.dbxwearables.android.ui.theme.DbxShapes
import com.dbxwearables.android.ui.theme.DbxTypography

private data class StatItem(val label: String, val key: String, val icon: ImageVector)

private val statItems = listOf(
    StatItem("Samples", "samples", Icons.Default.Favorite),
    StatItem("Workouts", "workouts", Icons.Default.FitnessCenter),
    StatItem("Sleep", "sleep", Icons.Default.Bedtime),
    StatItem("Summaries", "daily_summaries", Icons.Default.CalendarMonth),
    StatItem("Deletes", "deletes", Icons.Default.Delete),
)

@Composable
fun DashboardScreen(
    viewModel: DashboardViewModel = hiltViewModel(),
    onRequestPermissions: () -> Unit = {}
) {
    val isSyncing by viewModel.isSyncing.collectAsStateWithLifecycle()
    val lastSync by viewModel.lastSyncDate.collectAsStateWithLifecycle()
    val stats by viewModel.stats.collectAsStateWithLifecycle()
    val recentEvents by viewModel.recentEvents.collectAsStateWithLifecycle()
    val hasPermissions by viewModel.hasPermissions.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) { viewModel.refresh() }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(DbxGradients.darkBackground),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            DbxHeaderCard(
                title = "dbx Wearables",
                subtitle = "Health Connect → Databricks ZeroBus"
            )
        }

        item {
            SyncStatusCard(
                isSyncing = isSyncing,
                lastSync = lastSync?.toString()?.take(19),
                onSyncClick = { viewModel.syncNow() }
            )
        }

        if (!hasPermissions) {
            item {
                Card(
                    shape = DbxShapes.card,
                    colors = CardDefaults.cardColors(containerColor = DbxCardBackground)
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(
                            text = "Health Connect permissions required",
                            style = DbxTypography.mono,
                            color = Color.White.copy(alpha = 0.7f)
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        DbxPrimaryButton(
                            text = "Grant Permissions",
                            onClick = onRequestPermissions
                        )
                    }
                }
            }
        }

        item {
            Text(
                text = "Records Synced",
                style = DbxTypography.sectionHeader,
                modifier = Modifier.padding(top = 8.dp)
            )
        }

        item {
            LazyVerticalGrid(
                columns = GridCells.Fixed(2),
                modifier = Modifier.height(280.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                userScrollEnabled = false
            ) {
                items(statItems) { item ->
                    CategoryStatCard(
                        label = item.label,
                        count = stats.totalRecordsSent[item.key] ?: 0,
                        icon = item.icon
                    )
                }
            }
        }

        if (recentEvents.isNotEmpty()) {
            item {
                Text(
                    text = "Recent Activity",
                    style = DbxTypography.sectionHeader,
                    modifier = Modifier.padding(top = 8.dp)
                )
            }
            items(recentEvents) { event ->
                Card(
                    shape = DbxShapes.card,
                    colors = CardDefaults.cardColors(containerColor = DbxCardBackground)
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column {
                            Text(
                                text = event.recordType,
                                style = DbxTypography.mono,
                                color = Color.White
                            )
                            Text(
                                text = "${event.recordCount} records · ${event.timestamp.take(19)}",
                                style = DbxTypography.mono,
                                color = Color.White.copy(alpha = 0.5f)
                            )
                        }
                        Box(
                            modifier = Modifier
                                .size(8.dp)
                                .background(
                                    if (event.success) DbxGreen else DbxRed,
                                    shape = androidx.compose.foundation.shape.CircleShape
                                )
                        )
                    }
                }
            }
        }
    }
}
