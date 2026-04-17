# Android Health Connect

Android app for reading health and fitness data via Google's [Health Connect API](https://developer.android.com/health-and-fitness/guides/health-connect) and posting it to a Databricks ZeroBus ingestion endpoint as NDJSON.

This is the Android counterpart to the iOS HealthKit app in `healthKit/`. It uses **native Health Connect types and conventions** — field names, type identifiers, and units follow Health Connect best practices rather than mirroring the iOS schemas. A separate API endpoint (`/api/v1/healthconnect/ingest`) and separate bronze table (`bronze_health_connect`) are used so the Databricks side can apply platform-specific processing.

## Tech Stack

| Concern | Choice |
|---|---|
| Language | Kotlin |
| UI | Jetpack Compose + Material 3 |
| Health API | Health Connect (`androidx.health.connect`) |
| Async | Kotlin Coroutines |
| DI | Hilt |
| Serialization | kotlinx.serialization |
| HTTP | OkHttp |
| Secure Storage | EncryptedSharedPreferences |
| Testing | JUnit 5, MockK, OkHttp MockWebServer |

## Health Connect Data Types

| Health Connect Record | NDJSON `type` | Unit |
|---|---|---|
| `StepsRecord` | `StepsRecord` | `steps` |
| `DistanceRecord` | `DistanceRecord` | `meters` |
| `ActiveCaloriesBurnedRecord` | `ActiveCaloriesBurnedRecord` | `kcal` |
| `BasalMetabolicRateRecord` | `BasalMetabolicRateRecord` | `kcal_per_day` |
| `HeartRateRecord` | `HeartRateRecord` | `bpm` |
| `RestingHeartRateRecord` | `RestingHeartRateRecord` | `bpm` |
| `HeartRateVariabilityRmssdRecord` | `HeartRateVariabilityRmssdRecord` | `milliseconds` |
| `OxygenSaturationRecord` | `OxygenSaturationRecord` | `percent` |
| `Vo2MaxRecord` | `Vo2MaxRecord` | `mL/kg/min` |
| `ExerciseSessionRecord` | (WorkoutRecord) | — |
| `SleepSessionRecord` | (SleepRecord) | — |

## Project Structure

```
androidHealthConnect/
├── build.gradle.kts                    # Project-level
├── settings.gradle.kts
├── gradle.properties
├── gradle/
│   ├── libs.versions.toml              # Version catalog
│   └── wrapper/
├── app/
│   ├── build.gradle.kts                # App-level
│   └── src/
│       ├── main/
│       │   ├── AndroidManifest.xml
│       │   ├── res/                     # Colors, strings, themes, health permissions
│       │   └── java/com/dbxwearables/android/
│       │       ├── DbxWearablesApp.kt   # @HiltAndroidApp
│       │       ├── MainActivity.kt      # @AndroidEntryPoint
│       │       ├── di/                  # Hilt AppModule
│       │       ├── data/
│       │       │   ├── model/           # HealthSample, WorkoutRecord, SleepRecord, DailySummary, DeletionRecord, etc.
│       │       │   ├── remote/          # APIConfiguration, APIService, APIError
│       │       │   └── repository/      # SyncStateRepository, SyncLedger
│       │       ├── health/              # HealthConnectManager, QueryService, Configuration
│       │       ├── domain/
│       │       │   ├── mapper/          # HealthSample, Workout, Sleep, DailySummary, ExerciseType mappers
│       │       │   └── sync/            # SyncCoordinator
│       │       ├── util/                # NDJSONSerializer, DateFormatters, SecureStorage, DeviceIdentifier
│       │       └── ui/
│       │           ├── theme/           # Databricks-branded colors, typography, gradients
│       │           ├── components/      # Reusable composables
│       │           ├── navigation/      # MainScreen with bottom nav
│       │           ├── dashboard/       # Dashboard screen + ViewModel
│       │           ├── explorer/        # Data Explorer screen + ViewModel
│       │           ├── payloads/        # Payload Inspector screen + ViewModel
│       │           ├── about/           # About screen
│       │           └── onboarding/      # 4-page onboarding flow
│       └── test/                        # Unit tests (JUnit 5 + MockK)
```

## Building

Prerequisites: Android SDK with API 35, JDK 17+.

```bash
cd androidHealthConnect

# Debug build
./gradlew assembleDebug

# Run unit tests
./gradlew test
```

## API Endpoint

`POST {baseURL}/api/v1/healthconnect/ingest`

| Header | Value |
|---|---|
| `Content-Type` | `application/x-ndjson` |
| `X-Platform` | `android_health_connect` |
| `X-Device-Id` | Persistent per-installation UUID |
| `X-App-Version` | From `BuildConfig.VERSION_NAME` |
| `X-Upload-Timestamp` | ISO 8601 UTC |
| `X-Record-Type` | `samples`, `workouts`, `sleep`, `daily_summaries`, `deletes` |
| `Authorization` | `Bearer {token}` (if configured) |

## Configuration

Set the API base URL via Gradle property:

```properties
# In gradle.properties or via -P flag
DBX_API_BASE_URL=https://your-databricks-app.cloud.databricks.com
```

## Bronze Table Strategy

Separate from iOS to accommodate different field names across platforms:

```
bronze_healthkit          ← iOS raw NDJSON
bronze_health_connect     ← Android raw NDJSON
silver_health_samples     ← Unified from both platforms
gold_daily_summary        ← Unified daily aggregations
```

Both bronze tables use the same column structure: `record_id STRING`, `ingested_at TIMESTAMP`, `body VARIANT`, `headers VARIANT`, `record_type STRING`.
