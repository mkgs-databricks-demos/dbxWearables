## Session: Dynamic Stream Pool Resize & Load-Based Auto-Scaling

**Date:** 2026-04-21
**Bundle:** dbxW_zerobus_app

---

### Summary

Added runtime-resizable gRPC stream pool to the ZeroBus ingest service. The pool can be resized manually via API/UI or automatically based on load. A background monitor scales up when streams are saturated or call rate is high, and scales down after sustained idle. All resize events (auto, manual, initial) are recorded in a ring buffer and displayed in a scrollable event log on the Load Test page. Auto-scaling responds to all `ingestRecords()` callers -- real iOS HealthKit traffic and synthetic load test traffic alike.

---

### Context: Stream Pool Architecture

The ZeroBus TypeScript SDK uses persistent gRPC streams to write records to the Unity Catalog bronze table. The `ZeroBusService` singleton manages a pool of these streams with round-robin selection. Prior to this session, the pool size was fixed at construction time from the `ZEROBUS_STREAM_POOL_SIZE` env var (sourced from the secret scope via `databricks.yml` variable).

**Config chain (unchanged):**
```
databricks.yml var -> secret scope -> app.yaml valueFrom -> env var -> ZeroBusService constructor
```

Dev target runs at initial size 2 (`databricks.yml` L162). Default fallback is 4.

---

### Work Completed

#### 1. Dynamic Pool Resize (`zerobus-service.ts`)

Added `resize(newSize)` method to `ZeroBusService`:

| Direction | Behavior |
| --- | --- |
| Scale UP | Opens additional gRPC streams via `sdk.createStream()`, appends to pool. Zero disruption -- existing in-flight requests continue on their streams |
| Scale DOWN | Drains in-flight requests (polls up to 10s), splices excess streams from the tail, resets round-robin index, closes removed streams (flushes queued records) |
| Not initialized | Updates `this.poolSize` target -- applied on next lazy init |

**Prerequisite change:** `targetTable`, `clientId`, and `clientSecret` are now stored as instance fields during `initializePool()` so `resize()` can open new streams without re-reading env vars.

Bounds: 1--32 streams. Validated in the method with a thrown error outside range.

#### 2. Resize API Endpoints (`load-test-routes.ts`)

| Endpoint | Method | Purpose |
| --- | --- | --- |
| `/api/v1/testing/pool-status` | GET | Returns `pool_size`, `active_streams`, `initialized`, `inflight_requests`, `draining`, `auto_scale`, `history` |
| `/api/v1/testing/pool-resize` | POST | Manual resize: `{ poolSize: N }` -> `{ oldSize, newSize, durationMs }` |
| `/api/v1/testing/pool-autoscale` | POST | Toggle auto-scale: `{ enabled, minSize, maxSize }` |

#### 3. Stream Pool UI Card (`LoadTestPage.tsx`)

Added a "Stream Pool" card in the left configuration column:

- Active streams badge (green when initialized)
- Toggle switch for auto-scale on/off
- When auto-scale enabled: min/max inputs (changes apply on blur)
- When auto-scale disabled: manual resize input + Resize button
- In-flight request indicator
- Error display
- Descriptive text changes based on mode

Pool status is fetched on mount, after each test completion, and every 3s while auto-scale is active during a running test.

#### 4. Load-Based Auto-Scaling (`zerobus-service.ts`)

Background interval monitor (`setInterval`) that checks stream utilization every `checkIntervalMs` (default: 3s).

**Scale-up triggers (two independent signals -- either can fire):**

| Trigger | Condition | Catches |
| --- | --- | --- |
| Concurrent saturation | `peakInflight >= streamCount` | Multiple simultaneous callers (many iOS devices syncing at once) |
| High call rate | `callsSinceLastCheck >= streamCount` | Sequential-but-heavy usage (load test batches, rapid iOS syncs in sequence) |

- Adds `scaleUpStep` streams (default: 2) up to `maxSize` (default: 16)
- `peakInflight` tracks the highest concurrent in-flight count between checks, reset each interval
- `callsSinceLastCheck` increments on every `ingestRecords()` call, reset each interval
- Fires on the very first check where either condition is met (no sustained requirement -- load testing needs fast response)

