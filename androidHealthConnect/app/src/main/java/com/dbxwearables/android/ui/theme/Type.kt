package com.dbxwearables.android.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

object DbxTypography {
    val heroTitle = TextStyle(
        fontSize = 28.sp,
        fontWeight = FontWeight.Bold,
        color = Color.White
    )
    val sectionHeader = TextStyle(
        fontSize = 20.sp,
        fontWeight = FontWeight.SemiBold,
        color = Color.White
    )
    val stat = TextStyle(
        fontSize = 36.sp,
        fontWeight = FontWeight.Bold,
        color = Color.White
    )
    val mono = TextStyle(
        fontSize = 12.sp,
        fontFamily = FontFamily.Monospace,
        color = Color.White
    )
}

val AppTypography = Typography(
    headlineLarge = DbxTypography.heroTitle,
    headlineMedium = DbxTypography.sectionHeader,
    displayLarge = DbxTypography.stat,
    bodySmall = DbxTypography.mono,
)
