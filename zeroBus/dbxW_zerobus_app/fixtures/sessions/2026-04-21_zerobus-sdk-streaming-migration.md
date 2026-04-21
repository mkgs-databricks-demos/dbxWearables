# dbxW_zerobus_app — Session Summary

## Session: ZeroBus SDK Streaming Migration & Enterprise-Scale Architecture

**Date:** 2026-04-21
**Bundle:** `dbxW_zerobus_app` (with cross-bundle changes to `dbxW_zerobus_infra`)

---

### Problem Statement

The ZeroBus ingestion service used a REST API transport (`fetch()` POST to `/zerobus/v1/tables/{table}/insert`) with manual OAuth M2M token management. This approach had per-request HTTP overhead, no streaming semantics, no backpressure, and no durability guarantees beyond an HTTP 200. The system needed to scale to enterprise levels — potentially millions of iOS mobile users syncing HealthKit data concurrently.

### Root Cause of Original REST Approach

The `@databricks/zerobus-ingest-sdk` (Rust/NAPI-RS native bindings) was previously attempted but failed in the Databricks Apps runtime due to missing native binaries. The REST API was implemented as a fallback. This session assumes the NAPI-RS compatibility issue has been resolved.

### Changes Made

#### 1. `zerobus-service.ts` — Full Rewrite (REST to SDK Streaming)

**Before:** Stateless `fetch()` POST per batch, manual OAuth token cache with 5-minute refresh, `parseTableName()` and `extractWorkspaceId()` helper methods for token scoping.

**After:**
- `ZerobusSdk` + `createStream()` with persistent gRPC connections
- **Stream pool** — configurable N streams (default 4, env `ZEROBUS_STREAM_POOL_SIZE`), round-robin selection per Express request
- **Lazy initialization** — pool created on first ingest request, concurrent callers await the same init promise
- **Offset-based durability** — `ingestRecordOffset()` queues records, `waitForOffset()` blocks until durable commit to Delta table
- **In-flight tracking** — `inflight` counter + `draining` flag for graceful shutdown
- **Drain logic** — on `close()`: set `draining=true` (reject new requests), poll until `inflight=0` (30s timeout), then `stream.close()` on all streams (flushes SDK buffers, waits for acks)
- **Removed:** approximately 120 lines of manual OAuth, URL parsing, `TokenCache` interface, `fetch()` transport
- **Added:** `IngestStream` interface, `poolStatus()` method, `DRAIN_TIMEOUT_MS` / `DRAIN_POLL_INTERVAL_MS` constants

#### 2. `ingest-routes.ts` — Targeted Updates

- Module header: "REST API" changed to "TypeScript SDK (gRPC streaming)"
- Step 6 comment: "Batch-ingest via ZeroBus SDK stream (offset-based durability)"
- Success response: added `durable: true` field (offset-confirmed commit)
- Health check: added `stream_pool` object (`pool_size`, `active_streams`, `initialized`, `inflight_requests`, `draining`)
- Startup/SIGTERM logs reference "stream pool"
- All helper functions, middleware, validation logic **unchanged**

#### 3. `package.json` — Added SDK Dependency

- Added `"@databricks/zerobus-ingest-sdk": "*"` to dependencies
- Version will be pinned by `package-lock.json` after first `npm install`

#### 4. `databricks.yml` (app bundle) — Pool Size Variable

- Added `zerobus_stream_pool_size` variable (default: `"4"`)
- Dev target override: `"2"`

#### 5. `zerobus_ingest.app.yml` — Secret Resource

- Added `zerobus-stream-pool-size` secret resource reading key `zerobus_stream_pool_size` from scope `${var.secret_scope_name}`
- Follows the same pattern as the other 5 secret resources

#### 6. `app.yaml` — Env Var Mapping

- Added `ZEROBUS_STREAM_POOL_SIZE` with `valueFrom: zerobus-stream-pool-size`
- Updated header comment listing

#### 7. `dbxW_zerobus_infra/databricks.yml` — Pool Size Variable (Cross-Bundle)

- Added `zerobus_stream_pool_size` variable (default: `"4"`, dev: `"2"`)
- Placed after `client_secret_dbs_key`, before `run_as_user`

#### 8. `dbxW_zerobus_infra/resources/uc_setup.job.yml` — Job Parameter

- Added `zerobus_stream_pool_size` parameter with default `${var.zerobus_stream_pool_size}`
- Updated header comment and job description

#### 9. `dbxW_zerobus_infra/src/uc_setup/ensure-service-principal` — Notebook Cells

- **Markdown cell:** Added "Stream pool size" row to auto-provisioned keys table
- **Read Job Parameters cell:** Added `zerobus_stream_pool_size = dbutils.widgets.get("zerobus_stream_pool_size")`
- **Provision Secret Scope cell:** Added `"zerobus_stream_pool_size": zerobus_stream_pool_size` to `secrets_to_store` dict, added print line
- **Summary cell:** Added pool size to summary output

### Design Decisions

1. **Fixed pool, not dynamic** — The stream pool opens N streams at startup and round-robins across them. No auto-scaling. The ZeroBus docs explicitly state "your scaling strategy is to open more connections." For elastic scaling, horizontal scaling of the Databricks App (multiple instances) is the right lever.

2. **Secret scope for config** — `ZEROBUS_STREAM_POOL_SIZE` is a non-sensitive integer, but the secret scope is the only mechanism that connects DAB bundle variables to app env vars via `valueFrom`. The service falls back to `DEFAULT_POOL_SIZE = 4` if the key is missing.

3. **Three-phase graceful shutdown** — (1) drain gate rejects new requests, (2) in-flight poll waits for active handlers, (3) `stream.close()` flushes SDK buffers. Guarantees every record accepted before SIGTERM is durably committed, even during redeploy.

4. **`IngestStream` explicit interface** — Rather than deriving the type from `ZerobusSdk['createStream']`, we declare a minimal interface (`ingestRecordOffset`, `waitForOffset`, `close`). Avoids coupling to NAPI-RS internal types.

5. **Cross-bundle provisioning chain** — infra bundle variable to UC setup job param to `ensure-service-principal` stores in scope to app resource reads from scope to `app.yaml` `valueFrom` to env var to service constructor.

### Files Modified

| File | Bundle | Change Type |
| --- | --- | --- |
| `src/app/server/services/zerobus-service.ts` | app | Full rewrite (REST to SDK streaming pool + drain) |
| `src/app/server/routes/zerobus/ingest-routes.ts` | app | Comments, `durable: true`, health check pool status |
| `src/app/package.json` | app | Added `@databricks/zerobus-ingest-sdk` |
| `databricks.yml` | app | Added `zerobus_stream_pool_size` variable |
| `resources/zerobus_ingest.app.yml` | app | Added `zerobus-stream-pool-size` secret resource |
| `src/app/app.yaml` | app | Added `ZEROBUS_STREAM_POOL_SIZE` env var |
| `databricks.yml` | infra | Added `zerobus_stream_pool_size` variable |
| `resources/uc_setup.job.yml` | infra | Added job parameter |
| `src/uc_setup/ensure-service-principal` (notebook) | infra | 4 cells updated (markdown, params, scope, summary) |

### Next Steps

- Run `npm install` in `src/app/` to resolve and pin the SDK version
- Deploy infra bundle and run UC setup job to populate `zerobus_stream_pool_size` in scope
- Deploy app bundle and verify stream pool initializes on first ingest request
- Load test with concurrent iOS POST requests to validate pool throughput
- Consider adding stream health monitoring and reconnection logic for production resilience
