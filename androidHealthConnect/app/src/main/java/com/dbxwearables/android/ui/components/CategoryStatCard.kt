package com.dbxwearables.android.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dbxwearables.android.ui.theme.DbxCardBackground
import com.dbxwearables.android.ui.theme.DbxRed
import com.dbxwearables.android.ui.theme.DbxShapes
import com.dbxwearables.android.ui.theme.DbxTypography

@Composable
fun CategoryStatCard(
    label: String,
    count: Int,
    icon: ImageVector,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = DbxShapes.card,
        colors = CardDefaults.cardColors(containerColor = DbxCardBackground)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(
                imageVector = icon,
                contentDescription = label,
                tint = DbxRed,
                modifier = Modifier.size(24.dp)
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = count.toString(),
                style = DbxTypography.stat.copy(fontSize = 28.sp)
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = label,
                style = DbxTypography.mono,
                color = Color.White.copy(alpha = 0.7f)
            )
        }
    }
}
