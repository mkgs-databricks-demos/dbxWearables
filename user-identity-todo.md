# User Identity & Authentication — Planning Document

**Project:** dbxWearables-ZeroBus  
**Status:** Planning (no code changes yet)  
**Created:** 2026-04-18  
**Last Updated:** 2026-04-18

---

## Problem Statement

The current data flow has **no user identity**. Every record in the bronze table (`hls_fde_dev.dev_matthew_giglia_wearables.wearables_zerobus`) can be traced to a *device install* (via `headers::"x-device-id"`), a *platform* (via `source_platform`), and a *data source app* (via `body:source_name`), but **not to a person**.

For the single-user demo this is fine. For multi-user production, every ingested record must be attributable to a specific authenticated user.

---

## Why HealthKit Doesn’t Solve This

Apple HealthKit is **local-only and privacy-first** — it does not expose any user identifier:

- No API to access the user’s Apple ID, name, or any stable person identifier
- `HKSource` (`source_name`, `source_bundle_id`) identifies the *app/device that wrote the data*, not the person
- Apple explicitly forbids using HealthKit data to identify users

The iOS app’s `DeviceIdentifier.swift` generates a **per-installation UUID** stored in the Keychain. It persists across app updates but is lost on uninstall/reinstall. It identifies *this app install on this phone*, not the person. A single user with an iPhone and an iPad would appear as two different device IDs.

### Current Data Traceability

| What we can trace | Where it lives | Identifies |
| --- | --- | --- |
| Device install | `headers::"x-device-id"` | App installation (Keychain UUID) |
| Platform | `source_platform` column | Data source (apple_healthkit, etc.) |
| Source app | `body:source_name`, `body:source_bundle_id` | HK data contributor (Apple Watch, iPhone, etc.) |
| HealthKit sample | `body:uuid` | Individual HK record (for dedup/deletes) |
| **User (person)** | **❌ MISSING** | **Not identifiable** |

---

## Constraint

**Onboarding each app user as a Databricks workspace identity (consumer persona) is not possible.** This means:

- No Databricks-native OAuth for end users
- No per-user service principals
- Can’t use Databricks’ OIDC directly for end users
- The Databricks App’s built-in OAuth2 protection is for workspace-to-app communication (notebook → app, service → app), not for public mobile clients

---

## Recommended Architecture: App-Managed JWT Auth with Lakebase User Registry

### Why This Approach

1. **Lakebase is already deployed** in the `dbxW_zerobus_infra` bundle — no new infrastructure
2. **Sign in with Apple** is the natural iOS identity provider — required by the App Store for apps with login
3. **The Databricks App already handles OAuth** — the app-to-workspace auth uses an M2M service principal, so user auth is a separate concern at the app layer
4. **The app issues its own JWTs** — lightweight, no external auth service needed
5. **The `authorization` header is already stripped** by the server’s blocklist — the JWT never lands in the bronze `headers` VARIANT

### Two-Layer Auth Model

The system uses two independent authentication layers:

| Layer | Who authenticates | To what | Mechanism | Status |
| --- | --- | --- | --- | --- |
| App → Workspace | Service principal | ZeroBus / Unity Catalog | M2M OAuth client credentials | **Existing** |
| User → App | Mobile user | Databricks App | App-issued JWT (via Sign in with Apple) | **New** |

Users never touch Databricks auth. The service principal is the single identity writing to ZeroBus. Users authenticate to the *app*, and the app writes on their behalf.

### Architecture Diagram

