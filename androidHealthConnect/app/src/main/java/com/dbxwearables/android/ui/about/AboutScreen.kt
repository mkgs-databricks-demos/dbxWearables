package com.dbxwearables.android.ui.about

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.dbxwearables.android.BuildConfig
import com.dbxwearables.android.ui.components.DataFlowDiagram
import com.dbxwearables.android.ui.components.DbxHeaderCard
import com.dbxwearables.android.ui.components.DbxSecondaryButton
import com.dbxwearables.android.ui.theme.DbxCardBackground
import com.dbxwearables.android.ui.theme.DbxGradients
import com.dbxwearables.android.ui.theme.DbxGreen
import com.dbxwearables.android.ui.theme.DbxShapes
import com.dbxwearables.android.ui.theme.DbxTypography

private val healthConnectTypes = listOf(
    "StepsRecord", "DistanceRecord", "ActiveCaloriesBurnedRecord",
    "BasalMetabolicRateRecord", "HeartRateRecord", "RestingHeartRateRecord",
    "HeartRateVariabilityRmssdRecord", "OxygenSaturationRecord", "Vo2MaxRecord",
    "ExerciseSessionRecord", "SleepSessionRecord"
)

@Composable
fun AboutScreen(onReplayOnboarding: () -> Unit = {}) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(DbxGradients.darkBackground),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        item {
            DbxHeaderCard(title = "About", subtitle = "ZeroBus Health Data Pipeline")
        }

        item {
            Card(
                shape = DbxShapes.card,
                colors = CardDefaults.cardColors(containerColor = DbxCardBackground)
            ) {
                Text(
                    text = "dbx Wearables streams health data from Android Health Connect " +
                            "to Databricks via ZeroBus. Data flows through a medallion " +
                            "architecture: raw NDJSON lands in a bronze table, gets " +
                            "cleaned in silver, and aggregated in gold layers.",
                    style = DbxTypography.mono,
                    color = Color.White.copy(alpha = 0.8f),
                    modifier = Modifier.padding(16.dp)
                )
            }
        }

        item {
            Text(text = "Data Flow", style = DbxTypography.sectionHeader)
            Spacer(modifier = Modifier.height(8.dp))
            DataFlowDiagram()
        }

        item {
            Text(text = "Health Connect Types", style = DbxTypography.sectionHeader)
            Spacer(modifier = Modifier.height(8.dp))
            Card(
                shape = DbxShapes.card,
                colors = CardDefaults.cardColors(containerColor = DbxCardBackground)
            ) {
                healthConnectTypes.forEach { type ->
                    Text(
                        text = "• $type",
                        style = DbxTypography.mono,
                        color = DbxGreen,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 3.dp)
                    )
                }
                Spacer(modifier = Modifier.height(8.dp))
            }
        }

        item {
            Text(
                text = "Version ${BuildConfig.VERSION_NAME}",
                style = DbxTypography.mono,
                color = Color.White.copy(alpha = 0.4f)
            )
        }

        item {
            DbxSecondaryButton(
                text = "Replay Onboarding",
                onClick = onReplayOnboarding,
                modifier = Modifier.fillMaxWidth(0.6f)
            )
            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}
