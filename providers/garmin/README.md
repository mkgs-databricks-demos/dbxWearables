# Garmin provider — reference connector

Full reference implementation of a dbxWearables cloud-API connector. Other cloud-API providers (`providers/fitbit/`, `providers/whoop/`, etc.) mirror this structure.

Garmin data reaches the shared `wearables_zerobus` bronze table through three complementary paths:

| Path | Where the code lives | Status |
| --- | --- | --- |
| Garmin Health API webhook (push) | [`app/plugins/garmin/`](../../app/plugins/garmin/) — AppKit Tier-3 plugin | Skeleton authored, not yet live |
| Garmin Connect pull (daily batch) | [`providers/garmin/pull/`](pull/) — python-garminconnect / garth | Working (single-user today; fanout-ready) |
| Connect IQ watch widget (on-device) | [`providers/garmin/connect_iq/`](connect_iq/) — Monkey C widget POSTs to `/api/wearable-core/ingest/garmin_connect_iq` | Working |

All three paths produce the same bronze row shape via the `wearable-core` `bronzeWriter`, so silver dispatches on `X-Platform` without branching per path.

## Prerequisites

Deploy the shared infrastructure bundle **before** using any Garmin integration path:

```bash
cd ../../zeroBus
./deploy.sh --target dev
```

This creates the Unity Catalog schema, `wearables_zerobus` table, secret scope, service principal, and SQL warehouse that every wearable provider depends on.

## Integration paths

### Path 1: Connect IQ watch widget (real-time)

A Monkey C widget with a background service that runs on the Garmin watch. Every 5 minutes it reads the latest sensor history and POSTs a JSON payload to the AppKit gateway's generic phone-SDK endpoint (`POST /api/wearable-core/ingest/garmin_connect_iq`) through the phone's Bluetooth connection.

**Data available on-device:**
- Heart rate (continuous)
- Stress level
- Body battery
- SpO2 (oxygen saturation)
- Steps
- Respiration rate

**Setup:** See [connect_iq/README.md](connect_iq/README.md).

### Path 2: Garmin Health API webhook (production push)

The AppKit [`garmin` plugin](../../app/plugins/garmin/README.md) handles the Garmin Health API PING → PULL pattern. Users click "Connect Garmin" in the Connections UI, go through OAuth 1.0a consent, and from then on Garmin pushes their data to our webhook within minutes of a sync. This is the production path. Skeleton is in place; live deployment requires Garmin Connect Developer Program approval.

### Path 3: Notebook pull (daily batch + backfill)

A Python-based daily pull from the Garmin Connect cloud API using the `python-garminconnect` library. Runs as a scheduled Databricks notebook job with credentials stored in the Lakebase `wearable_credentials` table (envelope-encrypted). The cross-provider [`lakeflow/wearable_daily_fanout.ipynb`](../../lakeflow/wearable_daily_fanout.ipynb) enumerates enrolled users and dispatches to [`pull/`](pull/) per user.

**Data available from cloud API (comprehensive):**
- All Path 1 metrics, plus:
- Sleep stages (deep, light, REM, awake), sleep score
- HRV (weekly average, nightly 5-min high)
- VO2 max
- Intraday heart rate time series
- Stress time series
- Activity/workout summaries (type, duration, distance, HR zones, calories)
- Floors climbed, intensity minutes

**Setup:** See [pull/README.md](pull/README.md).

## Data coverage matrix

| Metric | Connect IQ widget | Health API webhook | Notebook pull |
|--------|:-----------------:|:------------------:|:-------------:|
| Heart rate (resting) | x | x | x |
| Heart rate (intraday) | x | x | x |
| Stress level | x | x | x |
| Body battery | x | x | x |
| SpO2 | x | x | x |
| Steps | x | x | x |
| Respiration | x | x | x |
| Sleep stages | | x | x |
| Sleep score | | x | x |
| HRV | | x | x |
| VO2 max | | x | x |
| Active calories | | x | x |
| Floors climbed | | x | x |
| Intensity minutes | | x | x |
| Workouts / activities | | x | x |

## Bronze Table: `wearables_zerobus`

Both paths store raw data in the shared VARIANT-based bronze table. Each Garmin API response becomes one row with the full JSON in the `body` column. Parsing into typed metrics happens in the silver layer.

See [schema.md](schema.md) for the complete field mapping and VARIANT query examples.

## Security model

- **Connect IQ path:** An optional Bearer token is configured on the watch via Garmin Connect Mobile app settings. The token is stored in the Garmin app's secure settings storage and sent as an `Authorization` header with every POST.
- **Health API webhook path (production):** Standard Garmin Connect Developer Program OAuth 1.0a consent flow. Per-user tokens land in Lakebase `wearable_credentials`, envelope-encrypted with AES-256-GCM using the signing key declared on the `wearable-core` plugin. Webhook bodies are HMAC-SHA256 signed and verified with the `webhookSecret` resource declared on the `garmin` plugin.
- **Notebook pull path (dev fallback):** Garmin OAuth tokens (obtained via a one-time local `garth login`) are stored in the same `wearable_credentials` table under a synthetic `_dev` user. Email / password never touch Databricks. The refresh token auto-rotates on each use (~30-day validity). See [scripts/upload_garmin_tokens.sh](scripts/upload_garmin_tokens.sh) for the full credential flow.

