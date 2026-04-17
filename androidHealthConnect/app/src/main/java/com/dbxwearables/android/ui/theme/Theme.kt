package com.dbxwearables.android.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DbxDarkColorScheme = darkColorScheme(
    primary = DbxRed,
    secondary = DbxOrange,
    tertiary = DbxGreen,
    background = DbxNavy,
    surface = DbxDarkTeal,
    surfaceVariant = DbxCardBackground,
    onPrimary = Color.White,
    onSecondary = Color.White,
    onTertiary = Color.White,
    onBackground = Color.White,
    onSurface = Color.White,
    onSurfaceVariant = Color.White.copy(alpha = 0.7f),
    error = DbxRed,
    outline = DbxMediumGray,
)

@Composable
fun DbxWearablesTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DbxDarkColorScheme,
        typography = AppTypography,
        content = content
    )
}