```
┌─────────────┐                    ┌──────────────────────────────────────────┐
│  iOS App     │                    │  Databricks App (AppKit)                 │
│              │                    │                                          │
│  Sign in     │  Apple ID Token    │  /api/v1/auth/apple  (public endpoint)  │
│  with Apple ─┼───────────────────►│  ┌─────────────────┐                    │
│              │                    │  │ Validate Apple   │  Apple JWKS        │
│              │                    │  │ identity token   │◄─── (cached)       │
│              │   App JWT          │  └────────┬────────┘                    │
│              │◄───────────────────│           │                              │
│              │                    │  ┌────────▼────────┐                    │
│              │                    │  │ Upsert user in  │                    │
│              │                    │  │ Lakebase         │──► users table     │
│  POST /ingest│  Bearer: app_jwt   │  └─────────────────┘                    │
│  X-Record-   ┼───────────────────►│                                          │
│  Type: ...   │                    │  JWT middleware extracts user_id         │
│              │                    │  ┌─────────────────┐                    │
│              │                    │  │ ZeroBus insert   │──► Bronze table    │
│              │   200 OK           │  │ (+ user_id col)  │    (+ user_id)    │
│              │◄───────────────────│  └─────────────────┘                    │
└─────────────┘                    │  (M2M SPN auth to workspace — existing) │
                                    └──────────────────────────────────────────┘
```

---

## Lakebase Schema (3 tables)

Stored in the existing Lakebase PostgreSQL instance deployed by `dbxW_zerobus_infra`.

### `users`

| Column | Type | Constraints | Description |
| --- | --- | --- | --- |
| `user_id` | `UUID` | `PRIMARY KEY` | App-generated, stable across devices |
| `apple_sub` | `TEXT` | `UNIQUE NOT NULL` | Apple’s privacy-preserving user ID (`sub` claim) |
| `display_name` | `TEXT` | | From Apple (user can choose to hide) |
| `created_at` | `TIMESTAMPTZ` | `NOT NULL DEFAULT NOW()` | |
| `last_seen_at` | `TIMESTAMPTZ` | | Updated on each auth request |

### `devices`

| Column | Type | Constraints | Description |
| --- | --- | --- | --- |
| `device_id` | `TEXT` | `PRIMARY KEY` | From `X-Device-Id` header (Keychain UUID) |
| `user_id` | `UUID` | `REFERENCES users` | Links device to person |
| `platform` | `TEXT` | | `apple_healthkit`, `android_health_connect`, etc. |
| `app_version` | `TEXT` | | From `X-App-Version` header |
| `first_seen_at` | `TIMESTAMPTZ` | `NOT NULL DEFAULT NOW()` | |
| `last_seen_at` | `TIMESTAMPTZ` | | Updated on each request |

### `refresh_tokens`

| Column | Type | Constraints | Description |
| --- | --- | --- | --- |
| `token_hash` | `TEXT` | `PRIMARY KEY` | SHA-256 of refresh token (never store raw) |
| `user_id` | `UUID` | `REFERENCES users` | |
| `device_id` | `TEXT` | `REFERENCES devices` | |
| `expires_at` | `TIMESTAMPTZ` | `NOT NULL` | |
| `revoked_at` | `TIMESTAMPTZ` | | `NULL` if active; set on explicit revoke |

---

## Token Lifecycle

| Token | Lifetime | Storage (iOS) | Storage (Server) | Purpose |
| --- | --- | --- | --- | --- |
| Apple identity token | ~10 min | Transient | Not stored | Exchanged once during Sign in with Apple |
| App access JWT | 15 min | Keychain (`KeychainHelper`) | Not stored (stateless) | Bearer token for all API calls |
| App refresh token | 30 days | Keychain (`KeychainHelper`) | Lakebase `refresh_tokens` (hashed) | Silent token renewal without re-auth |

### JWT Claims (Access Token)

```json
{
  "sub": "<user_id UUID from Lakebase users table>",
  "device_id": "<X-Device-Id from Keychain>",
  "platform": "apple_healthkit",
  "iat": 1776500000,
  "exp": 1776500900
}
```

Signed with an app secret stored in the existing Databricks secret scope (`dbxw_zerobus_secrets`). The server validates the signature and extracts `sub` as `user_id` — this is the value written to the bronze table column, not a client-supplied header.

