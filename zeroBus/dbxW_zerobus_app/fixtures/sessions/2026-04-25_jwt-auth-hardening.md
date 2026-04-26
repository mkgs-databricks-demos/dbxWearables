## Session: JWT Authentication (Phase 1) & Security Hardening

**Date:** 2026-04-25
**Bundle:** `dbxW_zerobus_app`

### Summary

Full implementation of Sign in with Apple JWT authentication for mobile clients, plus three security hardening layers: SPN route guard, per-endpoint rate limiting, and iOS bootstrap SPN architecture. Bundle validates cleanly in strict mode. Eight new or modified files, zero warnings.

---

### Phase 1: Sign in with Apple JWT Authentication

#### Problem

The AppKit server had no user-level authentication. The App → Workspace layer uses M2M OAuth (platform-managed SPN), but there was no mechanism for identifying individual mobile users sending HealthKit data. Without user identity, the bronze table's `user_id` column would remain empty and per-user data attribution is impossible.

#### Solution: Two-Layer Auth Model

| Layer | Direction | Mechanism |
| --- | --- | --- |
| User → App | Mobile client → AppKit server | App-issued JWT via Sign in with Apple |
| App → Workspace | AppKit server → Databricks | M2M OAuth SPN (platform-managed, pre-existing) |

Mobile users authenticate once via Sign in with Apple. The server validates the Apple identity token (JWKS signature + issuer/audience/expiry), registers the user in Lakebase, and issues a short-lived app JWT (HS256, 15 min) + opaque refresh token (SHA-256 hashed, 30-day expiry).

#### New Files Created

**`server/services/auth-service.ts`** (~383 lines) — Core authentication service:
- Apple JWKS validation using `jose` library (fetches `https://appleid.apple.com/auth/keys`)
- HS256 JWT signing for app-issued access tokens
- Refresh token rotation implementing RFC 6819 (revoke old, issue new)
- Lakebase CRUD operations for `auth.users`, `auth.devices`, `auth.refresh_tokens` tables
- Idempotent migration (creates `auth` schema + tables on first startup)
- `isReady()` guard for graceful degradation when `JWT_SIGNING_SECRET` not provisioned

**`server/middleware/jwt-auth.ts`** (~130 lines) — Express middleware:
- `requireAuth` — returns 401 if no valid Bearer token present
- `optionalAuth` — attaches user info if present, continues without error if missing
- Augments `req.auth` with decoded `AccessTokenPayload` (`sub`, `device_id`, `platform`)
- Short-circuits when `req.auth` already set by the route guard (avoids double verification)

**`server/routes/auth/auth-routes.ts`** (~234 lines) — Four endpoints:
- `POST /api/v1/auth/apple` — Exchange Apple identity token for app JWT + refresh token
- `POST /api/v1/auth/refresh` — Silent token renewal with rotation
- `POST /api/v1/auth/revoke` — Revoke refresh token (requires valid access JWT)
- `GET /api/v1/auth/health` — Auth subsystem health check (reports env vars, hardening status)

#### JWT Claims (Access Token)

```json
{
  "sub": "<user_id UUID from Lakebase auth.users>",
  "device_id": "<X-Device-Id from iOS Keychain>",
  "platform": "apple_healthkit",
  "iat": "<timestamp>",
  "exp": "<iat + 900>"
}
```

#### Lakebase Auth Tables

| Table | Key | Purpose |
| --- | --- | --- |
| `auth.users` | `user_id` UUID (PK), `apple_sub` (UNIQUE) | One row per authenticated person |
| `auth.devices` | `device_id` TEXT (PK) → `user_id` FK | Links device installs to users (multi-device) |
| `auth.refresh_tokens` | `token_hash` TEXT (PK) → `user_id` + `device_id` FK | SHA-256 hashes, 30-day expiry, revocable |

#### Library Choice: `jose` over `jsonwebtoken`

The project uses ESM (`"type": "module"`). The `jsonwebtoken` package is CJS-only and requires pairing with `jwks-rsa` for Apple JWKS. `jose` is ESM-native, zero native deps, W3C-recommended, and combines JWT verification + JWKS fetching in a single package.

---

### Phase 2: Security Hardening

#### Problem

With auth endpoints exposed, three attack surfaces needed mitigation:

