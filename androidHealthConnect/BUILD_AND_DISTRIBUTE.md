# Android Build & Distribution Guide

Step-by-step instructions for building the dbxWearables Android app and distributing it to trial users.

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Android Studio | Ladybug (2024.2) or newer | Includes bundled JDK 17 and Gradle |
| JDK | 17+ | Bundled with Android Studio, or install separately |
| Android SDK | API 35 (Android 15) | Install via Android Studio SDK Manager |
| Android SDK Build-Tools | 35.0.0 | Install via SDK Manager |
| Git | Any recent version | To clone the repository |

Health Connect is available on Android 14+ (API 34) devices. The app's `minSdk` is 28 (Android 9) so it installs on older devices, but Health Connect features require Android 14 or the [Health Connect APK](https://play.google.com/store/apps/details?id=com.google.android.apps.healthdata) on Android 13.

## 1. Clone and Open the Project

```bash
git clone <repo-url>
cd dbxWearables
```

Open Android Studio and select **File > Open**, then navigate to the `androidHealthConnect/` directory. Android Studio will detect the Gradle project and begin syncing dependencies.

If prompted to install missing SDK components, accept all suggestions.

## 2. Configure the API Endpoint

The app needs a Databricks ZeroBus endpoint URL. Set it one of two ways:

### Option A: gradle.properties (recommended for development)

Add to `androidHealthConnect/gradle.properties`:

```properties
DBX_API_BASE_URL=https://your-workspace.cloud.databricks.com/apps/your-app
```

### Option B: Command-line flag

```bash
./gradlew assembleDebug -PDBX_API_BASE_URL=https://your-workspace.cloud.databricks.com/apps/your-app
```

This value is baked into `BuildConfig.DBX_API_BASE_URL` at compile time and used by `APIConfiguration.kt` to construct the full endpoint: `{baseURL}/api/v1/healthconnect/ingest`.

> **Important:** Do not commit real API URLs to the repository. The `.gitignore` excludes `local.properties` but not `gradle.properties`. For sensitive URLs, use `local.properties` and read from it in `build.gradle.kts`.

## 3. Build

### Debug Build

```bash
cd androidHealthConnect
./gradlew assembleDebug
```

The APK is written to `app/build/outputs/apk/debug/app-debug.apk`.

### Release Build

```bash
./gradlew assembleRelease
```

