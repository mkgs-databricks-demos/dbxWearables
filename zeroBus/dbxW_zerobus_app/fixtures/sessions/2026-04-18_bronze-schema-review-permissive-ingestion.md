## Session: Bronze Schema Review & Permissive Ingestion Refactor

**Date:** 2026-04-18  
**Bundle:** `dbxW_zerobus_app`  
**Scope:** Bronze table schema validation, header capture redesign, `source_platform` + `user_id` column additions, ingestion permissiveness improvements, user identity architecture planning

---

### Problems Encountered

#### 1. Header Capture Gap (Bug)

Cross-referencing the iOS `APIService.swift` against the server's `ingest-routes.ts` revealed that 3 headers the iOS app sends were silently dropped:

| Header | Value | Status |
| --- | --- | --- |
| `X-Record-Type` | `samples\|workouts\|sleep\|...` | ✅ Captured |
| `X-Device-Id` | `DeviceIdentifier.current` | ✅ Captured |
| `X-Platform` | `apple_healthkit` | ❌ **Dropped** |
| `X-App-Version` | `CFBundleShortVersionString` | ❌ **Dropped** |
| `X-Upload-Timestamp` | ISO 8601 date | ❌ **Dropped** |

**Root cause:** `HEADERS_TO_KEEP` allowlist in `ingest-routes.ts` included placeholders for future headers (`x-sync-session-id`, `x-batch-index`, `x-batch-count`) but missed 3 headers the iOS app was already sending.

#### 2. Allowlist Architecture is Fragile

The allowlist approach creates a recurring bug class: any time a client adds a new header, the server must be updated to capture it. For a bronze layer that uses VARIANT columns specifically for schema-on-read flexibility, this contradicts the design intent.

---

### Root Causes

1. **Allowlist/blocklist mismatch** — The server used an allowlist pattern for a column (VARIANT) designed for permissive storage. The restrictive approach at the server layer contradicted the permissive approach at the table layer.

2. **Missing `source_platform` denormalization** — `X-Platform` was only available inside the `headers` VARIANT column, requiring VARIANT parsing for what will be a primary filter dimension when multiple platforms (Android, Fitbit, Garmin) are added.

3. **Overly restrictive `X-Record-Type` validation** — The server rejected any record type not in a hardcoded set of 5, requiring a server deploy to add new record types.

---

### Changes Made

#### Phase 1: Initial Fixes (Header Gap + source_platform)

**`ingest-routes.ts`** — Added `x-platform`, `x-app-version`, `x-upload-timestamp` to `HEADERS_TO_KEEP` allowlist. Extracted `X-Platform` header as `sourcePlatform` parameter, passed to `buildRecord()`.

**`zerobus-service.ts`** — Added `source_platform: string` to `WearablesRecord` interface. Added `sourcePlatform` parameter to `buildRecord()` method signature and return object. Updated header comment to include 6th column.

**`target-table-ddl` notebook (ID: 2686724970547991)** — Added `source_platform STRING` column to `CREATE TABLE IF NOT EXISTS` DDL. Added new cell with `ALTER TABLE ADD COLUMNS` for schema evolution on existing table.

**Live table** — Ran `ALTER TABLE hls_fde_dev.dev_matthew_giglia_wearables.wearables_zerobus ADD COLUMNS (source_platform STRING ...)` to add column to deployed table. Existing rows have NULL (backfill not needed — silver layer can coalesce from `headers::"x-platform"`).

#### Phase 2: Permissive Ingestion Refactor (Blocklist)

**`ingest-routes.ts`** — Complete redesign of header capture and record type validation:

| Before | After |
| --- | --- |
| `HEADERS_TO_KEEP` allowlist (10 specific headers) | `HEADERS_TO_STRIP` blocklist (3: `authorization`, `cookie`, `set-cookie`) |
| `extractHeaders()` iterated allowlist keys | `extractHeaders()` iterates `Object.entries(req.headers)`, skips blocklist |
| `VALID_RECORD_TYPES` — rejected unknown types with 400 | `KNOWN_RECORD_TYPES` — logs unknown at warn level, ingests anyway |
| Header comment referenced iOS-only contract | Updated to document blocklist strategy, multi-platform, open record types |

**`extractHeaders()` new implementation:**
```typescript
function extractHeaders(req: Request): Record<string, string> {
  const headers: Record<string, string> = {};
  for (const [key, value] of Object.entries(req.headers)) {
    if (!HEADERS_TO_STRIP.has(key) && typeof value === 'string') {
      headers[key] = value;
    }
  }
  return headers;
}
```

#### Phase 3: Validation Notebook Updates

**`validate-zerobus-ingest` notebook (ID: 3718791516828959):**

