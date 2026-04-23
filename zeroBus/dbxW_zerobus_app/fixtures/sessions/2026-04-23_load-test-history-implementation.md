## Session: Load Test History Implementation

**Date:** 2026-04-23
**Bundle:** `dbxW_zerobus_app`

### Summary

Implemented the full Load Test History feature across 3 new files and 5 modified files. The system now records every load test run to Lakebase (Postgres) with structured metadata, which Lakehouse Sync (wal2delta CDC) automatically replicates to Unity Catalog Delta tables as SCD Type 2 history.

### Architecture

```
LoadTestPage (React)
  │ POST /load-test/stream { counts, batchSize, presetLabel }
  │ (userId removed from client — extracted server-side from x-forwarded-email)
  ▼
load-test-routes.ts
  ├─ extractUser(req) → user_id from AppKit proxy headers
  ├─ loadTestHistoryService.createRun() → Lakebase INSERT (status='running')
  ├─ syntheticDataService.generateAndIngestStreaming() → ZeroBus gRPC
  └─ loadTestHistoryService.completeRun() + upsertTypeResults() → Lakebase UPDATE
      │
      ▼ Lakehouse Sync (automatic CDC)
  lb_load_test_runs_history (UC Delta, SCD Type 2)
  lb_load_test_type_results_history (UC Delta, SCD Type 2)
      │
      ▼ Current-state views (DDL in infra bundle)
  v_load_test_runs / v_load_test_type_results
```

### Key Decisions

1. **Single write path (Lakebase only)** — replaced initial dual-write proposal. Lakehouse Sync handles UC replication via WAL logical decoding, no external compute needed.
2. **`run_id` as TEXT, not UUID** — Lakehouse Sync's supported type list doesn't explicitly include Postgres UUID. Using `gen_random_uuid()::TEXT` maps cleanly to STRING in Delta.
3. **REPLICA IDENTITY FULL** — set on both Lakebase tables during setup so Lakehouse Sync captures full rows on UPDATE/DELETE.
4. **History writes are non-fatal** — wrapped in try/catch so load test execution continues even if Lakebase history insert fails.
5. **Server-side user extraction** — `extractUser(req)` reads `x-forwarded-email` from AppKit proxy headers. The `userId` field was removed from the client POST body entirely.

### Bug Fixed

All synthetic records previously had `user_id = 'synthetic-load-test'` (hardcoded in client). Now both the single-shot and SSE handlers extract the real user identity server-side, so synthetic records in the bronze table carry the actual workspace email.

### Files Created

| File | Lines | Purpose |
| --- | --- | --- |
| `server/utils/extract-user.ts` | 65 | Shared user identity extraction (3-way: Bearer, x-forwarded-email, anonymous) |
| `server/services/load-test-history-service.ts` | 311 | Lakebase CRUD: table setup, createRun, completeRun, upsertTypeResults, listRuns, getRun, deleteRun |
| `client/src/pages/testing/LoadTestHistory.tsx` | 393 | React timeline table with expandable per-type breakdown, sortable columns, status/preset badges |

### Files Modified

| File | Changes |
| --- | --- |
| `server/routes/zerobus/ingest-routes.ts` | Replaced local `extractUserFromToken()` with shared `extractUser()` import |
| `server/routes/testing/load-test-routes.ts` | Added imports (extractUser, extractClientIp, loadTestHistoryService); added `presetLabel` to interface; server-side userId extraction; history writes in SSE flow (create, complete, abort, type results); GET `/history` and GET `/history/:runId` endpoints |
| `server/server.ts` | Added `setLakebaseClient(appkit.lakebase)` to wire history service |
| `client/src/pages/testing/LoadTestPage.tsx` | Removed `userId: 'synthetic-load-test'` from POST body; added `presetLabel`; integrated `<LoadTestHistory />` |
| `dbxW_zerobus_infra/src/uc_setup/target-table-ddl` (notebook) | Added 3 cells: markdown intro, `v_load_test_runs` view DDL, `v_load_test_type_results` view DDL |

### New API Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/api/v1/testing/history` | Paginated history list with per-type breakdown |
| GET | `/api/v1/testing/history/:runId` | Single run detail |

### Remaining Manual Steps

1. **Enable Lakehouse Sync** in the Lakebase UI: select `app` schema → destination catalog/schema → Start sync
2. **Verify REPLICA IDENTITY** after first deployment: the service sets it during table creation, but confirm via `\d+ app.load_test_runs` in psql
3. **Run the infra bundle** to create the current-state views: `databricks bundle deploy --target <target>` + run the UC setup job
4. **Deploy the app** and run a load test to verify end-to-end: Lakebase rows → `lb_*_history` Delta tables → views → history UI
