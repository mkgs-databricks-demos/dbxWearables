## Session: Apple Auth Best Practices Audit, iOS Contract Alignment & Nonce Verification

**Date:** 2026-04-27
**Bundle:** `dbxW_zerobus_app`
**Focus:** Cross-project review (iOS + Databricks), Apple Sign in with Apple best practices audit, P0 server-side fixes to align with iOS client contract, nonce verification implementation

---

### Context

After the 2026-04-26 session completed Phase 1 auth infrastructure deployment and all secret scope provisioning, this session focused on:
1. Reviewing the iOS app's auth implementation maturity (done outside Databricks in Xcode)
2. Auditing the server against Apple's Sign in with Apple backend best practices
3. Fixing the contract divergences between the iOS app and the server

The iOS Bootstrap SPN client secret (`ios_bootstrap_client_secret_dev_matthew_giglia_wearables`) was provisioned at the start of this session, completing all 10/10 secret scope keys.

---

### iOS App Assessment

Reviewed the iOS `healthKit/` project structure and found it significantly more mature than the Phase 4 roadmap suggested:

| Component | Status | File |
| --- | --- | --- |
| SPN OAuth flow | Working | `AuthService.swift` |
| Sign in with Apple | Implemented | `AppleSignInManager.swift` |
| Sign-in UI | Implemented | `SignInWithAppleView.swift` |
| JWT exchange client | Implemented | `AppleSignInManager.performExchange()` |
| Keychain (JWT + refresh) | Extended | `KeychainHelper.swift` |
| Runtime workspace config | Working | `WorkspaceConfig.swift` |
| XcodeGen project | Generated | `project.yml` + `dbxWearablesApp.xcodeproj/` |
| Build scripts | Working | `scripts/generate_credentials_qr.py`, `generate_app_icon.py` |
| Auth architecture doc | Exists | `docs/auth-architecture.md` |

New files discovered that weren't in the original repo structure docs: `DemoMode.swift`, `IntegrationTestHelper.swift`, `HealthKitTestDataGenerator.swift`, `TestResultsView.swift`, `DatabricksLogo.swift`.

---

### iOS Documentation Updates (Staged)

Prepared documentation updates for 5 files outside the app bundle's editable path. Content staged in notebook cells 5–11 for manual application:

| Cell | Target File | Action |
| --- | --- | --- |
| 7 | `healthKit/docs/auth-architecture.md` | Full replacement (11K chars) — restructured to Layer 1/Layer 2 model |
| 8 | `healthKit/README.md` | Add Authentication section, update project structure |
| 9 | `healthKit/healthKit/Services/README.md` | Add auth + testing service entries |
| 10 | `healthKit/healthKit/README.md` | Update service graph with auth chain |
| 11 | `CLAUDE.md` (repo root) | Replace Current State — iOS maturity + Databricks side exists |

---

### Contract Divergences Identified

Xcode screenshots from the iOS app revealed 5 critical mismatches between the iOS client and the deployed server:

| # | Divergence | iOS Expects | Server Has |
| --- | --- | --- | --- |
| 1 | Endpoint path | `/api/v1/auth/apple/exchange` | `/api/v1/auth/apple` |
| 2 | Request: token field | `appleIdToken` (camelCase) | `identity_token` (snake_case) |
| 3 | Request: device field | `deviceId` (camelCase) | `device_id` (snake_case) |
| 4 | Response: JWT field | `jwt` | `access_token` |
| 5 | Response: expiry field | `expiresIn` (camelCase) | `expires_in` (snake_case) |

Plus: iOS sends `nonce` and `userId` fields the server didn't accept; server returns `refresh_token` the iOS didn't parse.

---

### Apple Best Practices Audit

Audited the server implementation against Apple's 10-point backend checklist (from Xcode screenshots):

**Score: 15/18 PASS, 2 PARTIAL, 1 FAIL** (post-P1: error messages sanitized)