---

## New API Endpoints

| Endpoint | Auth Required | Method | Purpose |
| --- | --- | --- | --- |
| `/api/v1/auth/apple` | Public (no JWT) | `POST` | Exchange Apple identity token → app JWT + refresh token |
| `/api/v1/auth/refresh` | Refresh token only | `POST` | Exchange refresh token → new access JWT |
| `/api/v1/auth/revoke` | Access JWT | `POST` | Revoke refresh token (logout) |
| `/api/v1/healthkit/ingest` | Access JWT | `POST` | **Existing** — add JWT validation middleware |
| `/api/v1/healthkit/health` | Access JWT | `GET` | **Existing** — add JWT validation middleware |

### Auth Endpoint: `POST /api/v1/auth/apple`

**Request:**
```json
{
  "identity_token": "<Apple identity JWT>",
  "device_id": "<DeviceIdentifier.current>",
  "platform": "apple_healthkit",
  "app_version": "1.0.0"
}
```

**Server flow:**
1. Validate Apple identity token JWT signature against Apple’s JWKS (`https://appleid.apple.com/auth/keys`)
2. Extract `sub` claim (Apple’s stable, privacy-preserving user identifier)
3. Upsert user in Lakebase `users` table (keyed on `apple_sub`)
4. Upsert device in Lakebase `devices` table (keyed on `device_id`, linked to `user_id`)
5. Generate app access JWT (15 min, signed with app secret)
6. Generate refresh token (30 days, store hash in Lakebase)

**Response:**
```json
{
  "access_token": "<app JWT>",
  "refresh_token": "<opaque token>",
  "expires_in": 900,
  "token_type": "Bearer",
  "user_id": "<UUID>"
}
```

### Auth Endpoint: `POST /api/v1/auth/refresh`

**Request:**
```json
{
  "refresh_token": "<opaque token>"
}
```

**Server flow:**
1. Hash the refresh token, look up in Lakebase `refresh_tokens`
2. Verify not expired, not revoked
3. Issue new access JWT
4. Optionally rotate refresh token (issue new, revoke old)

**Response:** Same shape as `/auth/apple` response.

---

## Auth Bootstrap: Public Endpoints

The Databricks App enforces OAuth at the platform level. For the `/api/v1/auth/*` endpoints to be reachable without a Databricks workspace identity, the app needs one of:

1. **Route-level auth configuration** in `app.yaml` — mark `/api/v1/auth/*` as public
2. **Express middleware** that short-circuits before the platform auth check for auth routes
3. **App-level "no auth" mode** with all auth handled internally via Express middleware

This needs investigation during implementation — the exact mechanism depends on how AppKit exposes auth configuration.

---

## Server-Side Changes (Databricks App)

### New Files

| File | Purpose |
| --- | --- |
| `src/app/server/middleware/jwt-auth.ts` | Express middleware: validate app JWT, extract `user_id`, attach to `req` |
| `src/app/server/services/auth-service.ts` | Apple JWKS validation, Lakebase user CRUD, JWT signing/verification |
| `src/app/server/routes/auth/auth-routes.ts` | `/api/v1/auth/apple`, `/api/v1/auth/refresh`, `/api/v1/auth/revoke` |

### Modified Files

| File | Change |
| --- | --- |
| `src/app/server/routes/zerobus/ingest-routes.ts` | Add JWT auth middleware to POST handler; extract `user_id` from validated claims; pass to `buildRecord()` |
| `src/app/server/services/zerobus-service.ts` | Add `user_id: string` to `WearablesRecord` interface and `buildRecord()` |
| `src/app/server/server.ts` | Wire auth routes; configure public vs. protected route groups |
| `src/app/package.json` | Add `jsonwebtoken` (JWT signing) and `jwks-rsa` (Apple JWKS validation) |

### JWT Signing Secret

