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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dbxwearables.android.ui.theme.DbxCardBackground
import com.dbxwearables.android.ui.theme.DbxDarkTeal
import com.dbxwearables.android.ui.theme.DbxGreen
import com.dbxwearables.android.ui.theme.DbxOrange
import com.dbxwearables.android.ui.theme.DbxRed
import com.dbxwearables.android.ui.theme.DbxShapes

@Composable
fun DataFlowDiagram(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        DiagramNode("Android Device", DbxDarkTeal)
        Arrow()
        DiagramNode("Health Connect", DbxGreen)
        Arrow()
        DiagramNode("Databricks App (AppKit)", DbxRed)
        Arrow()
        DiagramNode("ZeroBus", DbxOrange)
        Arrow()
        DiagramNode("Bronze Table (Unity Catalog)", DbxCardBackground)
    }
}

@Composable
private fun DiagramNode(label: String, color: Color) {
    Box(
        modifier = Modifier
            .fillMaxWidth(0.8f)
            .clip(DbxShapes.button)
            .background(color)
            .padding(12.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = label,
            color = Color.White,
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun Arrow() {
    Spacer(modifier = Modifier.height(4.dp))
    Text(text = "↓", color = Color.White.copy(alpha = 0.5f), fontSize = 18.sp)
    Spacer(modifier = Modifier.height(4.dp))
}