- **Cell 9 (POST All Record Types)** — Added `X-Platform`, `X-App-Version`, `X-Upload-Timestamp`, `X-Device-Id` headers to test POSTs
- **Cell 11 (Query Bronze Table)** — Added `source_platform` to SELECT columns
- **Cell 15 (Header Capture Analysis)** — Replaced allowlist gap analysis with blocklist strategy documentation
- **Cell 16 (iOS Model Mapping)** — Updated table to include `source_platform` column, added notes about permissive body/headers/record_type
- **Cell 18 (Best Practices Audit)** — Replaced recommendations with "Ingestion Design Principles" and "Remaining Considerations" sections
- **Cells 14-18** — Added during schema review: markdown section header, header strategy, model mapping, offset analysis, best practices audit

#### Phase 4: User Identity Column (user_id)

**Problem:** No way to attribute ingested records to a specific user. HealthKit doesn't expose user identity (Apple privacy model), and `DeviceIdentifier.current` is per-installation, not per-person.

**`user-identity-todo.md`** — Created comprehensive auth planning document at repo root. Architecture: App-Managed JWT Auth with Lakebase User Registry, Sign in with Apple, two-layer auth model (App→Workspace M2M existing, User→App JWT new).

**`zerobus-service.ts`** — Added `user_id: string` to `WearablesRecord` interface. Added `userId` parameter to `buildRecord()` with default `'anonymous'`. Updated header comment to list 7th column.

**`target-table-ddl` notebook (ID: 2686724970547991)** — Added `user_id STRING` column to `CREATE TABLE IF NOT EXISTS` DDL. Updated `ALTER TABLE ADD COLUMNS` cell to include both `source_platform` and `user_id`.

**Live table** — Ran `ALTER TABLE hls_fde_dev.dev_matthew_giglia_wearables.wearables_zerobus ADD COLUMNS (user_id STRING ...)` to add column. Existing rows have `NULL`; new rows default to `'anonymous'` until JWT auth is implemented.

#### Phase 5: 3-Way User Identity Branch (extractUserFromToken)

**Problem:** The Phase 4 `extractUserFromToken()` only checked `x-forwarded-email` (AppKit proxy header). This worked for workspace traffic (notebooks, jobs) but didn't establish the correct priority ordering for the eventual mobile app JWT auth path.

**Insight from header analysis:** AppKit's proxy strips the `Authorization` header before forwarding to Express and injects `x-forwarded-*` headers. This means `Authorization: Bearer` is ONLY present when a client bypasses the proxy (= mobile app calling directly). The two auth paths are naturally mutually exclusive.

**`ingest-routes.ts`** — Rewrote `extractUserFromToken()` as a 3-way priority branch:

| Priority | Signal | Source | user_id value | Status |
| --- | --- | --- | --- | --- |
| 1 | `Authorization: Bearer <token>` | Mobile app (direct) | Lakebase UUID from JWT `sub` | **Placeholder** — logs token, returns `'anonymous'` |
| 2 | `x-forwarded-email` header | Workspace (proxy) | User email (e.g. `matthew.giglia@databricks.com`) | **Active** |
| 3 | Neither | No auth | `'anonymous'` | **Active** |

**Also in this phase:**
- Added `x-forwarded-access-token` to `HEADERS_TO_STRIP` blocklist (contained raw JWT being stored in bronze — security fix)
- Updated header comment block to document the 3-way priority logic
- Branch 1 includes TODO comments for future JWT validation implementation

**Validation:** All 6 checks pass — notebook traffic correctly hits Branch 2, `user_id` = `current_user()`.

---

### Design Decisions

#### 1. Blocklist > Allowlist for Header Capture

The bronze layer's VARIANT columns exist for schema-on-read flexibility. An allowlist at the server layer contradicts this — it imposes schema-on-write restrictions on a column designed to accept anything. Switching to a blocklist (strip only `authorization`, `cookie`, `set-cookie`) aligns the server with the table design and eliminates the bug class where new client headers are silently dropped.

#### 2. Open Record Type Validation

`X-Record-Type` now accepts any non-empty string. Known types (`samples`, `workouts`, `sleep`, `activity_summaries`, `deletes`) are logged at info level; unknown types are logged at warn level but still ingested. This lets clients add new record types (e.g., `mindful_sessions`, `electrocardiograms`) without a server deploy.

#### 3. `source_platform` as Denormalized Column

Extracted from `X-Platform` header to a top-level STRING column (defaults to `'unknown'`). This enables fast partition-level filtering by platform without VARIANT parsing — critical when Android Health Connect, Fitbit, and Garmin are added.

#### 4. No Offset Column

