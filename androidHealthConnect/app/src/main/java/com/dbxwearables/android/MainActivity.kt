package com.dbxwearables.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.health.connect.client.PermissionController
import com.dbxwearables.android.health.HealthConnectConfiguration
import com.dbxwearables.android.ui.navigation.MainScreen
import com.dbxwearables.android.ui.onboarding.OnboardingScreen
import com.dbxwearables.android.ui.theme.DbxWearablesTheme
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    private var showOnboarding by mutableStateOf(false)

    private val permissionLauncher = registerForActivityResult(
        PermissionController.createRequestPermissionResultContract()
    ) { _ -> }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val prefs = getSharedPreferences("dbx_wearables_prefs", MODE_PRIVATE)
        showOnboarding = !prefs.getBoolean("onboarding_completed", false)

        setContent {
            DbxWearablesTheme {
                if (showOnboarding) {
                    OnboardingScreen(
                        onComplete = {
                            prefs.edit().putBoolean("onboarding_completed", true).apply()
                            showOnboarding = false
                        },
                        onRequestPermissions = {
                            permissionLauncher.launch(HealthConnectConfiguration.allPermissions)
                        }
                    )
                } else {
                    MainScreen(
                        onRequestPermissions = {
                            permissionLauncher.launch(HealthConnectConfiguration.allPermissions)
                        },
                        onReplayOnboarding = {
                            showOnboarding = true
                        }
                    )
                }
            }
        }
    }
}
