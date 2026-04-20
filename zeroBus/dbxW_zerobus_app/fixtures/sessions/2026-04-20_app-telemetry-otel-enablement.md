## Session: App Telemetry & OpenTelemetry Enablement

**Date:** 2026-04-20  
**Bundle:** `dbxW_zerobus_app`  
**Target:** `dev`  
**Scope:** Enable Databricks App Telemetry (Beta) with custom OpenTelemetry instrumentation for the ZeroBus ingest app

---

### Problem Statement

The ZeroBus ingest app (`dev-dbxw-0bus-ingest`) had no persistent observability. Realtime logs were available via `/logz` but lost on compute shutdown. No traces or metrics were captured for debugging request flows or monitoring performance.

### Solution

Enabled the Databricks App Telemetry (Beta) feature, which uses ZeroBus Ingest under the hood to stream OTel data to Unity Catalog Delta tables. Added custom OpenTelemetry Node.js SDK instrumentation to auto-instrument Express, HTTP, Postgres, and net modules.

### Key Findings & Decisions

1. **No infra bundle changes required** — The existing schema grants (`ALL_PRIVILEGES` for the deploying user in both dev and hls_fde targets) satisfy the telemetry requirements (CAN MANAGE + CREATE TABLE on schema).

2. **Terraform provider schema differs from docs** — The documentation describes enabling telemetry via UI with catalog/schema/prefix. The actual Terraform provider (used by DABs) expects:
   ```yaml
   telemetry_export_destinations:
     - unity_catalog:
         logs_table: <fully_qualified_name>
         traces_table: <fully_qualified_name>
         metrics_table: <fully_qualified_name>
   ```
   NOT `unity_catalog_table` with `catalog_name`/`schema_name`/`table_name_prefix`.

3. **CLI schema warnings are expected** — The CLI's JSON schema validator doesn't yet recognize the inner structure of `TelemetryExportDestination` for this beta feature. Warnings appear but don't block deployment.

4. **Table naming** — The provider uses `traces_table` (not `spans_table`), creating `*_otel_traces` (not `*_otel_spans` as the docs suggest for the UI flow).

5. **SIGTERM handling** — The OTel shutdown hook must NOT call `process.exit(0)` — doing so short-circuits AppKit's graceful shutdown (HTTP server close, Lakebase pool drain), causing the platform's 15-second SIGTERM timeout error on redeployments.

6. **ESM preload** — Since the project uses `"type": "module"`, the OTel bootstrap file is loaded via `node --import ./dist/otel.js` (not `-r` which is CJS-only).

### Changes Made

| File | Change |
| --- | --- |
| `databricks.yml` | Added `telemetry_table_prefix` variable (default: `dbxw_0bus_ingest`) |
| `resources/zerobus_ingest.app.yml` | Added `telemetry_export_destinations` with `unity_catalog` structure; updated header docs |
| `src/app/app.yaml` | Added `OTEL_TRACES_SAMPLER: always_on` env var; documented platform-injected OTel env vars |
| `src/app/server/otel.ts` | **New** — OTel SDK bootstrap (NodeSDK, trace/metric/log OTLP proto exporters, auto-instrumentations for HTTP/Express/pg/net, graceful flush on SIGTERM without process.exit) |
| `src/app/tsdown.server.config.ts` | Added `server/otel.ts` as second entry point |
| `src/app/package.json` | Added 8 `@opentelemetry/*` deps; updated `start` script to `node --import ./dist/otel.js` |

### Telemetry Tables Created

| Table | Status | Data Flowing |
| --- | --- | --- |
| `hls_fde_dev.dev_matthew_giglia_wearables.dbxw_0bus_ingest_otel_logs` | Active | System logs + app console output |
| `hls_fde_dev.dev_matthew_giglia_wearables.dbxw_0bus_ingest_otel_traces` | Active | HTTP client spans, pg.connect, pg.query, Lakebase token refresh, TLS/TCP |
| `hls_fde_dev.dev_matthew_giglia_wearables.dbxw_0bus_ingest_otel_metrics` | Active | http.client.duration, db.client.operation.duration, db.client.connection.count, nodejs.eventloop.time |

### Auto-Instrumentations Active

| Package | Version | Captures |
| --- | --- | --- |
| `@opentelemetry/instrumentation-http` | 0.208.0 | Outbound HTTP request spans + duration histograms |
| `@opentelemetry/instrumentation-pg` | 0.61.2 | Postgres connect, query, pool, connection count |
| `@opentelemetry/instrumentation-net` | 0.53.0 | TCP/TLS connect spans |
| `@opentelemetry/instrumentation-runtime-node` | 0.22.0 | Event loop time (active/idle) |
| `@databricks/lakebase` | (built-in) | Lakebase token refresh spans |

### Deployment Iterations

1. **Attempt 1** — Used `unity_catalog_table` with `catalog_name`/`schema_name`/`table_name_prefix`. CLI warned about unknown fields; Terraform errored with schema mismatch revealing the correct structure.
2. **Attempt 2** — Used flat `catalog_name`/`schema_name`/`table_name_prefix` (no wrapper). CLI warned; same Terraform error.
3. **Attempt 3** — Used `unity_catalog` with `logs_table`/`traces_table`/`metrics_table` (fully qualified names). Clean validation, successful deploy.
4. **Attempt 4** — Fixed SIGTERM handler (removed `process.exit(0)`). Clean deploy.

### Post-Deploy Verification

- `[otel] OpenTelemetry SDK initialized` confirmed in logs at 17:20:49 UTC
- All 3 tables populated within seconds of app start
- Single trace ID (`d733c52ecdde2ecc97c9571addfaa30f`) covers full startup span tree
- Only 1 ERROR log (SIGTERM timeout from previous instance during hot swap — expected, now mitigated)

### Recommendations

- Enable **predictive optimization** on the 3 OTel tables for better query performance
- Consider adding `@opentelemetry/instrumentation-express` explicitly if Express route-level spans are desired (currently only HTTP client spans are captured)
- The `OTEL_TRACES_SAMPLER: always_on` setting captures 100% of traces — adjust to `parentbased_traceidratio` with a ratio if volume becomes excessive