Release builds require a signing key (see [Section 6](#6-signing-for-release)).

### Run Unit Tests

```bash
./gradlew test
```

Test reports are written to `app/build/reports/tests/testDebugUnitTest/index.html`.

## 4. Run on a Device or Emulator

### Physical Device (recommended)

Physical devices provide real Health Connect data from Fitbit, Pixel Watch, Samsung Galaxy Watch, or other wearable sources.

1. Enable **Developer Options** and **USB Debugging** on the device
2. Connect via USB and accept the debugging prompt
3. In Android Studio, select the device from the toolbar and click **Run** (or `./gradlew installDebug`)
4. The app will launch and show the onboarding flow on first run
5. Grant all Health Connect permissions when prompted

### Emulator

The emulator can run the app UI but has no real health data:

1. In Android Studio, open **Device Manager** and create a device with **API 35**
2. After the emulator boots, install Health Connect from the Play Store (or use a Google APIs system image which includes it)
3. Run the app — the UI renders fully, but syncs produce empty results

## 5. First-Run Walkthrough

1. **Onboarding** — 4-page flow explaining ZeroBus, listing Health Connect data types, and requesting permissions
2. **Dashboard** — Shows sync status, per-category record counts, and recent activity
3. **Sync Now** — Tap the Sync Now button on the Dashboard to trigger data upload
4. **Payload Inspector** — Switch to the Payloads tab to inspect the NDJSON that was sent
5. **Data Explorer** — The Data tab shows per-type breakdowns of synced records

## 6. Signing for Release

Debug builds are signed automatically with the Android debug keystore. For distribution you need a release signing configuration.

### Generate a Keystore

```bash
keytool -genkey -v \
  -keystore dbxwearables-release.keystore \
  -alias dbxwearables \
  -keyalg RSA -keysize 2048 \
  -validity 10000
```

### Configure Signing in Gradle

Add to `androidHealthConnect/app/build.gradle.kts` inside the `android` block:

```kotlin
signingConfigs {
    create("release") {
        storeFile = file("../dbxwearables-release.keystore")
        storePassword = System.getenv("KEYSTORE_PASSWORD")
        keyAlias = "dbxwearables"
        keyPassword = System.getenv("KEY_PASSWORD")
    }
}

buildTypes {
    release {
        signingConfig = signingConfigs.getByName("release")
        // ... existing config
    }
}
```

> **Never commit the keystore or passwords to the repository.** Use environment variables or CI/CD secrets.

---

## Distributing to Trial Users

### Option 1: Direct APK Sharing (simplest, for small teams)

Best for: 1-10 testers who you can communicate with directly.

1. Build the signed release APK:
   ```bash
   ./gradlew assembleRelease
   ```
2. Share `app/build/outputs/apk/release/app-release.apk` via Slack, email, or a shared drive
3. Testers must enable **Install from unknown sources** in their device settings
4. Testers install the APK manually

**Limitations:** No automatic updates. You must redistribute the APK for every new version. Not suitable for broader trials.

### Option 2: Firebase App Distribution (recommended for trials)

Best for: 10-100 testers with managed access and automatic update notifications.

#### Setup

1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
2. Add an Android app with package name `com.dbxwearables.android`
3. Download `google-services.json` and place it in `androidHealthConnect/app/`
4. Add the Firebase App Distribution Gradle plugin:

   In `androidHealthConnect/build.gradle.kts`:
   ```kotlin
   plugins {
       // ... existing plugins
       id("com.google.firebase.appdistribution") version "5.1.0" apply false
   }
   ```

   In `androidHealthConnect/app/build.gradle.kts`:
   ```kotlin
   plugins {
       // ... existing plugins
       id("com.google.firebase.appdistribution")
   }

   android {
       buildTypes {
           release {
               firebaseAppDistribution {
                   groups = "dbx-trial-testers"
                   releaseNotes = "Health Connect sync with Databricks ZeroBus"
               }
           }
       }
   }
   ```

#### Distribute

```bash
# Authenticate with Firebase (one-time)
firebase login

# Build and upload
./gradlew assembleRelease appDistributionUploadRelease
```

Testers receive an email invitation, install the Firebase App Tester app, and get notified of new builds automatically.

### Option 3: Google Play Internal Testing (for broader rollout)

Best for: 100+ testers, or when you want Play Store infrastructure (crash reports, staged rollouts, automatic updates).

#### Setup

1. Create a Google Play Developer account ($25 one-time fee)
2. Create the app in the [Google Play Console](https://play.google.com/console)
3. Complete the app content declarations (privacy policy, data safety form, target audience)
4. Build an Android App Bundle:
   ```bash
   ./gradlew bundleRelease
   ```
5. Upload `app/build/outputs/bundle/release/app-release.aab` to the **Internal testing** track

#### Manage Testers

1. In Play Console, go to **Testing > Internal testing**
2. Create a tester list (by email address) or use a Google Group
3. Share the opt-in link with testers — they install from the Play Store
4. Testers receive automatic updates when you upload new builds

#### Testing Tracks (in order of audience size)

| Track | Audience | Review Required |
|-------|----------|-----------------|
| Internal testing | Up to 100 testers by email | No |
| Closed testing | Unlimited testers by email or Google Group | No |
| Open testing | Anyone with the link | Yes (brief review) |
| Production | Everyone on Play Store | Yes (full review) |

For a trial, **internal testing** is sufficient and requires no Google review.

### Option 4: Enterprise MDM (for corporate deployments)

If trial users are within an organization that uses an MDM (Mobile Device Management) solution like Microsoft Intune, VMware Workspace ONE, or Google Endpoint Management:

1. Build the signed release APK
2. Upload to the MDM console as a line-of-business app
3. Assign to a device group containing the trial users
4. The app installs silently on managed devices

This is the best option when testers are on company-managed devices and you need centralized control over app versions.

---

## Device Requirements for Testers

Communicate these requirements to trial users:

| Requirement | Details |
|-------------|---------|
| Android version | 14+ (API 34) recommended; 13 works with Health Connect APK installed manually |
| Health Connect app | Pre-installed on Android 14+; install from Play Store on Android 13 |
| Health data source | Pixel Watch, Fitbit, Samsung Galaxy Watch, Oura Ring, Withings, or any Health Connect-compatible app |
| Internet access | Required for syncing data to Databricks |
| Storage | ~20 MB for app installation |

### Tester Instructions Template

> **Getting started with dbxWearables:**
>
> 1. Install the app (via [link/APK/Play Store] depending on distribution method)
> 2. Open the app and swipe through the onboarding screens
> 3. When prompted, grant all Health Connect permissions
> 4. Go to the Dashboard tab and tap **Sync Now**
> 5. Data will be uploaded to Databricks — check the Payloads tab to see what was sent
>
> **Requirements:** Android 14 or newer, with Health Connect data from a wearable or fitness app.

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `SDK location not found` | Android SDK not configured | Set `sdk.dir` in `local.properties` or set `ANDROID_HOME` env var |
| `Health Connect not available` | Device running Android < 14 without HC app | Install Health Connect from Play Store, or use Android 14+ device |
| `No health data after sync` | No wearable paired or no HC-compatible apps | Pair a wearable or install a fitness app that writes to Health Connect |
| Build fails with `Could not resolve` | Network issue fetching dependencies | Check internet connection; run `./gradlew --refresh-dependencies` |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | Debug/release signing mismatch | Uninstall the existing app from the device and reinstall |
| Empty `DBX_API_BASE_URL` | Property not set | Add `DBX_API_BASE_URL` to `gradle.properties` (see [Section 2](#2-configure-the-api-endpoint)) |
| ProGuard/R8 errors on release build | kotlinx.serialization stripped | Verify `proguard-rules.pro` keeps serialization classes (already configured) |

## CI/CD Integration

For automated builds, a GitHub Actions workflow would look like:

```yaml
name: Android Build
on:
  push:
    paths: ['androidHealthConnect/**']

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 17
      - uses: android-actions/setup-android@v3
      - name: Build debug APK
        working-directory: androidHealthConnect
        run: ./gradlew assembleDebug
      - name: Run unit tests
        working-directory: androidHealthConnect
        run: ./gradlew test
      - uses: actions/upload-artifact@v4
        with:
          name: debug-apk
          path: androidHealthConnect/app/build/outputs/apk/debug/app-debug.apk
```

Add secrets for `KEYSTORE_PASSWORD`, `KEY_PASSWORD`, and `DBX_API_BASE_URL` in the repository settings for release builds.
