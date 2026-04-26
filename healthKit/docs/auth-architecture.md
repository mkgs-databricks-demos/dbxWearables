# Authentication Architecture

This document describes how the iOS HealthKit app authenticates against the
Databricks AppKit gateway, both in the current short-term design and the
long-term target.

## Goals

1. Never ship hardcoded secrets in the iOS bundle.
2. Keep secrets out of process memory longer than necessary; persist them
   to a secure store (iOS Keychain) and refresh on a regular cadence.
3. Allow the gateway to revoke individual users without rotating shared
   secrets.
4. Keep the iOS-side surface stable across the auth-model change so we
   don't have to rewrite the sync pipeline when we move to JWTs.

## Current model — Service-principal bridge (short-term)

Every iOS device shares a Databricks **service principal** (M2M).
The SPN's `client_id` / `client_secret` are pasted into the app once, then
stored in the iOS Keychain. The app uses them to mint short-lived OAuth
bearer tokens via the workspace's OIDC token endpoint and attaches a token
to every ingest POST.

```
┌────────────────┐  client_credentials  ┌─────────────────────────────┐
│  iOS app       │ ───────────────────► │  Workspace OIDC token       │
│ (Keychain:     │                      │  POST /oidc/v1/token        │
│  client_id +   │ ◄─────────────────── │  → bearer token (1h TTL)    │
│  client_secret)│      access_token    │                             │
└──────┬─────────┘                      └─────────────────────────────┘
       │ Bearer <token>
       ▼
┌─────────────────────────────────────────────────────────────────────┐
│  AppKit gateway: POST /api/v1/healthkit/ingest                      │
│   - validates token via Databricks SDK                              │
│   - forwards NDJSON body + headers to ZeroBus                       │
└─────────────────────────────────────────────────────────────────────┘
```

### Components

| Component | Role |
|-----------|------|
| `KeychainHelper` | Multi-account wrapper around iOS Keychain. Stores `databricksClientID`, `databricksClientSecret`, `oauthAccessToken`, `oauthAccessTokenExpiry` under service `com.dbxwearables.api` with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. |
| `AuthService` (actor) | Implements `AuthProviding`. Reads SPN credentials from Keychain, posts to `<workspace>/oidc/v1/token` with HTTP Basic auth, caches the access token in memory and Keychain, and refreshes ~60s before expiry. |
| `APIService` | Calls `auth.bearerToken()` before every request. On HTTP 401, calls `auth.invalidateCachedToken()` and retries exactly once. |
| `SPNCredentialsView` (DEBUG) | About-tab sheet for pasting client ID + secret into the Keychain. Compiled out of release builds. |

### Configuration

Two environment variables drive the auth flow (set per-scheme in
`project.yml`, never hardcoded):

| Variable | Example | Used for |
|----------|---------|----------|
| `DBX_WORKSPACE_HOST` | `https://fevm-hls-fde.cloud.databricks.com` | OIDC token endpoint base |
| `DBX_API_BASE_URL` | `https://dev-dbxw-0bus-ingest-...aws.databricksapps.com` | Gateway ingest endpoint base |

`DBX_WORKSPACE_HOST` and `DBX_API_BASE_URL` are different hosts on purpose:
the workspace OIDC endpoint lives on the Databricks workspace host, while
the AppKit gateway is deployed to `*.databricksapps.com`.

### Threats this mitigates

- **Bundle inspection** — credentials are never in the bundle; they enter
  via paste-in or (later) a registration flow.
- **In-memory leakage** — bearer token lives in an actor and is bounded
  to ~1h. Lost devices wipe Keychain on factory reset.
- **Token endpoint flakiness** — in-flight token expiry is avoided by
  refreshing 60s before the cached token's `expires_in` deadline.

### Threats this does **not** mitigate

- **Shared SPN blast radius** — every device uses the same SPN, so a
  single leaked credential authenticates as the whole fleet.
- **Per-user revocation** — there's no per-user identity yet, so we
  can't revoke one device without rotating the SPN.
- **Scope creep** — the SPN currently has full ingest privileges. Long
  term it should only be allowed to register users and mint JWTs.

## Long-term model — JWT broker (target)

The SPN no longer authorizes ingest. Instead, the gateway uses it
exclusively to (a) register users and (b) mint short-lived per-user
JWTs.

```
┌────────────────┐  register / refresh   ┌─────────────────────────────┐
│  iOS app       │ ────────────────────► │  Gateway /auth/register     │
│                │ ◄──────────────────── │  /auth/refresh              │
│ (Keychain:     │      device JWT       │   - SPN-authenticated calls │
│  device JWT,   │       (~15min TTL)    │   - writes to Lakebase user │
│  refresh tok)  │                       │     registry                │
└──────┬─────────┘                       └─────────────────────────────┘
       │ Bearer <device JWT>
       ▼
┌─────────────────────────────────────────────────────────────────────┐
│  AppKit gateway: POST /api/v1/healthkit/ingest                      │
│   - validates device JWT (signature + expiry + revocation list)     │
│   - forwards body to ZeroBus tagged with the user's identity        │
└─────────────────────────────────────────────────────────────────────┘
```

### Why Lakebase

The user registry needs:
- Row-level reads/writes per user (not analytical scans).
- Sub-100ms reads on the hot path (every ingest validates a JWT).
- Transactional writes for revocation.

Lakebase (Postgres-compatible) fits all three; storing the registry in a
Delta table on Unity Catalog would force the hot path through a SQL
warehouse cold start.

### Migration plan

The iOS-side abstractions are designed so the migration is mostly a
mechanical swap:

1. **Today:** `AuthService` reads SPN client_id/secret and posts to the
   workspace OIDC token endpoint to get a bearer token.
2. **Future:** A new `JWTAuthService` (also conforming to `AuthProviding`)
   reads a device JWT + refresh token from the Keychain and posts to the
   gateway's `/auth/refresh` endpoint instead.

`APIService` already depends on the protocol, not the concrete type, so
swapping `AuthService` for `JWTAuthService` does not require any change
to the sync pipeline. The 401 → invalidate → retry path also keeps
working: a JWT broker that revokes a user's token causes the next request
to receive a 401, which triggers a refresh just like an expired bearer.

### Scope reduction for the SPN

When the JWT broker ships, the SPN is restricted to:

- `POST /auth/register` (gateway-only, never reachable from a phone)
- `POST /auth/refresh` (gateway-only)
- write access to the Lakebase user registry

It loses ingest privileges entirely; ingest validates the device JWT.

## Operational notes

- **Rotation:** SPN secret rotation requires re-pasting in the debug UI
  for every demo device. Acceptable for the current demo phase; not
  acceptable for the production model, which is one of the reasons we're
  moving to per-user JWTs.
- **Logging:** `AuthService` does **not** log token bodies, client
  secrets, or full Authorization headers. The OIDC error path logs only
  the HTTP status code.
- **Test coverage:** `AuthServiceTests` covers happy path, caching,
  refresh-near-expiry, invalidate-forces-refresh, missing creds, non-2xx
  from token endpoint, malformed JSON. `APIServiceTests` covers the
  401 → invalidate → retry path and persistent-401 surfacing.
