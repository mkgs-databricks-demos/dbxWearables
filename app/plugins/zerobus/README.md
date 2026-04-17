# `zerobus` plugin — Tier 1 (generic)

Wraps [`databricks-zerobus-ingest-sdk`](https://docs.databricks.com/aws/en/ingestion/zerobus-ingest/) in an AppKit plugin that exposes a single per-process stream pool, automatic retries, and OpenTelemetry metrics. Has **no opinion on row shape** — callers supply any schema.

This plugin is domain-agnostic. The wearable-specific bronze row shape (`{record_id, ingested_at, body, headers, record_type}`) is layered on top in the `wearable-core` plugin's `bronzeWriter`. Keeping ZeroBus generic here makes this plugin a candidate for contribution back to the [AppKit project](https://github.com/databricks/appkit) as `@databricks/appkit-zerobus`.

## Exports

```ts
const AppKit = await createApp({
  plugins: [server(), zerobus()],
});

await AppKit.zerobus.writeRow("hls_fde_dev.wearables.wearables_zerobus", {
  record_id: "…",
  ingested_at: new Date().toISOString(),
  body: "{ … }",
  headers: "{ … }",
  record_type: "daily_stats",
});

// Multiple rows with automatic batching
await AppKit.zerobus.writeRows(tableFqn, rows);

// Flush before shutdown
await AppKit.zerobus.flush();
```

One stream is opened per table FQN and reused across callers. Retries use exponential backoff on transient errors.

## Required resources (manifest)

| Alias | Type | Env binding | Description |
| --- | --- | --- | --- |
| `clientId` | secret | `ZEROBUS_CLIENT_ID` | Service principal client_id for ZeroBus OAuth M2M |
| `clientSecret` | secret | `ZEROBUS_CLIENT_SECRET` | OAuth M2M client_secret |
| `workspaceUrl` | secret | `ZEROBUS_WORKSPACE_URL` | Databricks workspace URL |
| `endpoint` | secret | `ZEROBUS_ENDPOINT` | Region-specific ZeroBus ingest endpoint |

All four are provisioned by [`zeroBus/dbxW_zerobus_infra`](../../../zeroBus/dbxW_zerobus_infra/README.md) into the `dbxw_zerobus_credentials` secret scope. Wire them through `app.yaml` `valueFrom` — see [`../../SETUP.md`](../../SETUP.md) Step 4.

## Configuration options

```ts
zerobus({
  // Max in-flight records per stream before applying backpressure. Default 50.
  maxInflightRequests: 50,
  // Max concurrent streams (tables) to hold open. Default 8.
  maxStreams: 8,
  // Retry policy
  retry: { maxAttempts: 3, baseDelayMs: 400 },
})
```