**Scale-down trigger:** `inflight === 0 AND callRate === 0` for `IDLE_CHECKS_BEFORE_SCALE_DOWN` consecutive checks (default: 3)
- Removes `scaleDownStep` streams (default: 1) down to `minSize` (default: 2)
- Conservative: requires sustained idle (no in-flight AND no calls) to avoid premature scale-down between batches

**Cooldown:** `cooldownMs` (default: 15s) between any two resize operations.

**Configuration interface:**

```typescript
interface AutoScaleConfig {
  minSize: number;         // default: 2
  maxSize: number;         // default: 16
  checkIntervalMs: number; // default: 3000 (3s)
  cooldownMs: number;      // default: 15000 (15s)
  scaleUpStep: number;     // default: 2
  scaleDownStep: number;   // default: 1
}
```

**Key design decision -- responds to ALL load, not just test traffic.** The auto-scale logic lives in `ZeroBusService`, not in the load test routes. Every call to `ingestRecords()` -- whether from the iOS app's real HealthKit POSTs via `/api/v1/healthkit/ingest` or from the synthetic load test -- increments `inflight`, `peakInflight`, and `callsSinceLastCheck`. The monitor responds to production load identically.

**Lifecycle:**
- `enableAutoScale(config)` starts the interval timer
- `disableAutoScale()` clears the timer, pool stays at current size
- `close()` (SIGTERM) calls `disableAutoScale()` before drain sequence

#### 5. Resize Event History (`zerobus-service.ts`)

Ring buffer of the last 50 `ResizeEvent` records:

```typescript
interface ResizeEvent {
  timestamp: string;      // ISO 8601
  trigger: 'auto-scale-up' | 'auto-scale-down' | 'manual' | 'initial';
  oldSize: number;
  newSize: number;
  durationMs: number;
  peakInflight?: number;  // auto-scale-up only
  idleChecks?: number;    // auto-scale-down only
  callRate?: number;      // auto-scale-up only (call rate trigger)
}
```

Events are recorded for:
- **`initial`** -- first `ensurePool()` opens the starting streams
- **`auto-scale-up`** -- monitor detects saturation or high call rate, includes `peakInflight` and `callRate` context
- **`auto-scale-down`** -- monitor detects sustained idle, includes `idleChecks` count
- **`manual`** -- user clicks Resize in the UI

Implementation uses a private `_lastResizeTrigger` / `_lastResizePeak` / `_lastResizeIdle` / `_lastResizeCallRate` context pattern: the caller sets these fields before calling `resize()`, and `resize()` reads + clears them when recording the event. This avoids changing the `resize()` method signature.

#### 6. Event Log Panel (`LoadTestPage.tsx`)

"Pool Resize History" panel in the results column:

- Scrollable (max 224px), newest-first (reverse chronological)
- Color-coded icons per trigger type:
  - Green `ArrowUpCircle` for auto-scale-up
  - Blue `ArrowDownCircle` for auto-scale-down
  - Red `Settings2` gear for manual
  - Gray `Sparkles` for initial
- Trigger badges: `auto up`, `auto down`, `manual`, `initial`
- Context annotations: `peak: N` for scale-up, `calls: N` for call-rate triggers, `idle: N x` for scale-down
- Timestamp (locale time string) + duration per event
- Auto-refreshes with pool status polling

#### 7. Auto-Scale Bug Fix: Scale-Up Never Triggered

**Symptom:** After enabling auto-scale and running a load test (Small preset, 500 payloads), auto-scale only scaled DOWN (10 -> 9 -> 8 -> ... -> 4) but never scaled UP. Manual resize worked fine.

**Diagnosis from OTel logs:**
```
18:21:03 -- Auto-scale enabled (min: 2, max: 16)
18:21:11 -- Starting: 500 payloads across 5 type(s)
18:21:12 -- Complete: 900 records in 1145ms (786 rec/s)
           (no auto-scale-up events anywhere)
18:21:12 -- Idle for 3 checks -- scaling DOWN: 10 -> 9
18:21:33 -- Idle for 3 checks -- scaling DOWN: 9 -> 8
           ... continued down to 4
```

