# Garmin Pull -- Daily Historical Ingestion

Pull comprehensive health data from Garmin Connect cloud API and push to the shared `wearables_zerobus` bronze table in Databricks via ZeroBus.

## How It Works

1. **One-time setup:** Run `make garmin-login` to authenticate with Garmin Connect. This uses your email/password (+ MFA if enabled) to obtain OAuth tokens, which are saved to `~/.garminconnect/garmin_tokens.json`.
2. **Upload tokens to Databricks Secrets:** Run `make setup-secrets` to push the token file to the shared secret scope. This is the only copy of your credentials that persists -- your email and password are never stored.
3. **Daily ingestion:** The runner (or a Databricks notebook) pulls yesterday's data from the Garmin Connect API and pushes raw JSON payloads to ZeroBus, which writes them to the `wearables_zerobus` bronze table as VARIANT.
4. **Token refresh:** The `python-garminconnect` library automatically refreshes the access token using the stored refresh token (~30-day validity, rotating on each use).

## Prerequisites

- Python >= 3.11
- A Garmin Connect account with a paired Garmin device
- **Deploy `zeroBus/dbxW_zerobus_infra` bundle first** (creates schema, table, secrets, service principal)
- Databricks CLI configured (for secret management)

## Quick Start

```bash
cd garmin/pull

# Install dependencies
make setup

# Set credentials in environment (one-time)
export GARMIN_EMAIL=your-email@example.com
export GARMIN_PASSWORD=your-password

# Authenticate to Garmin Connect (saves OAuth tokens locally)
make garmin-login

# Test extraction without pushing to Databricks
make ingest-dry-run

# Write silver-layer events to a local JSON file for inspection
make ingest-to-file

# Push tokens to Databricks Secrets (shared scope)
make setup-secrets
```

## Running Locally

```bash
# Ingest yesterday's data
python -m garmin.pull.runner

# Ingest a specific date
python -m garmin.pull.runner --date 2026-04-10

# Dry run (extract + build bronze rows, print summary, don't push)
python -m garmin.pull.runner --date 2026-04-10 --dry-run

# Write silver-layer normalized events to file
python -m garmin.pull.runner --date 2026-04-10 --output events.json
```

## Running as a Databricks Notebook

See [`../notebooks/01_ingest_garmin.ipynb`](../notebooks/01_ingest_garmin.ipynb) for a notebook that:
- Reads Garmin tokens from the shared `dbxw_zerobus_credentials` secret scope
- Pulls daily data via `python-garminconnect`
- Wraps raw API responses as VARIANT-compatible rows
- Pushes to the `wearables_zerobus` bronze table via ZeroBus
- Writes refreshed tokens back to Secrets

For testing without ZeroBus, use [`../notebooks/03_ingest_garmin_direct.ipynb`](../notebooks/03_ingest_garmin_direct.ipynb) which writes directly to Delta with `parse_json()`.

## Backfilling

```bash
# Backfill a date range
START_DATE=2026-03-01 END_DATE=2026-04-01 make backfill
```

Or use the backfill notebook: [`../notebooks/02_backfill_garmin.ipynb`](../notebooks/02_backfill_garmin.ipynb).

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `GARMIN_EMAIL` | For first login | Garmin Connect email |
| `GARMIN_PASSWORD` | For first login | Garmin Connect password |
| `GARMIN_TOKENSTORE` | No | Token storage directory (default: `~/.garminconnect`) |
| `GARMIN_DEVICE_ID` | No | Device identifier (default: `garmin_forerunner_265`) |
| `ZEROBUS_SERVER_ENDPOINT` | For push | ZeroBus endpoint URL |
| `DATABRICKS_WORKSPACE_URL` | For push | Databricks workspace URL |
| `DATABRICKS_CLIENT_ID` | For push | Service principal client ID |
| `DATABRICKS_CLIENT_SECRET` | For push | Service principal client secret |
| `DATABRICKS_CATALOG` | Yes | Unity Catalog name (no default) |
| `DATABRICKS_SCHEMA` | No | Schema name (default: `wearables`) |
| `DATABRICKS_BRONZE_TABLE` | No | Bronze table name (default: `wearables_zerobus`) |

## Data Extracted

All 10 Garmin API endpoints are pulled for comprehensive coverage. Each response is stored as raw JSON in the bronze table's `body` VARIANT column. See [../schema.md](../schema.md) for the full field mapping.

## Security

- Your Garmin email and password are only used once during `make garmin-login` and are never stored.
- OAuth tokens (access + refresh) are saved to `~/.garminconnect/garmin_tokens.json` locally and to the shared `dbxw_zerobus_credentials` Databricks secret scope for notebook use.
- The refresh token auto-rotates on each use, so a stolen token becomes invalid after the next legitimate refresh.
- ZeroBus credentials (service principal) are stored in the same shared secret scope, provisioned by the `dbxW_zerobus_infra` bundle.
