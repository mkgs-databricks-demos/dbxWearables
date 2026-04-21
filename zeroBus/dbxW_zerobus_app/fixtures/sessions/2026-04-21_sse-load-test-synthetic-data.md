## Session: SSE Load Test & Synthetic Data Generation Infrastructure

**Date:** 2026-04-21
**Bundle:** dbxW_zerobus_app

---

### Summary

Built end-to-end synthetic data generation and load testing infrastructure for the ZeroBus ingest pipeline. Replaced client-side chunked HTTP requests with Server-Sent Events (SSE) for real-time streaming progress. Debugged two SSE issues using OTel logs: response buffering and premature abort detection.

---

### Work Completed

#### 1. Dynamic Payload Generation for API Docs (DocsPage.tsx)

Replaced static hardcoded JSON examples in the "Try It" panel with realistic, unique payloads generated on each click. Ported statistical distributions from `validate-zerobus-ingest.ipynb`:

- `gaussRandom()`, `triangularRandom()` for biometric realism
- Per-type generators: heart rate (55-85 resting, occasional 90-140), step count (~4K-8K/hr), workout duration, sleep hours
- "Generate New" button with spin animation; auto-regenerates when record type changes

#### 2. Shared Synthetic Module Extraction

Extracted generation logic into a shared module for reuse across client (DocsPage) and server (load test):

| File | Purpose |
| --- | --- |
| `src/app/shared/synthetic-healthkit.ts` (313 lines) | Pure utility functions (zero dependencies, browser + Node.js). Exports `generatePayload()`, `generatePayloadBatch()`, `generateAllTypes()`, statistical distributions |
| `src/app/server/services/synthetic-data-service.ts` (358 lines) | Server-side bulk generation + direct ZeroBus ingestion. `generate()` for NDJSON, `generateAndIngest()` for single-shot, `generateAndIngestStreaming()` for SSE with progress callbacks |

Updated `tsconfig.client.json`, `tsconfig.server.json`, and `vite.config.ts` with `@shared/*` path aliases.

#### 3. Load Test Page (LoadTestPage.tsx)

Full-featured UI for generating and ingesting millions of synthetic records:

- **5 scale presets**: Smoke (5 payloads), Small (500), Medium (5K), Large (50K), Massive (500K / ~1.5M records)
- **Per-type count inputs** with custom overrides
- **Live dashboard**: animated progress bar, 3 metric cards (records, duration, throughput), per-type breakdown table
- **Stop button**: AbortController-based, preserves already-ingested records

#### 4. SSE Streaming (replaced chunked HTTP)

Migrated from client-side chunked `fetch()` loop to server-side SSE streaming:

| Component | Change |
| --- | --- |
| `synthetic-data-service.ts` | Added `ProgressEvent` interface + `generateAndIngestStreaming()` with `onProgress` callback and `AbortSignal` |
| `load-test-routes.ts` | Added `POST /api/v1/testing/load-test/stream` SSE endpoint. Sets `text/event-stream` headers, emits `progress`/`complete`/`error` events |
| `LoadTestPage.tsx` | Single `fetch()` + `ReadableStream` reader. Parses SSE events from stream buffer. Removed `chunkSize` state/UI |

**Data flow:**
```
LoadTestPage -> fetch('/api/v1/testing/load-test/stream')
  -> SSE stream <- server emits progress after each gRPC batch
  -> syntheticDataService.generateAndIngestStreaming()
  -> zeroBusService.buildRecord() + ingestRecords()
  -> gRPC stream pool -> bronze table
```

#### 5. SSE Bug #1: Response Buffering

**Symptom:** UI stuck at "0/0 batches" -- events written but never received by client.

**Root cause:** Express compression middleware (and/or Node.js internal buffering) held `res.write()` data in memory instead of pushing it to the socket.

**Fix:** Added `res.flushHeaders()` after `writeHead()` (forces browser into streaming mode) and `(res as any).flush?.()` after each `res.write()` (pushes through compression middleware).

#### 6. SSE Bug #2: Premature Abort Detection

**Symptom:** UI still stuck at 0/0 after buffering fix. OTel logs showed "Client disconnected -- aborting" firing 2-7ms after every request start.

**Root cause:** `req.on('close')` fires when the POST **request body** is fully consumed (~2ms for a small JSON body), NOT when the TCP connection drops. This set `clientDisconnected = true` before any progress events could be emitted, causing `writeEvent()` to silently no-op.

**Diagnosis:** Queried `hls_fde_dev.dev_matthew_giglia_wearables.dbxw_0bus_ingest_otel_logs`:
```
17:12:09.221 -- Starting: 500 payloads across 5 type(s)
17:12:09.228 -- Client disconnected -- aborting  <- 7ms later!
17:12:09.292 -- Complete: 500 records in 70ms    <- records ingested, events dropped
```

**Fix:** Changed `req.on('close')` to `res.on('close')` with a `responseEnded` boolean guard. `res.on('close')` fires when the **response** stream terminates (either by `res.end()` or client abort). The guard prevents false positives on normal completion:

```typescript
let responseEnded = false;
res.on('close', () => {
  if (!responseEnded) {
    clientDisconnected = true;
    abortController.abort();
  }
});
// on normal completion:
responseEnded = true;
res.end();
```

---

### Files Modified

| File | Lines | Change |
| --- | --- | --- |
| `src/app/shared/synthetic-healthkit.ts` | 313 | **New** -- shared generation utilities |
| `src/app/server/services/synthetic-data-service.ts` | 358 | Added `ProgressEvent`, `generateAndIngestStreaming()` |
| `src/app/server/routes/testing/load-test-routes.ts` | ~240 | Added SSE endpoint, flush, `res.on('close')` |
| `src/app/client/src/pages/testing/LoadTestPage.tsx` | ~530 | SSE stream reader, presets, live dashboard |
| `src/app/client/src/pages/DocsPage.tsx` | modified | Replaced inline generators with `@shared/synthetic-healthkit` imports |
| `src/app/client/src/App.tsx` | modified | Added `/load-test` route |
| `src/app/client/src/components/Navbar.tsx` | modified | Added "Load Test" nav item |
| `src/app/server/server.ts` | modified | Added `setupLoadTestRoutes(appkit)` |
| `tsconfig.client.json` | modified | Added `@shared/*` path alias |
| `vite.config.ts` | modified | Added `@shared` resolve alias |

---

### Key Lessons

1. **`req.on('close')` is not connection close** -- In Node.js, `IncomingMessage.close` fires when the request stream ends (body consumed), not when the TCP connection drops. For SSE, always use `res.on('close')`.

2. **Express SSE requires explicit flushing** -- `res.write()` alone is not enough when compression middleware is present. Always call `res.flushHeaders()` after headers and `(res as any).flush?.()` after each write.

3. **OTel logs are invaluable for SSE debugging** -- The timing correlation between "Starting" and "Client disconnected" (2ms gap) made the `req.on('close')` misuse immediately obvious.
