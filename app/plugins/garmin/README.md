# `garmin` plugin — Tier 3 (reference connector)

Full reference implementation of a cloud-API wearable connector for Garmin Connect + Garmin Health API. Every other provider plugin (`fitbit`, `whoop`, `oura`, `withings`, `strava`) mirrors this structure.

## What it provides

- **OAuth 1.0a flow** (Garmin Health API still uses OAuth 1.0a as of early 2026). Extends [`BaseOAuth1aConnector`](../wearable-core/src/baseOAuth1aConnector.ts).
- **Webhook PING → PULL handler** for Garmin's "we pinged you, now fetch the detail" pattern. HMAC signature verification.
- **OAuth start / callback / revoke routes** mounted under `/api/garmin/...`.
- **Registers with `AppKit.wearableCore.connectorRegistry`** on startup so the Connections UI picks it up automatically.
- **Record types** (aligned with `providers/garmin/schema.md`): `daily_stats`, `sleep`, `heart_rates`, `stress`, `hrv`, `spo2`, `body_battery`, `steps`, `respiration`, `activities`, and the watch-side `samples`.

## Paths

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/garmin/oauth/start` | Mints request token, redirects user to Garmin consent |
| `GET` | `/api/garmin/oauth/callback` | Exchanges verifier for access token, persists via `credentialStore` |
| `POST` | `/api/garmin/webhook/:recordType` | Garmin Health API PING; plugin PULLs the detail and writes bronze rows |
| `POST` | `/api/garmin/revoke` | Calls Garmin revoke endpoint + marks `wearable_credentials` row revoked |

## Manifest resources

All three are `optional` — they only become *required* when Garmin is enabled in plugin config via `getResourceRequirements({ enabled: true })`. A customer who only wants Fitbit doesn't need to provision Garmin credentials.

| Alias | Type | Env binding | Purpose |
| --- | --- | --- | --- |
| `clientId` | secret | `GARMIN_CLIENT_ID` | OAuth 1.0a consumer key (from Garmin Developer Program) |
| `clientSecret` | secret | `GARMIN_CLIENT_SECRET` | OAuth 1.0a consumer secret |
| `webhookSecret` | secret | `GARMIN_WEBHOOK_SECRET` | HMAC-SHA256 key for webhook signature verification |

## Two credential paths

**Production (official path):** Garmin Connect Developer Program OAuth 1.0a flow via the routes above. Requires Garmin approval of your consumer key.

**Dev fallback (garth):** For local demos before official approval, [`providers/garmin/scripts/upload_garmin_tokens.sh`](../../../providers/garmin/scripts/upload_garmin_tokens.sh) runs a one-time `garth login` in your terminal and writes the resulting OAuth tokens into `wearable_credentials` under a synthetic `_dev` user. Every other platform code path — fanout notebook, silver pipeline, Connections UI — exercises identically whether the tokens came from the official OAuth flow or garth.

## Pull path

The Lakeflow `wearable_daily_fanout.ipynb` job discovers enrolled Garmin users via `wearable_credentials WHERE provider = 'garmin'` and delegates to the Python pull connector at [`providers/garmin/pull/`](../../../providers/garmin/pull/). Both the webhook handler (TS side) and `pull_batch` (Python side) write the **same bronze row shape** via [`bronzeWriter`](../wearable-core/src/bronzeWriter.ts) / `zerobus.writeRow` — silver doesn't distinguish webhook vs pull.

## Connect IQ watch widget

The watch-side widget at [`providers/garmin/connect_iq/`](../../../providers/garmin/connect_iq/) POSTs to `/api/wearable-core/ingest/garmin_connect_iq` — the generic phone-SDK route on `wearable-core`. The watch sends data via the paired phone's BLE bridge, so even though a phone is technically in the loop, there's no Apple Health / Google Health conversion step.
