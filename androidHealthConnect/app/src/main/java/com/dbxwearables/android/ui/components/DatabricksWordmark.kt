package com.dbxwearables.android.ui.components

import androidx.compose.foundation.layout.Row
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.dbxwearables.android.ui.theme.DbxRed

@Composable
fun DatabricksWordmark(modifier: Modifier = Modifier, fontSize: Int = 24) {
    Row(modifier = modifier) {
        Text(
            text = "data",
            fontSize = fontSize.sp,
            fontWeight = FontWeight.Light,
            color = Color.White
        )
        Text(
            text = "bricks",
            fontSize = fontSize.sp,
            fontWeight = FontWeight.Bold,
            color = DbxRed
        )
    }
}
