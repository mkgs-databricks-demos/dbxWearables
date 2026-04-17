package com.dbxwearables.android.ui.theme

import androidx.compose.ui.graphics.Brush

object DbxGradients {
    val primary = Brush.horizontalGradient(listOf(DbxRed, DbxOrange))
    val darkBackground = Brush.verticalGradient(listOf(DbxNavy, DbxDarkTeal))
    val heroHeader = Brush.verticalGradient(
        listOf(DbxNavy, DbxDarkTeal, DbxNavy.copy(alpha = 0.8f))
    )
}
