package com.dbxwearables.android.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.dbxwearables.android.ui.theme.DbxCardBackground
import com.dbxwearables.android.ui.theme.DbxGreen
import com.dbxwearables.android.ui.theme.DbxRed
import com.dbxwearables.android.ui.theme.DbxShapes
import com.dbxwearables.android.ui.theme.DbxTypography

@Composable
fun SyncStatusCard(
    isSyncing: Boolean,
    lastSync: String?,
    onSyncClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = DbxShapes.card,
        colors = CardDefaults.cardColors(containerColor = DbxCardBackground)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = if (isSyncing) "Syncing..." else "Ready",
                        style = DbxTypography.sectionHeader,
                        color = if (isSyncing) DbxRed else DbxGreen
                    )
                    if (lastSync != null) {
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            text = "Last: $lastSync",
                            style = DbxTypography.mono,
                            color = Color.White.copy(alpha = 0.5f)
                        )
                    }
                }
                if (isSyncing) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(32.dp),
                        color = DbxRed,
                        strokeWidth = 3.dp
                    )
                } else {
                    DbxPrimaryButton(
                        text = "Sync Now",
                        onClick = onSyncClick
                    )
                }
            }
        }
    }
}
