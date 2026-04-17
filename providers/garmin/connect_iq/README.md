# Garmin Connect IQ Widget — dbxWearables

A Monkey C widget for Garmin watches (Forerunner 265 and compatible) that reads on-device sensor history and POSTs health data to a Databricks AppKit REST endpoint every 5 minutes.

## Supported Devices

- Forerunner 265 / 265S (primary target)
- Forerunner 965
- Venu 3 / 3S
- Fenix 8
- Enduro 3

Edit `manifest.xml` to add or remove devices.

## Data Collected

Every 5 minutes (configurable up to 60), the background service reads:

| Sensor | Metric Type | Unit |
|--------|-------------|------|
| Heart Rate | `heart_rate_intraday` | bpm |
| Stress | `stress_level` | score |
| Body Battery | `body_battery_current` | score |
| SpO2 | `spo2` | pct |
| Steps | `steps_intraday` | count |

Only new samples (since the last collection) are sent.

## Prerequisites

1. **Garmin Connect IQ SDK** (>= 7.x)

   Download from [developer.garmin.com/connect-iq/sdk](https://developer.garmin.com/connect-iq/sdk/).

   ```bash
   # macOS: add SDK bin to PATH
   export PATH="$HOME/Library/ConnectIQ/Sdks/connectiq-sdk-<version>/bin:$PATH"
   ```

2. **Garmin Connect Mobile** app on your phone (pairs with the watch over BLE).

3. A running **Databricks AppKit endpoint** that accepts POST requests at `/api/v1/garmin/ingest`.

## Build

```bash
cd garmin/connect_iq

# Build for Forerunner 265
monkeyc -f monkey.jungle -d fr265 -o bin/DbxWearables.prg -y /path/to/developer_key.der

# Build for simulator
monkeyc -f monkey.jungle -d fr265 -o bin/DbxWearables.prg -y /path/to/developer_key.der -t
```

If you don't have a developer key yet:

```bash
# Generate a developer key (one-time)
generatekey -f /path/to/developer_key.der
```

## Sideload to Watch

1. Enable Developer Mode on your watch:
   - Settings > System > About > tap the screen 7 times
   - A "Developer Options" menu appears
   - Enable "Developer Mode"

2. Connect your watch to Wi-Fi (same network as your computer).

3. Open the Connect IQ app on your phone and note the watch's IP.

4. Push the app:
   ```bash
   monkeydo bin/DbxWearables.prg fr265
   ```

   Or copy `bin/DbxWearables.prg` to the watch via USB:
   ```
   /GARMIN/APPS/DbxWearables.prg
   ```

## Configure via Garmin Connect Mobile

After installing the widget, configure it from the Garmin Connect Mobile app:

1. Open Garmin Connect Mobile > Device Settings > Connect IQ Apps > dbxWearables
2. Set **API Base URL** to your Databricks AppKit endpoint:
   ```
   https://<workspace>.cloud.databricks.com/apps/<app-name>
   ```
3. (Optional) Set **Auth Token** — a Bearer token for the ingestion endpoint.
4. (Optional) Adjust **Sync Interval** (default: 5 minutes, range: 5-60).

## Widget UI

The widget shows:
- Sync status (OK / Error / Not synced)
- Last sync record count
- Total records synced since install
- Last sync timestamp
- Tap anywhere to trigger an immediate manual sync

## How It Works

1. `DbxWearablesApp` registers a background temporal event on start.
2. Every N minutes, `BackgroundService.onTemporalEvent()` fires.
3. `SensorCollector.collectAll()` reads each SensorHistory iterator for samples newer than the last collection.
4. The background service POSTs the collected records as JSON to the configured AppKit endpoint.
5. The AppKit server (planned in `zeroBus/dbxW_zerobus/`) wraps the payload and writes it to the shared `wearables_zerobus` bronze table via ZeroBus.
6. On success, `onBackgroundData()` updates Storage with sync stats displayed by the widget view.

## Wire Format

```http
POST /api/v1/garmin/ingest HTTP/1.1
Content-Type: application/json
X-Device-Id: garmin_fr265_abc123
X-Platform: garmin_connect_iq
X-Record-Type: samples
X-Upload-Timestamp: 2026-04-16T14:35:00Z
Authorization: Bearer <token>

{
  "records": [
    {"metric_type": "heart_rate_intraday", "value": 72.0, "unit": "bpm",
     "recorded_at": "2026-04-16T14:30:00Z", "device_id": "garmin_fr265_abc123",
     "source": "garmin_connect_iq"},
    ...
  ],
  "device_id": "garmin_fr265_abc123",
  "source": "garmin_connect_iq",
  "upload_timestamp": "2026-04-16T14:35:00Z"
}
```

## Testing with Simulator

```bash
# Start simulator
connectiq

# Build and run
monkeyc -f monkey.jungle -d fr265 -o bin/DbxWearables.prg -y /path/to/developer_key.der -t
monkeydo bin/DbxWearables.prg fr265
```

The simulator provides mock SensorHistory data. Set the API Base URL in the simulator's settings panel to test against a local server:

```
http://localhost:8000
```

(HTTP is allowed in the simulator but not on real Android devices.)

## Project Structure

```
connect_iq/
  manifest.xml            CIQ app manifest (widget, permissions, devices)
  monkey.jungle           Build configuration
  resources/
    strings.xml           User-facing strings
    settings.xml          Garmin Connect Mobile settings definitions
    properties.xml        Default property values
    drawables.xml         Icon references
  source/
    DbxWearablesApp.mc    AppBase: lifecycle, background registration
    DbxWearablesView.mc   Widget view: sync status display
    DbxWearablesDelegate.mc   Input: tap-to-sync
    BackgroundService.mc  ServiceDelegate: scheduled sensor collection + upload
    SensorCollector.mc    Reads SensorHistory APIs, builds record arrays
    ApiClient.mc          HTTP POST wrapper for foreground manual syncs
```