**Root cause:** The scale-up condition was `peakInflight >= streamCount`, but `generateAndIngestStreaming` processes batches **sequentially** (`await ingestRecords()` one at a time). With sequential processing, `inflight` is always 0 or 1. For a pool of 2+ streams, the condition `1 >= 2` is never true. The same applies to individual iOS HealthKit POSTs processed one at a time by Express.

The only scenario where `peakInflight >= streamCount` would trigger is multiple simultaneous HTTP requests -- e.g., many iOS devices syncing at exactly the same time. But typical usage is sequential.

**Fix:** Added a second, independent scale-up trigger -- **call rate**:

```typescript
// Two independent triggers (either can fire):
const concurrentSaturated = peak >= streamCount;  // original
const highCallRate = callRate >= streamCount;      // new

if ((concurrentSaturated || highCallRate) && streamCount < config.maxSize && cooldownElapsed) {
  // scale up
}
```

`callsSinceLastCheck` increments on every `ingestRecords()` call and resets each check interval. If the pool handles at least as many calls as it has streams in a 3-second window, there's enough demand to justify more streams.

For a Small preset (500 payloads, ~1500 records, batchSize 500): ~3 `ingestRecords()` calls per 3s interval. With 2 streams, `callRate (3) >= streamCount (2)` is true -> scale up fires.

Scale-down was also tightened: now requires **both** `inflight === 0 AND callRate === 0` for 3 consecutive checks, preventing premature shrink during brief pauses between batches.

The event log now shows `calls: N` alongside `peak: N` for scale-up events.

---

### Files Modified

| File | Lines | Change |
| --- | --- | --- |
| `src/app/server/services/zerobus-service.ts` | 747 | Credential instance fields, `resize()`, `AutoScaleConfig`, `enableAutoScale()`, `disableAutoScale()`, `checkAutoScale()` with dual-metric triggers (`peakInflight` + `callRate`), `callsSinceLastCheck` tracking, `ResizeEvent` ring buffer with `callRate` field, `recordResizeEvent()`, `autoScaleStatus()` |
| `src/app/server/routes/testing/load-test-routes.ts` | 385 | `GET /pool-status`, `POST /pool-resize`, `POST /pool-autoscale` endpoints, `autoScaleStatus()` in response |
| `src/app/client/src/pages/testing/LoadTestPage.tsx` | 843 | Stream Pool card with auto-scale toggle + min/max inputs, manual resize, pool status polling (3s during tests), `toggleAutoScale` callback, `PoolStatus.auto_scale` interface, `ResizeEvent` interface with `callRate`, event history log panel with `calls: N` annotations |

---

### Key Design Decisions

1. **Auto-scale in the service, not the route layer.** Ensures all ingest callers benefit -- iOS app traffic, synthetic tests, any future ingestion path. The load test page is just the UI for enabling/configuring it.

2. **Dual-metric scale-up (concurrent saturation + call rate).** The original `peakInflight >= streamCount` only detects concurrent callers. Adding `callsSinceLastCheck >= streamCount` captures sequential-but-heavy usage patterns -- critical because both the load test (sequential batches) and typical iOS traffic (one POST at a time) are sequential callers. Either trigger independently fires the scale-up.

3. **Fast scale-up, conservative scale-down.** Scale-up triggers on the first check where either condition is met. Scale-down requires 3 consecutive checks with BOTH zero in-flight AND zero calls -- prevents premature shrink during brief pauses between batches.

4. **Peak inflight + call rate tracking.** `peakInflight` captures the highest concurrent watermark between checks (brief spikes between intervals). `callsSinceLastCheck` captures total demand volume. Together they cover both concurrent and sequential usage patterns.

5. **Ring buffer, not persistent storage.** Resize events are in-memory only (last 50). They reset on app restart. This is appropriate for an operational tool -- persistent history lives in the OTel logs table (`[ZeroBus] Pool resized: N -> M` console.log entries).

6. **Context fields pattern for event recording.** Rather than adding `trigger` parameters to the `resize()` method signature (which would break manual callers), the auto-scale monitor sets private `_lastResizeTrigger` / `_lastResizePeak` / `_lastResizeCallRate` fields before calling `resize()`, and `resize()` reads + clears them. Manual resizes default to `trigger: 'manual'`.
