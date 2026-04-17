package com.dbxwearables.android.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.dbxwearables.android.ui.theme.DbxGradients
import com.dbxwearables.android.ui.theme.DbxShapes
import com.dbxwearables.android.ui.theme.DbxTypography

@Composable
fun DbxHeaderCard(
    title: String,
    subtitle: String? = null,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(DbxShapes.card)
            .background(DbxGradients.heroHeader)
            .padding(24.dp)
    ) {
        Column {
            DatabricksWordmark(fontSize = 16)
            Spacer(modifier = Modifier.height(8.dp))
            Text(text = title, style = DbxTypography.heroTitle)
            if (subtitle != null) {
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = subtitle,
                    style = DbxTypography.mono,
                    color = Color.White.copy(alpha = 0.7f)
                )
            }
        }
    }
}
