# dbxW_zerobus_app — Session Summary

## Session: ZeroBus HealthKit Ingestion Routes Implementation

**Date:** 2026-04-17
**Branch:** `mg-main-zerobus-app`

---

### What Was Built

Implemented the core ZeroBus ingestion gateway — the Express route and service layer that bridges the iOS HealthKit demo app with the `wearables_zerobus` bronze table via the `@databricks/zerobus-ingest-sdk`. This is the critical missing piece that connects the already-built iOS app (POST NDJSON) to the already-provisioned infrastructure (secret scope, service principal, bronze table).

---

### Changes Made

#### 1. ZeroBus Service Singleton (`server/services/zerobus-service.ts`)

Created a service class that manages the ZeroBus SDK lifecycle:

- **Lazy initialization** — SDK + stream created on first ingest request, not at startup. Concurrent requests share the same initialization promise.
- **Record builder** — `buildRecord(body, headers, recordType)` constructs a `WearablesRecord` matching the bronze table schema:
  - `record_id`: `crypto.randomUUID()` (STRING, PK)
  - `ingested_at`: `Date.now() * 1000` — epoch microseconds (TIMESTAMP)
  - `body`: `JSON.stringify(parsedLine)` — VARIANT as JSON-encoded string
  - `headers`: `JSON.stringify(headerObj)` — VARIANT as JSON-encoded string
  - `record_type`: from `X-Record-Type` header (STRING)
- **Batch ingest** — `ingestRecords(records)` iterates records, calls `stream.ingestRecordOffset()`, then `stream.waitForOffset(lastOffset)` to block until durable.
- **Env var validation** — `checkEnv()` reports which of the 5 required env vars are missing.
- **Graceful shutdown** — `close()` cleanly closes the stream on SIGTERM.

**Key design decision — VARIANT column encoding:** Per ZeroBus Ingest docs, VARIANT columns must be ingested as JSON-encoded strings. The `body` and `headers` fields are `JSON.stringify()`'d before being sent to the SDK. The SDK in `RecordType.Json` mode then serializes the full record to JSON, producing properly escaped string values for the VARIANT columns.

**Key design decision — TIMESTAMP encoding:** The type mapping table in the ZeroBus docs maps TIMESTAMP to int64 (epoch microseconds). JavaScript `Date.now()` returns milliseconds, so we multiply by 1000.

#### 2. HealthKit Ingestion Routes (`server/routes/zerobus/ingest-routes.ts`)

Created Express routes following the AppKit `server.extend()` pattern from the existing `todo-routes.ts`:

**POST `/api/v1/healthkit/ingest`**
- Validates `X-Record-Type` header against allowed values: `samples`, `workouts`, `sleep`, `activity_summaries`, `deletes`
- Parses NDJSON body using `express.text()` middleware (handles `application/x-ndjson`, `application/ndjson`, `text/plain`)
- Splits body by newlines, validates each line as JSON, collects parse errors
- Extracts a sanitized subset of HTTP headers for storage (X-Record-Type, X-Device-Id, X-Sync-Session-Id, etc.)
- Builds `WearablesRecord` per valid NDJSON line
- Batch-ingests via `zeroBusService.ingestRecords()` (blocks until durable)
- Returns JSON response compatible with iOS `APIResponse.swift`:
  - `{ status, message, record_id?, records_ingested, record_ids[], duration_ms, parse_warnings? }`
  - Single-record requests include top-level `record_id` for backwards compatibility

**GET `/api/v1/healthkit/health`**
- Returns env var configuration status and target table name
- No authentication required — useful for readiness probes

**Graceful shutdown:**
- Registers `SIGTERM` handler to close the ZeroBus stream cleanly

#### 3. Updated Server Entry Point (`server/server.ts`)

Added import for `setupZeroBusRoutes` and wired it into the `createApp` chain after `setupSampleLakebaseRoutes` and before `appkit.server.start()`.

#### 4. Added ZeroBus SDK Dependency (`package.json`)

Added `@databricks/zerobus-ingest-sdk: "*"` to dependencies. Version will resolve on next `npm install`. The SDK wraps the high-performance Rust SDK via NAPI-RS native bindings.

**Note:** Per proxy conventions, NO npm registry proxy was added — Databricks Apps have their own package mirror.

---

### Design Decisions

#### Singleton Stream Pattern

The ZeroBus stream is expensive to create (OAuth handshake, gRPC connection). A singleton service with lazy initialization reuses the stream across all HTTP requests. Concurrent requests during initialization share the same promise — no duplicate streams.

#### NDJSON Parsing Strategy

The iOS app sends batched NDJSON payloads (one JSON object per line). The route uses `express.text()` middleware to receive the raw body, then splits and parses line-by-line. Valid lines are ingested; invalid lines produce warnings but don't block the batch.

#### Response Compatibility

The iOS `APIResponse.swift` model has `{ status, message, record_id? }`. The batch response adds `records_ingested`, `record_ids[]`, and `duration_ms` — Swift's `Codable` decoder ignores unknown keys by default, so this is backwards compatible.

#### Header Preservation

A curated subset of HTTP headers is stored alongside each record in the VARIANT `headers` column. This preserves request context for debugging, deduplication, and audit without storing sensitive infrastructure headers.

---

### Files Created / Modified

| File | Status | Description |
| --- | --- | --- |
| `src/app/server/services/zerobus-service.ts` | Created | ZeroBus SDK singleton — lazy init, record builder, batch ingest, shutdown |
| `src/app/server/routes/zerobus/ingest-routes.ts` | Created | POST /api/v1/healthkit/ingest + GET health endpoint |
| `src/app/server/server.ts` | Modified | Added ZeroBus route import and wiring |
| `src/app/package.json` | Modified | Added @databricks/zerobus-ingest-sdk dependency |

### Bundle Structure (Updated)

```
dbxW_zerobus_app/
├── databricks.yml
├── README.md
├── .gitignore
├── resources/
│   └── zerobus_ingest.app.yml
├── fixtures/
│   ├── sessions/
│   │   ├── INDEX.md
│   │   ├── 2026-04-17_app-bundle-scaffold.md
│   │   ├── 2026-04-17_appkit-gateway-migration.md
│   │   └── 2026-04-17_zerobus-ingestion-routes.md    ← NEW
│   └── AppKit App Bundle Setup Session.ipynb
└── src/
    └── app/
        ├── app.yaml
        ├── appkit.plugins.json
        ├── package.json                                ← MODIFIED
        ├── server/
        │   ├── server.ts                               ← MODIFIED
        │   ├── services/                               ← NEW
        │   │   └── zerobus-service.ts                  ← NEW
        │   └── routes/
        │       ├── lakebase/
        │       │   └── todo-routes.ts
        │       └── zerobus/                            ← NEW
        │           └── ingest-routes.ts                ← NEW
        ├── client/
        └── tests/
```

### Next Steps

1. **Run `npm install`** — resolve and lock `@databricks/zerobus-ingest-sdk` version
2. **Deploy dev target** — `databricks bundle deploy -t dev` to deploy the app
3. **Verify `/api/v1/healthkit/health`** — confirm env vars are injected
4. **Test with curl** — send sample NDJSON payload to the ingest endpoint
5. **Connect iOS app** — set `DBX_API_BASE_URL` to the deployed app URL
6. **Verify data in bronze table** — `SELECT * FROM hls_fde_dev.dev_matthew_giglia_wearables.wearables_zerobus`
7. **Define Spark Declarative Pipelines** — silver/gold processing (planned resource)