Delta row tracking (`delta.enableRowTracking = true`) already provides monotonically increasing `_row_id` and `_row_commit_version` system columns. A user-space auto-incrementing offset would require cross-request coordination and adds no value over what Delta provides. SDP downstream uses commit-version-based checkpointing, not user-space sequence numbers.

#### 5. Only 3 Server-Side Validations

The server now validates exactly 3 things:
1. `X-Record-Type` header exists and is non-empty
2. Request body is non-empty
3. Each NDJSON line is valid JSON (required for VARIANT storage)

Everything else (schema validation, type checking, dedup, enrichment) belongs in the silver layer.

---

### HealthKit UUID Location

The HealthKit sample UUID (`body:uuid`) lives inside the VARIANT `body` column — NOT as a top-level column. `record_id` is a different server-generated UUID. This affects silver-layer design:

| Record Type | UUID Location | Natural Key |
| --- | --- | --- |
| samples | `body:uuid` | HealthKit sample UUID |
| workouts | `body:uuid` | HealthKit workout UUID |
| sleep | `body:stages[*].uuid` | Per-stage UUIDs (no session UUID) |
| activity_summaries | N/A | `body:date` (string, e.g. "2026-04-17") |
| deletes | `body:uuid` | References the deleted record's UUID |

Consider denormalizing `body:uuid` to a top-level column when building the SDP silver layer.

---

### Delta Table Best Practices Audit

All 7 checks passed on `hls_fde_dev.dev_matthew_giglia_wearables.wearables_zerobus`:

| Feature | Value | Purpose |
| --- | --- | --- |
| `delta.enableChangeDataFeed` | `true` | SDP downstream reads changes |
| `delta.enableRowTracking` | `true` | Monotonic ordering (replaces offset) |
| `delta.enableVariantShredding` | `true` | Query perf on body/headers VARIANT |
| `delta.enableDeletionVectors` | `true` | Efficient soft deletes |
| `delta.parquet.compression.codec` | `zstd` | Best compression ratio |
| `clusterByAuto` | `true` | Auto-tuned data layout |
| Predictive optimization | inherited | From metastore |

---

### Final Bronze Table Schema (7 columns)

```sql
CREATE TABLE wearables_zerobus (
  record_id       STRING    NOT NULL  -- Server-generated UUID (PK)
  ingested_at     TIMESTAMP           -- Server-side epoch microseconds
  body            VARIANT             -- Any valid JSON (NDJSON line)
  headers         VARIANT             -- ALL headers except auth/cookie
  record_type     STRING              -- Any non-empty string from X-Record-Type
  source_platform STRING              -- From X-Platform, default 'unknown'
  user_id         STRING              -- App-authenticated user ID from JWT claims
)
```

---

### Files Modified

| File | Status | Description |
| --- | --- | --- |
| `src/app/server/routes/zerobus/ingest-routes.ts` | Modified | Blocklist refactor; open record types; `source_platform` extraction; `user_id` via 3-way `extractUserFromToken()` (Bearer JWT placeholder → x-forwarded-email → anonymous); added `x-forwarded-access-token` to blocklist |
| `src/app/server/services/zerobus-service.ts` | Modified | Added `source_platform` and `user_id` to WearablesRecord interface and buildRecord() |
| `src/endpoint-validation/validate-zerobus-ingest` (notebook) | Modified | Added schema review cells (14-18), updated POST headers, query columns, analysis cells |
| `dbxW_zerobus_infra: src/uc_setup/target-table-ddl` (notebook 2686724970547991) | Modified | Added source_platform and user_id to CREATE TABLE DDL; ALTER TABLE ADD COLUMNS for both |
| Live table: `hls_fde_dev.dev_matthew_giglia_wearables.wearables_zerobus` | Altered | Added source_platform and user_id STRING columns via ALTER TABLE |
| `user-identity-todo.md` (repo root) | Created | JWT auth architecture planning doc (Sign in with Apple + Lakebase user registry) |
| `fixtures/sessions/2026-04-18_bronze-schema-review-permissive-ingestion.md` | Created | This file |
| `fixtures/sessions/INDEX.md` | Updated | Added this session entry |

---

### Next Steps

1. ~~Redeploy app~~ — Done (deployment `01f13b0209361f969ad6f7859675a990`)
2. ~~Re-run validation notebook~~ — 6/6 validations pass (`user_id` = `current_user()` via `x-forwarded-email`)
3. **iOS integration test** — Set `DBX_API_BASE_URL` and run end-to-end sync from device
4. **Implement JWT auth** — Phase 1-3 from `user-identity-todo.md` (Lakebase schema → auth endpoints → JWT middleware)
5. **Define SDP pipeline** — Silver layer parsing `body` VARIANT per `record_type`, dedup on `body:uuid`
6. **Consider `body:uuid` denormalization** — Top-level column for silver-layer dedup without VARIANT parsing
