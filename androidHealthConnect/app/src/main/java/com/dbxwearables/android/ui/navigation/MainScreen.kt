package com.dbxwearables.android.ui.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Info
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.dbxwearables.android.ui.about.AboutScreen
import com.dbxwearables.android.ui.dashboard.DashboardScreen
import com.dbxwearables.android.ui.explorer.DataExplorerScreen
import com.dbxwearables.android.ui.payloads.PayloadInspectorScreen
import com.dbxwearables.android.ui.theme.DbxDarkTeal
import com.dbxwearables.android.ui.theme.DbxNavy
import com.dbxwearables.android.ui.theme.DbxRed

sealed class Screen(val route: String, val label: String, val icon: ImageVector) {
    data object Dashboard : Screen("dashboard", "Dashboard", Icons.Default.BarChart)
    data object Data : Screen("data", "Data", Icons.Default.Description)
    data object Payloads : Screen("payloads", "Payloads", Icons.Default.Code)
    data object About : Screen("about", "About", Icons.Default.Info)
}

private val screens = listOf(Screen.Dashboard, Screen.Data, Screen.Payloads, Screen.About)

@Composable
fun MainScreen(
    onRequestPermissions: () -> Unit,
    onReplayOnboarding: () -> Unit
) {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination

    Scaffold(
        bottomBar = {
            NavigationBar(containerColor = DbxNavy) {
                screens.forEach { screen ->
                    NavigationBarItem(
                        icon = { Icon(screen.icon, contentDescription = screen.label) },
                        label = { Text(screen.label) },
                        selected = currentDestination?.hierarchy?.any { it.route == screen.route } == true,
                        onClick = {
                            navController.navigate(screen.route) {
                                popUpTo(navController.graph.findStartDestination().id) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = DbxRed,
                            selectedTextColor = DbxRed,
                            unselectedIconColor = Color.White.copy(alpha = 0.5f),
                            unselectedTextColor = Color.White.copy(alpha = 0.5f),
                            indicatorColor = DbxDarkTeal
                        )
                    )
                }
            }
        }
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = Screen.Dashboard.route,
            modifier = Modifier.padding(padding)
        ) {
            composable(Screen.Dashboard.route) {
                DashboardScreen(onRequestPermissions = onRequestPermissions)
            }
            composable(Screen.Data.route) {
                DataExplorerScreen()
            }
            composable(Screen.Payloads.route) {
                PayloadInspectorScreen()
            }
            composable(Screen.About.route) {
                AboutScreen(onReplayOnboarding = onReplayOnboarding)
            }
        }
    }
}