Stored in the existing Databricks secret scope (`dbxw_zerobus_secrets`). Injected via `app.yaml` as an environment variable:

```yaml
env:
  - name: JWT_SIGNING_SECRET
    valueFrom: dbxw_zerobus_secrets/jwt_signing_secret
```

---

## iOS App Changes

> **Note:** No changes to the `healthKit/` folder until implementation begins.

### New Files

| File | Purpose |
| --- | --- |
| `Services/AuthService.swift` | Handles Sign in with Apple, token storage, refresh, logout |
| `Views/Auth/SignInView.swift` | Sign in with Apple button UI |
| `ViewModels/AuthViewModel.swift` | Auth state management (`@Published isAuthenticated`) |

### Modified Files

| File | Change |
| --- | --- |
| `Utilities/KeychainHelper.swift` | Store access JWT and refresh token (currently stores a placeholder API token) |
| `Services/APIService.swift` | Use app JWT from KeychainHelper as Bearer token; handle 401 → automatic refresh |
| `App/dbxWearablesApp.swift` | Gate app on auth state; show SignInView when not authenticated |
| `App/AppDelegate.swift` | No change — sync is already gated on having a valid token |
| `Configuration/APIConfiguration.swift` | Add auth endpoint paths (`/api/v1/auth/apple`, `/api/v1/auth/refresh`) |

### Sign in with Apple Flow (iOS)

1. User taps “Sign in with Apple” button
2. `ASAuthorizationAppleIDProvider` presents system sheet
3. On success, receive `ASAuthorizationAppleIDCredential` with:
   - `identityToken` (JWT) — contains `sub` claim
   - `fullName` (optional, only on first auth)
   - `user` (opaque string, same as `sub`)
4. `AuthService` sends `identityToken` + `DeviceIdentifier.current` to `POST /api/v1/auth/apple`
5. Receives app JWT + refresh token, stores both in Keychain
6. All subsequent API calls use app JWT as Bearer token

### Token Refresh (iOS)

`APIService` handles 401 responses:

1. Catch 401 from any API call
2. Call `POST /api/v1/auth/refresh` with stored refresh token
3. On success: store new access JWT, retry original request
4. On failure (refresh expired/revoked): clear tokens, show SignInView

---

## Bronze Table Changes

### New Column

```sql
ALTER TABLE hls_fde_dev.dev_matthew_giglia_wearables.wearables_zerobus
ADD COLUMNS (
  user_id STRING COMMENT 'App-authenticated user ID extracted from validated JWT claims'
);
```

### Updated DDL (target-table-ddl notebook)

```sql
CREATE TABLE IF NOT EXISTS wearables_zerobus
(
  record_id       STRING    NOT NULL  COMMENT 'Server-generated GUID for each ingested record',
  ingested_at     TIMESTAMP           COMMENT 'Server-side ingestion timestamp',
  body            VARIANT             COMMENT 'Raw NDJSON line payload stored as VARIANT',
  headers         VARIANT             COMMENT 'All HTTP headers except auth/cookie (blocklist)',
  record_type     STRING              COMMENT 'From X-Record-Type header (any non-empty string)',
  source_platform STRING              COMMENT 'From X-Platform header (apple_healthkit, etc.)',
  user_id         STRING              COMMENT 'App-authenticated user ID from JWT claims',
  CONSTRAINT wearables_zerobus_pk PRIMARY KEY (record_id)
)
```

### Data Traceability After Implementation

| What we can trace | Where it lives | Identifies |
| --- | --- | --- |
| Device install | `headers::"x-device-id"` | App installation (Keychain UUID) |
| Platform | `source_platform` column | Data source (apple_healthkit, etc.) |
| Source app | `body:source_name`, `body:source_bundle_id` | HK data contributor |
| HealthKit sample | `body:uuid` | Individual HK record |
| **User (person)** | **`user_id` column** | **Authenticated person** |

---

## Implementation Order