1. **iOS bootstrap chicken-and-egg** — The iOS app needs credentials to reach auth endpoints _before_ the user signs in with Apple. Embedding the app's main SPN credentials would over-privilege the mobile client.
2. **No route-level access control** — All authenticated callers (workspace users, JWT users, SPNs) had equal access to all routes.
3. **No rate limiting** — Auth endpoints (especially the Apple exchange) were vulnerable to brute-force and credential-stuffing attacks.

#### Solution 1: SPN Route Guard

**`server/middleware/spn-route-guard.ts`** (~190 lines) — Global middleware registered on `/api/*` before all route handlers.

**Caller identification (priority order):**

1. `Authorization: Bearer <token>` validates as app JWT → `app-jwt-user`
2. `x-forwarded-email` contains `@` → `workspace-user` (proxy-authenticated)
3. Proxy headers present + matches `IOS_SPN_APPLICATION_ID` → `ios-spn` (verified)
4. Proxy headers present, no match → `proxy-unverified` (unknown SPN)
5. No auth context → `anonymous`

**Access control matrix (route zones):**

| Caller Type | Auth | Ingest | Admin | Health |
| --- | --- | --- | --- | --- |
| workspace-user | Yes | Yes | Yes | Yes |
| app-jwt-user | Yes | Yes | No | Yes |
| ios-spn | Yes | No | No | Yes |
| proxy-unverified | Yes | No | No | Yes |
| anonymous | No | No | No | Yes |

**Route zone classification:**
- `health`: path ends in `/health`
- `auth`: `/api/v1/auth/*`
- `ingest`: `/api/v1/healthkit/*`
- `admin`: everything else under `/api/`

**Design decision:** The route guard populates `req.auth` during Bearer token validation (Priority 1), so `jwt-auth.ts` middleware short-circuits when `req.auth` is already set. This prevents double token verification without coupling the two middlewares.

#### Solution 2: Per-Endpoint Rate Limiting

**`server/middleware/rate-limit.ts`** (~175 lines) — In-memory sliding window rate limiter factory.

| Endpoint | Window | Max Requests | Rationale |
| --- | --- | --- | --- |
| `POST /api/v1/auth/apple` | 15 min | 10 | Bootstrap is once per install |
| `POST /api/v1/auth/refresh` | 1 min | 20 | Multi-device simultaneous refresh |
| `POST /api/v1/auth/revoke` | 1 min | 10 | Logout is infrequent |

