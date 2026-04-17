package com.dbxwearables.android.ui.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.dbxwearables.android.ui.components.DatabricksWordmark
import com.dbxwearables.android.ui.components.DbxPrimaryButton
import com.dbxwearables.android.ui.components.DbxSecondaryButton
import com.dbxwearables.android.ui.theme.DbxGradients
import com.dbxwearables.android.ui.theme.DbxGreen
import com.dbxwearables.android.ui.theme.DbxRed
import com.dbxwearables.android.ui.theme.DbxTypography
import kotlinx.coroutines.launch

private const val PAGE_COUNT = 4

@Composable
fun OnboardingScreen(
    onComplete: () -> Unit,
    onRequestPermissions: () -> Unit
) {
    val pagerState = rememberPagerState(pageCount = { PAGE_COUNT })
    val scope = rememberCoroutineScope()

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(DbxGradients.darkBackground)
    ) {
        HorizontalPager(
            state = pagerState,
            modifier = Modifier.fillMaxSize()
        ) { page ->
            when (page) {
                0 -> WelcomePage()
                1 -> ZeroBusPage()
                2 -> DataTypesPage()
                3 -> PermissionsPage(onRequestPermissions)
            }
        }

        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                repeat(PAGE_COUNT) { index ->
                    Box(
                        modifier = Modifier
                            .size(8.dp)
                            .clip(CircleShape)
                            .background(
                                if (index == pagerState.currentPage) DbxRed
                                else Color.White.copy(alpha = 0.3f)
                            )
                    )
                }
            }
            Spacer(modifier = Modifier.height(24.dp))
            if (pagerState.currentPage < PAGE_COUNT - 1) {
                DbxPrimaryButton(
                    text = "Next",
                    onClick = { scope.launch { pagerState.animateScrollToPage(pagerState.currentPage + 1) } }
                )
            } else {
                DbxPrimaryButton(text = "Get Started", onClick = onComplete)
            }
        }
    }
}

@Composable
private fun WelcomePage() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        DatabricksWordmark(fontSize = 32)
        Spacer(modifier = Modifier.height(24.dp))
        Text(
            text = "Welcome to dbx Wearables",
            style = DbxTypography.heroTitle,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = "Stream your health data from Android Health Connect to Databricks for real-time analytics.",
            style = DbxTypography.mono,
            color = Color.White.copy(alpha = 0.7f),
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun ZeroBusPage() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(text = "Powered by ZeroBus", style = DbxTypography.heroTitle, textAlign = TextAlign.Center)
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = "ZeroBus is Databricks' event streaming SDK. It receives health data via a REST API and streams it directly into Unity Catalog bronze tables — no Kafka required.",
            style = DbxTypography.mono,
            color = Color.White.copy(alpha = 0.7f),
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun DataTypesPage() {
    val types = listOf(
        "Steps", "Distance", "Active Calories", "Basal Metabolic Rate",
        "Heart Rate", "Resting Heart Rate", "HRV (RMSSD)",
        "Oxygen Saturation", "VO2 Max", "Exercise Sessions", "Sleep Sessions"
    )
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(text = "Data We Sync", style = DbxTypography.heroTitle, textAlign = TextAlign.Center)
        Spacer(modifier = Modifier.height(16.dp))
        types.forEach { type ->
            Text(
                text = "• $type",
                style = DbxTypography.mono,
                color = DbxGreen,
                modifier = Modifier.padding(vertical = 2.dp)
            )
        }
    }
}

@Composable
private fun PermissionsPage(onRequestPermissions: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(text = "Grant Access", style = DbxTypography.heroTitle, textAlign = TextAlign.Center)
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = "This app needs read access to your Health Connect data. Your data is sent only to your configured Databricks endpoint.",
            style = DbxTypography.mono,
            color = Color.White.copy(alpha = 0.7f),
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(24.dp))
        DbxSecondaryButton(text = "Grant Permissions", onClick = onRequestPermissions)
    }
}