Phased approach — each phase is independently deployable:

### Phase 1: Server-Side Auth Infrastructure
- [ ] Add `jsonwebtoken` and `jwks-rsa` to `package.json`
- [ ] Create `auth-service.ts` (Apple JWKS validation, JWT signing, Lakebase user CRUD)
- [ ] Create `jwt-auth.ts` middleware (validate JWT, extract `user_id`, attach to `req`)
- [ ] Create `auth-routes.ts` (`/api/v1/auth/apple`, `/api/v1/auth/refresh`, `/api/v1/auth/revoke`)
- [ ] Create Lakebase migration for `users`, `devices`, `refresh_tokens` tables
- [ ] Add `JWT_SIGNING_SECRET` to secret scope and `app.yaml`
- [ ] Configure public endpoint access for `/api/v1/auth/*`
- [ ] Wire auth routes in `server.ts`

### Phase 2: Ingest Route Integration
- [ ] Add JWT auth middleware to `POST /api/v1/healthkit/ingest`
- [ ] Add `user_id` to `WearablesRecord` interface and `buildRecord()`
- [ ] Add `user_id STRING` column to bronze table DDL + live ALTER TABLE
- [ ] Update validation notebook to test with JWT auth

### Phase 3: iOS App Auth
- [ ] Create `AuthService.swift` (Sign in with Apple, token storage/refresh)
- [ ] Create `SignInView.swift` (Sign in with Apple button)
- [ ] Create `AuthViewModel.swift` (auth state management)
- [ ] Update `KeychainHelper.swift` (store access JWT + refresh token)
- [ ] Update `APIService.swift` (use app JWT, handle 401 → refresh)
- [ ] Update `APIConfiguration.swift` (auth endpoint paths)
- [ ] Update `dbxWearablesApp.swift` (gate on auth state)
- [ ] Add Sign in with Apple capability in Xcode project

### Phase 4: Multi-Device Support
- [ ] Verify same user from multiple devices links to single `user_id`
- [ ] Test device registration/deregistration flow
- [ ] Dashboard: show per-user data aggregation

---

## Alternatives Considered

| Approach | Mechanism | Why not chosen |
| --- | --- | --- |
| Databricks consumer persona | Per-user workspace identity | Not possible per constraint |
| Per-user service principal | SPN per mobile user | Doesn’t scale, management overhead |
| External IdP (Auth0/Cognito) | Third-party auth service | Adds external dependency and cost |
| Device-as-proxy | Treat `X-Device-Id` as user | Breaks with multi-device, reinstalls |
| Firebase Auth | Google’s auth service | External dependency, Google ecosystem lock-in |
| OAuth2 public client (PKCE) | Users auth via Databricks OIDC | Requires workspace identity (ruled out) |

---

## Open Questions

1. **AppKit public endpoint configuration** — How does AppKit expose route-level auth overrides? Can specific paths be marked as public in `app.yaml`, or does the app need to handle all auth internally?

2. **Lakebase connection from AppKit** — The Lakebase plugin is already configured. Verify that the existing connection pool can be reused for the `users`, `devices`, and `refresh_tokens` tables.

3. **JWT signing algorithm** — `HS256` (symmetric, simpler, app secret) vs. `RS256` (asymmetric, key pair). For a single-app scenario, `HS256` with a Databricks secret is sufficient. If multiple services need to validate tokens, `RS256` is better.

4. **Apple Business Manager** — For enterprise distribution (not App Store), Sign in with Apple requires Apple Business Manager enrollment. Confirm distribution model.

5. **Refresh token rotation** — Should each refresh produce a new refresh token (rotation) or reuse the same one? Rotation is more secure but adds complexity. Recommendation: rotate on refresh, with a grace period for concurrent requests.

6. **Backfill existing records** — Existing bronze rows will have `user_id = NULL`. The silver layer should handle this gracefully (coalesce to `'unknown'` or filter).