Features:
- Standard headers on every response: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`
- `Retry-After` header on 429 responses
- Key extraction from `x-forwarded-for` (AppKit proxy) with `req.ip` fallback
- Periodic cleanup of expired window entries (60-second sweep interval)
- Pre-configured factory functions: `authAppleLimiter()`, `authRefreshLimiter()`, `authRevokeLimiter()`

**Design decision:** In-memory counters (not Lakebase-backed). Databricks Apps run as single instances, so in-memory state is sufficient and avoids database round-trips on every request. The `createRateLimiter()` factory interface is stable — swap to Lakebase-backed storage if horizontal scaling is needed.

#### Solution 3: Three-SPN Architecture

| SPN | Purpose | Permissions | Credential Location |
| --- | --- | --- | --- |
| App (auto-provisioned) | AppKit server operations | Broad (ZeroBus, UC, Lakebase) | Platform-injected |
| ZeroBus SPN | gRPC streaming to bronze table | UC table write only | Secret scope → env vars |
| iOS bootstrap SPN | Auth endpoint access for sign-in | CAN_USE on app resource ONLY | Embedded in iOS binary |

The iOS bootstrap SPN is a dedicated identity with minimal permissions. Even if its credentials are extracted from the iOS binary, the route guard restricts it to auth routes only, and Apple's hardware-bound identity token validation provides the cryptographic second factor.

---

### Configuration Changes

#### `server/server.ts`

- Imported and initialized `authService.setup(appkit.lakebase)` before route registration
- Imported and called `setupRouteGuard(appkit)` as global middleware before all route handlers
- Imported and registered `setupAuthRoutes(appkit)` with rate limiters

#### `package.json`

- Added `jose ^5.0.0` dependency (ESM-native JWT + JWKS library)

#### `app.yaml`

Added three new environment variables (all with `valueFrom` from secret scope):
- `JWT_SIGNING_SECRET` — HS256 signing key for app-issued JWTs
- `APPLE_BUNDLE_ID` — iOS app bundle identifier for Apple token `aud` validation
- `IOS_SPN_APPLICATION_ID` — iOS bootstrap SPN identity for route guard verification

#### `resources/zerobus_ingest.app.yml`

Added three new secret resources (10 total, up from 7):
- `jwt-signing-secret` → `${var.jwt_signing_secret_key}` in `${var.secret_scope_name}`
- `apple-bundle-id` → `${var.apple_bundle_id_key}` in `${var.secret_scope_name}`
- `ios-spn-application-id` → `${var.ios_spn_application_id_key}` in `${var.secret_scope_name}`

#### `databricks.yml`

Added three new variables with defaults matching secret scope key names:
- `jwt_signing_secret_key` (default: `jwt_signing_secret`)
- `apple_bundle_id_key` (default: `apple_bundle_id`)
- `ios_spn_application_id_key` (default: `ios_spn_application_id`)

Includes provisioning instructions in comments:
```bash
databricks secrets put-secret dbxw_zerobus_credentials jwt_signing_secret --string-value "$(openssl rand -base64 32)"
databricks secrets put-secret dbxw_zerobus_credentials apple_bundle_id --string-value "com.dbxwearables.healthKit"
databricks secrets put-secret dbxw_zerobus_credentials ios_spn_application_id --string-value "<spn-application-id-uuid>"
```

#### `README.md`

Added comprehensive documentation:
- JWT Authentication section with token lifecycle table, JWT claims, Lakebase auth tables
- Auth Hardening section with route guard access matrix, rate limiting table, three-SPN architecture
- Implementation files reference table
- iOS bootstrap SPN provisioning step-by-step
- Updated app resources table (10 total)

---

### Design Decisions

| Decision | Rationale |
| --- | --- |
| `jose` over `jsonwebtoken` + `jwks-rsa` | ESM-native, zero native deps, single package for JWT + JWKS |
| HS256 (symmetric) for app JWTs | Single server instance — no need for asymmetric keys; simpler key rotation |
| 15-min access / 30-day refresh tokens | Balance between security (short access) and UX (infrequent re-auth) |
| Route guard before route handlers | Single enforcement point — no route can accidentally skip access control |
| req.auth populated by route guard | Eliminates double verification; jwt-auth.ts short-circuits if already set |
| In-memory rate limiting | Single-instance app; avoids DB round-trips; factory interface allows future swap |
| Graceful degradation | Auth is optional — app works without JWT_SIGNING_SECRET for non-auth use cases |
| Token hash storage (not plaintext) | SHA-256 hash of refresh tokens in Lakebase — database breach doesn't expose tokens |
| Dedicated iOS SPN (CAN_USE only) | Minimal blast radius if iOS-embedded credentials are compromised |

---

### Files Modified Summary

| File | Change Type | Lines | Purpose |
| --- | --- | --- | --- |
| `server/services/auth-service.ts` | New | ~383 | Apple JWKS, JWT signing, Lakebase CRUD, migration |
| `server/middleware/jwt-auth.ts` | New | ~130 | requireAuth / optionalAuth Express middleware |
| `server/middleware/spn-route-guard.ts` | New | ~190 | Global caller identification + access matrix |
| `server/middleware/rate-limit.ts` | New | ~175 | Sliding window rate limiter factory + auth presets |
| `server/routes/auth/auth-routes.ts` | New | ~234 | 4 auth endpoints with rate limiters |
| `server/server.ts` | Modified | +15 | Auth service init, route guard, auth routes |
| `package.json` | Modified | +1 | `jose ^5.0.0` dependency |
| `app.yaml` | Modified | +25 | 3 new env vars (JWT, Apple, iOS SPN) |
| `resources/zerobus_ingest.app.yml` | Modified | +35 | 3 new secret resources (10 total) |
| `databricks.yml` | Modified | +30 | 3 new variables + provisioning instructions |
| `README.md` | Modified | +120 | Auth + hardening documentation |

### Bundle Validation

```
databricks bundle validate --strict --target dev
→ Validation OK! (no warnings)
```