| # | Requirement | Status |
| --- | --- | --- |
| 1 | Verify Apple ID token signature via JWKS | PASS |
| 2 | **Validate nonce to prevent replay attacks** | **FAIL** |
| 3 | Check token expiration | PASS |
| 4 | Verify issuer is `https://appleid.apple.com` | PASS |
| 5 | Verify audience matches bundle ID | PASS |
| 6 | Rate limit auth attempts | PASS |
| 7 | Store sessions in database | PASS |
| 8 | Implement JWT revocation | PASS |
| 9 | Log auth events | PASS |
| 10 | Use strong JWT signing secret (256+ bits) | PASS |
| 11 | Appropriate JWT expiry | OK (15 min, more secure than Apple's 1h recommendation) |
| 12 | Cache Apple public keys | PASS (jose manages) |
| 13 | Handle null email/name after first sign-in | PASS |
| 14 | Monitor for suspicious patterns | PARTIAL (rate limiting only) |
| 15 | HTTPS only | PASS (Databricks Apps enforce) |
| 16 | Request timeouts | PARTIAL (Express defaults) |
| 17 | Validate all input fields | PASS |
| 18 | Generic error messages | **PASS** (sanitized — error codes only, no detail leakage) |

The nonce gap was the critical finding — without it, a captured Apple identity token could be replayed within its ~10-minute validity window.

---

### P0 Fixes Implemented

All 6 P0 items implemented in two files, aligning the server to the iOS client's contract:

#### 1. Nonce Verification (CRITICAL)

**File:** `auth-service.ts`
**Change:** `validateAppleToken(identityToken, nonce?)` — if nonce provided, SHA-256 hashes it and compares to the `nonce` claim in the decoded Apple JWT. Throws `'Nonce mismatch — possible replay attack'` on failure.

Also added `real_user_status?: number` to `AppleTokenPayload` (Apple's bot indicator: 0=unsupported, 1=unknown, 2=likely real). Extracted from the Apple JWT payload and logged on auth success.

#### 2. Endpoint Path Alias

**File:** `auth-routes.ts`
**Change:** Extracted handler into `handleAppleExchange` function, registered on both:
- `POST /api/v1/auth/apple` (original, backward compat)
- `POST /api/v1/auth/apple/exchange` (iOS path)

Both share the same rate limiter instance.

#### 3. Request Field Normalization

**File:** `auth-routes.ts`
**Change:** Accepts both conventions with fallbacks:
```
identityToken = body.appleIdToken || body.identity_token
deviceId      = body.deviceId     || body.device_id
nonce         = body.nonce
clientUserId  = body.userId
appVersion    = body.app_version  || body.appVersion
```

#### 4. userId Cross-Check (Apple Step 4)

**File:** `auth-routes.ts`
**Change:** If client sends `userId`, compares it to the validated token's `sub` claim. Returns 400 on mismatch with a warning log.

#### 5. Response Field Aliases

**File:** `auth-routes.ts`
**Change:** Response now includes both conventions:
```
// snake_case (original — load test UI, curl)
...tokens,
// camelCase (iOS JWTExchangeResponse decoder)
jwt:          tokens.access_token,
refreshToken: tokens.refresh_token,
expiresIn:    tokens.expires_in,
userId:       tokens.user_id,
tokenType:    tokens.token_type,
```

#### 6. real_user_status Extraction (P1, done early)

**File:** `auth-service.ts`
**Change:** `AppleTokenPayload.real_user_status` populated from Apple JWT. Logged in auth success message.


### P1 Fix Implemented

#### 7. Error Message Sanitization

**File:** `auth-routes.ts`
**Change:** Replaced 6 client-facing error messages that leaked implementation details with generic messages + machine-readable error codes.

| Leaked Detail (before) | Client Message (after) | Error Code |
| --- | --- | --- |
| `JWT_SIGNING_SECRET not provisioned` | `Auth service not available` | `SERVICE_UNAVAILABLE` |
| `Apple identity JWT from ASAuthorizationAppleIDCredential` | `Missing required field: appleIdToken` | `MISSING_FIELD` |
| `DeviceIdentifier.current from iOS Keychain` | `Missing required field: deviceId` | `MISSING_FIELD` |
| `userId does not match Apple identity token sub claim` | `Authentication failed` | `IDENTITY_MISMATCH` |
| Raw exception (e.g. "Apple identity token has expired") | `Authentication failed` | `TOKEN_EXPIRED` / `NONCE_INVALID` / `SIGNATURE_INVALID` / `AUDIENCE_MISMATCH` / `APPLE_AUTH_FAILED` |
| Raw refresh error (e.g. "Refresh token has been revoked") | `Token refresh failed` | `TOKEN_EXPIRED` / `TOKEN_REVOKED` / `INVALID_TOKEN` / `REFRESH_FAILED` |

All detailed error messages remain in `console.error()` for server-side OTel log capture. The `code` field gives the iOS app programmatic error handling without exposing internals.

**Design decision:** Error codes use `UPPER_SNAKE_CASE` constants that the iOS app can switch on. The `/refresh` endpoint already had `TOKEN_EXPIRED` and `TOKEN_REVOKED` codes — this change extends the pattern to all auth endpoints and adds `NONCE_INVALID`, `SIGNATURE_INVALID`, `AUDIENCE_MISMATCH`, `IDENTITY_MISMATCH`, `APPLE_AUTH_FAILED`, `INVALID_TOKEN`, `REFRESH_FAILED`, `MISSING_FIELD`, `SERVICE_UNAVAILABLE`, and `INTERNAL_ERROR`.

#### 8. Structured JSON Auth Logging

**Files:** `auth-logger.ts` (new), `auth-routes.ts`, `auth-service.ts`

Created a centralized `auth-logger.ts` utility that emits structured JSON log lines consumed by the OTel log exporter. All auth events are now machine-parseable JSON with standardized fields.

**Privacy:** All identifiers (user_id, device_id, apple_sub) are SHA-256 hashed and truncated to 12 hex chars before logging. This preserves cross-entry correlation without storing raw PII.

**Event types:** `apple_exchange`, `token_refresh`, `token_revoke`, `service_init`, `migration`, `token_reuse_detected`

**Standard fields per log entry:**
| Field | Type | Description |
| --- | --- | --- |
| `logger` | string | Always `"auth"` |
| `event` | string | Event type identifier |
| `outcome` | string | `success`, `failure`, or `warn` |
| `ts` | string | ISO-8601 timestamp |
| `error_code` | string | Machine-readable code (matches sanitized client codes) |
| `error_detail` | string | Detailed message (server-side only) |
| `user_id_hash` | string | SHA-256 prefix of user UUID |
| `device_id_hash` | string | SHA-256 prefix of device UUID |
| `apple_sub_hash` | string | SHA-256 prefix of Apple sub |
| `duration_ms` | number | Request processing time |
| `real_user_status` | number | Apple fraud indicator (0/1/2) |
| `client_ip` | string | From x-forwarded-for |
| `platform` | string | e.g. `apple_healthkit` |
| `app_version` | string | Client-reported version |

**Coverage:** 21 logAuthEvent() calls across 2 files (14 in auth-routes.ts, 7 in auth-service.ts). 3 console.warn calls retained for developer-facing provisioning instructions.

**Design decisions:**
- JSON lines to console (not a logging framework) — OTel log exporter already captures console output
- Hash prefix length 12 hex = 48 bits — collision probability ~1/281 trillion
- `getClientIp()` utility extracts from x-forwarded-for for rate limit correlation
- Startup/provisioning warnings kept as console.warn for dev ergonomics (alongside structured logs)
- Migration events include `tables_created` and `tables_existed` arrays for operational visibility

#### 9. Explicit Request Timeouts

**Files:** `timeout.ts` (new), `auth-service.ts`, `auth-routes.ts`

Two-layer timeout architecture prevents hung external calls from blocking clients:

**Layer 1 — Service-level (auth-service.ts):**
- `createRemoteJWKSet` configured with `timeoutDuration: 5000ms` for Apple JWKS HTTP fetch
- `jwtVerify` wrapped with `withTimeout(10000ms)` for overall Apple token validation
- All Lakebase queries routed through `private query()` helper with `withTimeout(5000ms)`
- DDL/migration queries use longer `10000ms` timeout

**Layer 2 — Route-level (auth-routes.ts):**
- Each catch block detects `TimeoutError` via `instanceof` check
- Maps to HTTP 504 Gateway Timeout with error code `TIMEOUT`
- Structured log entry with `errorCode: 'TIMEOUT'` and the timeout label/duration
- Health endpoint reports `request_timeouts: true`

**Timeout constants:**
| Constant | Value | Scope |
| --- | --- | --- |
| `APPLE_JWKS_FETCH_TIMEOUT_MS` | 5,000ms | jose HTTP fetch for Apple's JWKS keys |
| `APPLE_VALIDATION_TIMEOUT_MS` | 10,000ms | Overall Apple token validation (JWKS + verify + nonce) |
| `LAKEBASE_QUERY_TIMEOUT_MS` | 5,000ms | Individual DML/query operations |
| `LAKEBASE_DDL_TIMEOUT_MS` | 10,000ms | CREATE TABLE, migrations (startup) |

**Utility:** `timeout.ts` provides `withTimeout<T>(promise, ms, label)` using `Promise.race` with `clearTimeout` on resolution (prevents dangling timer handles). `TimeoutError` carries `label` and `timeoutMs` properties for structured logging.

**Design decisions:**
- Promise.race (not AbortSignal) — compatible with any promise API including jose and pg
- Underlying operation NOT cancelled — continues in background (acceptable for Postgres DML)
- Timer cleaned up on normal resolution — prevents handle leak blocking graceful shutdown
- TimeoutError re-exported from auth-service.ts — route handlers import from single source
- TimeoutError re-thrown without wrapping in Apple catch block — preserves instanceof check

---

## Phase 2: Connect Auth to Ingest

**Goal:** Wire the authenticated user identity (JWT `sub` claim = Lakebase user_id UUID) into the HealthKit ingest pipeline so the bronze table's `user_id` column contains real, validated user IDs instead of `'anonymous'`.

**Key insight:** The route guard (`spn-route-guard.ts`) already validates Bearer JWTs and populates `req.auth` for all `/api/*` routes — this was implemented in Phase 1 but wasn't consumed by the ingest pipeline. Phase 2 is a 2-file change.

### Changes

#### 1. extract-user.ts — Replaced placeholder with req.auth?.sub

**Before:** Branch 1 saw Bearer tokens but returned `'anonymous'` with a TODO comment about implementing JWT validation.

**After:** Branch 1 checks `req.auth?.sub`. If the route guard (or optionalAuth) validated the JWT, `req.auth` contains the decoded `AccessTokenPayload` with `sub` = Lakebase user_id UUID. No JWT validation logic in this file — that responsibility belongs to the middleware.

New priority order:
1. `req.auth?.sub` — App JWT validated by middleware → Lakebase user_id UUID
2. `x-forwarded-email` — Workspace traffic → email string
3. `'anonymous'` — No auth context

#### 2. ingest-routes.ts — Added optionalAuth + user_id logging

- **Import:** Added `optionalAuth` from `jwt-auth.ts`
- **Middleware chain:** `textParser → optionalAuth → handler` (defense-in-depth: short-circuits if route guard already set `req.auth`)
- **Comment update:** User identity section reflects the new auth-aware flow
- **Log update:** Success message now includes `user=${userId}` for operational visibility
- **Step 4 comment:** Updated from "Extract user identity from Bearer JWT" to "Extract user identity (req.auth.sub from validated JWT, or x-forwarded-email)"

### End-to-end data flow

```
iOS app
  → Bearer JWT in Authorization header
  → spn-route-guard.ts: verifyAccessToken(token) → req.auth = { sub, device_id, platform }
  → optionalAuth: req.auth already set → next() (short-circuit)
  → extractUser(req): reads req.auth.sub → returns Lakebase user_id UUID
  → zeroBusService.buildRecord(userId=UUID)
  → ZeroBus SDK gRPC stream
  → Bronze table: user_id column = authenticated UUID
```

Workspace traffic follows Branch 2: `x-forwarded-email` → email string → bronze table `user_id`.

### Design decisions

- **No code duplication:** JWT validation lives exclusively in middleware (route guard + jwt-auth.ts). `extract-user.ts` just reads the validated result.
- **Defense-in-depth:** `optionalAuth` is added even though the route guard already handles it. The short-circuit in `jwt-auth.ts` (`if (req.auth) { next(); return; }`) prevents double verification.
- **No breaking changes:** Workspace traffic and anonymous callers continue to work exactly as before. Only mobile clients with valid JWTs get their real user_id instead of 'anonymous'.
- **load-test-routes.ts benefits automatically:** It also calls `extractUser(req)`, so authenticated load test requests will get real user_ids without any code changes.

---

### Files Modified

| File | Changes | Lines |
| --- | --- | --- |
| `server/utils/timeout.ts` | **New file.** `withTimeout<T>()` generic promise deadline utility. `TimeoutError` class with `label` + `timeoutMs`. `Promise.race` with `clearTimeout`. | 0 → 88 |
| `server/routes/zerobus/ingest-routes.ts` | Phase 2: added `optionalAuth` middleware, updated user identity comments, added `user_id` to success log | 393 → 397 |
| `server/utils/extract-user.ts` | Phase 2: replaced Branch 1 Bearer placeholder with `req.auth?.sub` check. Removed TODO + console.info. Added auth pipeline JSDoc. | 64 → 78 |
| `server/utils/auth-logger.ts` | **New file.** Structured JSON auth logger: `logAuthEvent()`, `hashId()` (SHA-256 prefix), `getClientIp()`. 6 event types, typed interface. | 0 → 158 |
| `server/services/auth-service.ts` | Nonce verification, `real_user_status`, structured logging, timeouts (private `query()` helper, `withTimeout` on Apple validation + all Lakebase calls, 4 timeout constants, `TimeoutError` re-export) | 569 → 737 |
| `server/routes/auth/auth-routes.ts` | Shared `handleAppleExchange` handler, `/apple/exchange` alias, camelCase field normalization, nonce passthrough, userId cross-check, dual-convention response, error sanitization, structured logging (17 logAuthEvent calls), timeout handling (`TimeoutError` → 504 in all 3 catch blocks, health reports `request_timeouts`) | 230 → 528 |

---

### Design Decisions

| Decision | Rationale |
| --- | --- |
| Server aligns to iOS (not vice versa) | iOS app is compiled and distributed; server is continuously deployed. Cheaper to change server. |
| Accept both field name conventions | Avoids breaking existing server consumers (load test UI, curl examples) while supporting iOS camelCase |
| Shared handler function, not redirect | `app.handle(req, res)` would double-count rate limits and mutate req.url. Named function registered on both paths avoids both issues. |
| Nonce is optional (`nonce?: string`) | Allows existing non-iOS callers (workspace users, load tests) to continue without nonces. iOS always sends one. |
| userId cross-check is lenient | Only rejects if `userId` is present AND mismatches. Absent `userId` is fine — server trusts the validated token's `sub`. |
| `real_user_status` extracted but not enforced | Logged for observability; enforcement (blocking `status=1` users) deferred to production hardening. |

---

### Remaining Work

#### P1 — Should Fix

| # | Task | Files | Status |
| --- | --- | --- | --- |
| 7 | Sanitize error messages (generic client, detailed server logs) | `auth-routes.ts` | **Done** |
| 8 | Structured JSON auth logging (hashed identifiers for OTel) | `auth-logger.ts`, `auth-routes.ts`, `auth-service.ts` | **Done** |

#### P2 — Nice to Have

| # | Task | Files | Status |
| --- | --- | --- | --- |
| 9 | Explicit request timeouts (Apple JWKS, Lakebase queries, route 504) | `timeout.ts`, `auth-service.ts`, `auth-routes.ts` | **Done** |

#### Deployment

Bundle validation (`databricks bundle validate --strict --target dev`) could not run on serverless compute (permission error on temp directory). Run from web terminal or local CLI, then deploy.

#### Phase 2 — Connect Auth to Ingest (unchanged from 2026-04-26)

Steps 2.1–2.6: Create shared `extractUser()`, wire `optionalAuth` into ingest routes, remove `userId` from client POST body.

---

### Secret Scope State (dbxw_zerobus_credentials)

All 10 keys now provisioned:

| Key | Status | Provisioner |
| --- | --- | --- |
| `client_id_dev_matthew_giglia_wearables` | ✓ | UC setup job |
| `client_secret_dev_matthew_giglia_wearables` | ✓ | Admin |
| `workspace_url` | ✓ | UC setup job |
| `zerobus_endpoint` | ✓ | UC setup job |
| `target_table_name` | ✓ | UC setup job |
| `zerobus_stream_pool_size` | ✓ | UC setup job |
| `jwt_signing_secret` | ✓ | UC setup job |
| `apple_bundle_id` | ✓ | UC setup job |
| `ios_spn_application_id` | ✓ | UC setup job |
| `ios_bootstrap_client_secret_dev_matthew_giglia_wearables` | ✓ | Admin (this session) |