## Architecture

```
Garmin Forerunner 265
  │
  ├── [Connect IQ widget] ──BLE──► phone ──HTTPS POST──► AppKit gateway ──► ZeroBus ──► wearables_zerobus
  │                                                        /api/wearable-core/ingest/garmin_connect_iq
  │
  └── syncs to ──► Garmin Connect Cloud
                         │
                         ├─ webhook PING ──► AppKit gateway ──► ZeroBus ──► wearables_zerobus
                         │                    /api/garmin/webhook/:recordType
                         │
                         └─ pulled by ──► [Lakeflow fanout] ──python-garminconnect──► ZeroBus ──► wearables_zerobus
                                             (reads tokens from Lakebase wearable_credentials)

                                                                           │
                                                                           ▼
                                                                     silver_health_events
                                                                     (one normalizer in providers/garmin/silver/)
```

## Notebooks

| Notebook | Purpose |
|----------|---------|
| `00_garmin_login_and_test.ipynb` | Setup + initial load. Reads `garmin_oauth_tokens` from the secret scope, creates the schema/table if missing, pulls one day of data via direct Delta write, and refreshes tokens. |
| `01_ingest_garmin.ipynb` | Daily ingestion via ZeroBus |
| `02_backfill_garmin.ipynb` | Historical backfill via ZeroBus |
| `03_ingest_garmin_direct.ipynb` | Direct Delta write (testing, no ZeroBus required) |
| `04_backfill_garmin_direct.ipynb` | Historical backfill via direct Delta write |

## Fresh-Deploy Walkthrough

From a clean workspace, the setup is four CLI steps plus one admin action.

### 0. Prerequisites

- Databricks CLI authenticated to the target workspace under a named profile.
- `databricks.local.yml` with your workspace overrides (copy from `databricks.local.yml.example`), **or** pass values on the CLI with `--profile` and `--var`. The local file is gitignored.

### 1. Deploy the shared ZeroBus infrastructure

Creates the schema, bronze table, secret scope, service principal, warehouse, and populates every ZeroBus secret except `client_secret`. See [`zeroBus/dbxW_zerobus_infra/README.md`](../../zeroBus/dbxW_zerobus_infra/README.md).

```bash
cd zeroBus/dbxW_zerobus_infra
databricks bundle deploy --target <your-target> --profile <your-profile>
databricks bundle run wearables_uc_setup --target <your-target> --profile <your-profile>
```

### 2. Generate and store the ZeroBus service-principal `client_secret`

Databricks does not return OAuth secrets from a bundle run, so this step is manual. Either use the workspace UI (*Settings → Identity and access → Service principals*) or the account-level CLI:

```bash
databricks account service-principal-secrets create <sp-workspace-id> --profile <account-profile>

databricks secrets put-secret dbxw_zerobus_credentials client_secret \
  --string-value "<generated-secret>" \
  --profile <your-profile>
```

### 3. Upload Garmin OAuth tokens (credentials never touch Databricks)

From your local machine, run the bootstrap script. It creates a throwaway Python venv, prompts for your Garmin email/password/MFA **in your terminal only**, performs an OAuth exchange with `garth`, uploads the resulting token pair to the `dbxw_zerobus_credentials` scope as `garmin_oauth_tokens`, and wipes the temp directory:

```bash
./garmin/scripts/upload_garmin_tokens.sh --profile <your-profile>
```

No notebook widgets, no job parameters, no plaintext credentials anywhere on disk or in Databricks. Only the OAuth tokens are persisted, encrypted at rest in the secret scope.

### 4. Deploy the Garmin ingestion bundle

```bash
cd garmin
databricks bundle deploy --target dev
```

### 5. Run the jobs

```bash
# One-time setup + initial load
databricks bundle run garmin_setup --target dev

# Daily ingestion via ZeroBus (scheduled; also runnable on demand)
databricks bundle run garmin_daily_ingest --target dev

# Historical backfill via ZeroBus
databricks bundle run garmin_backfill --target dev \
  --params start_date=2026-03-01,end_date=2026-04-16
```

The direct-write jobs (`garmin_daily_direct`, `garmin_backfill_direct`) work identically but skip ZeroBus; use them while `client_secret` is still being provisioned.

### Token rotation

`garth` refreshes the OAuth2 token on every API call. The notebooks write the refreshed pair back to the secret scope at the end of each run, so scheduled jobs keep themselves alive indefinitely. Re-run `upload_garmin_tokens.sh` only if the refresh token is revoked (e.g. you changed your Garmin password).
