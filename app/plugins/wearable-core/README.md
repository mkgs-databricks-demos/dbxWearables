# `wearable-core` plugin — Tier 2 (platform)

Owns the dbxWearables platform concerns: identity, credentials, bronze-row shaping, the OAuth base classes, and the connector registry. Depends on the first-party `lakebase` plugin and the Tier-1 [`zerobus`](../zerobus/README.md) plugin.

## What it owns

- **Lakebase migrations** (`migrations/001_*.sql` through `004_*.sql`) — `app_users`, `wearable_credentials`, `wearable_anchors`, `wearable_sync_runs`. Applied idempotently via [`runMigrations`](src/runMigrations.ts) on every startup.
- **`credentialStore`** — abstract interface + default `LakebaseCredentialStore`. Per-row envelope encryption for OAuth tokens.
- **`bronzeWriter`** — shapes the canonical `{record_id, ingested_at, body, headers, record_type}` bronze row, then delegates to `AppKit.zerobus.writeRow(wearablesZerobusFqn, row)`.
- **`connectorRegistry`** — in-memory registry of `WearableConnector` instances, populated by each provider plugin's `setup()`.
- **`BaseOAuth2Connector`** — PKCE flow scaffolding for Fitbit, Whoop, Oura, Withings, Strava.
- **`BaseOAuth1aConnector`** — legacy OAuth 1.0a scaffolding for the Garmin Health API.
- **Routes** — `/api/wearable-core/ingest/:platform` (phone clients), `/api/wearable-core/connections` (UI).

## Exports

```ts
const AppKit = await createApp({
  plugins: [server(), lakebase(), zerobus(), wearableCore()],
});

// 1. Look up tokens via the credential store
const creds = await AppKit.wearableCore.credentialStore.get(userId, "garmin");

// 2. Write a bronze row from any provider plugin
await AppKit.wearableCore.bronzeWriter.write({
  provider: "garmin",
  userId,
  deviceId: "garmin_forerunner_265",
  recordType: "daily_stats",
  body: rawGarminApiResponse,
});

// 3. Register a connector (every provider plugin does this in setup())
AppKit.wearableCore.connectorRegistry.register(new GarminConnector(...));

// 4. Run plugin-owned migrations
await AppKit.wearableCore.runMigrations("garmin", "./plugins/garmin/migrations");
```

## Required resources (manifest)

| Alias | Type | Permission | Purpose |
| --- | --- | --- | --- |
| `lakebase` | database | `CAN_CONNECT_AND_CREATE` | Where the platform tables live |
| `signingKey` | secret | `READ` | Envelope-encryption key for OAuth tokens |
| `bronzeTable` | secret | `READ` | FQN of `wearables_zerobus` (from infra bundle) |

## Bronze row wire format

Every row written through `bronzeWriter.write(...)` produces the same column shape:

```json
{
  "record_id": "uuid",
  "ingested_at": "2026-04-16T14:35:00Z",
  "body": "<JSON string — original vendor payload wrapped with source metadata>",
  "headers": "<JSON string — see headers contract below>",
  "record_type": "daily_stats"
}
```

### Headers contract (VARIANT `headers` column)

Every connector (and every phone client) sets the same headers so silver can dispatch without conditionals:

| Header | Required | Description |
| --- | --- | --- |
| `Content-Type` | yes | `application/json` |
| `X-Platform` | yes | Provider identifier: `garmin_connect`, `garmin_connect_iq`, `fitbit`, `whoop`, `oura`, `withings`, `strava`, `apple_healthkit`, `google_health_connect`, `samsung_health` |
| `X-Record-Type` | yes | Vendor-specific record type (`daily_stats`, `sleep`, `workout`, `samples`, ...) |
| `X-Device-Id` | yes | Device identifier reported by the source |
| `X-User-Id` | yes | Platform-scoped UUID from `app_users` (empty string for dev `_dev` user only) |
| `X-Upload-Timestamp` | yes | ISO 8601 UTC upload time |
| `X-Provider-User-Id` | no | Vendor's user ID — useful for webhook-only paths where we resolve user from `wearable_credentials` |

## Migrations

The platform tables are managed by this plugin's `setup()` via the shared `runMigrations` helper. The same helper is exported for any future plugin that owns its own tables — call it with your plugin's namespace:

```ts
async setup() {
  await this.appkit.wearableCore.runMigrations(
    "my-plugin",
    path.join(__dirname, "./migrations"),
  );
}
```

The helper tracks applied versions in an `appkit_migrations (namespace, version, applied_at)` table. Plugin ownership of tables is never coupled to `wearable-core`.

## Routes

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/wearable-core/connections` | Returns all registered connectors + the current user's enrollment state for each, for the Connections UI |
| `POST` | `/api/wearable-core/ingest/:platform` | Generic ingest endpoint for phone-SDK clients (HealthKit, Health Connect, Samsung Health). Validates required headers and streams through `bronzeWriter` |
