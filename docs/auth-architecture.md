---
title: Mobile Auth System — Architecture Plan
status: Draft
last_updated: 2026-04-20
owners: [TODO]
related:
  - databricks.yml
  - server/
  - proxy-lambda/
---

# Consolidated Plan: Mobile Auth System, Databricks-First

## Requirements recap

- Mobile app needs JWT-based auth with short-lived access tokens and long-lived refresh tokens
- Mobile users are never Databricks identities (no workspace access, no JIT/consumer)
- Only publicly exposed endpoint is what starts the sign-in flow
- Self-service registration with email verification via deep link into the mobile app
- Signing keys stored in Databricks secret scope
- Lakebase for user data, tokens, audit
- AppKit (Node.js + Express) for the Databricks App; preview-status acknowledged
- Databricks App runs always-on (no scale-to-zero)
- Lambda passes JWTs through; App re-verifies on every call

## Architecture

Three tiers:

1. **Mobile app** — stores refresh token in Keychain/Keystore, access token in memory, deep-link handler for verify/reset URLs
2. **AWS edge (thin, stateless)** — API Gateway HTTP API + a single dumb-proxy Lambda + S3/CloudFront serving domain association files
3. **Databricks** — AppKit app (the actual backend), Lakebase (state), secret scope (keys + SES creds)

All business logic lives in the Databricks App. The Lambda's only jobs are TLS termination on `api.yourdomain.com`, holding the M2M service principal credentials, and forwarding requests.

## AWS edge tier

**API Gateway (HTTP API)** — gives you throttling, WAF hooks, custom domain. Cheaper and simpler than REST API. Route everything under `/auth/*` to the proxy Lambda.

**Proxy Lambda (Node.js 20, arm64)** — near-zero logic:

```
/proxy-lambda/src/
  handler.ts              # ~150 lines total
  lib/
    databricks-oauth.ts   # M2M token fetch, module-scope cache, refresh at 45m
    forward.ts            # signed fetch to Databricks App /api/*
  config.ts               # app URL, SP client_id/secret from env
```

What it does per request:

1. Take the incoming request (method, path, headers, body)
2. Strip hop-by-hop headers; preserve `Authorization` (mobile app's JWT) and request body verbatim
3. Add `Authorization: Bearer <M2M SP token>` for the Databricks platform auth layer
4. Put the mobile app's JWT (if present) into `X-Mobile-Token` so the App can re-verify without collision
5. Forward to the Databricks App's matching `/api/auth/*` route
6. Return the response with status, headers, body intact

No Lakebase connection. No KMS. No SES. No argon2. No JWT signing or verification. Cold starts are essentially just the Node runtime + a single OAuth token fetch on first invoke.

**S3 + CloudFront** on `app.yourdomain.com`:

- `/.well-known/apple-app-site-association` — iOS universal link association
- `/.well-known/assetlinks.json` — Android App Links verification
- `/verify` and `/reset` fallback HTML (optional, for when app isn't installed)

Must be HTTPS, correct content-type, no redirects. Set once, forget.

**WAF rules** on API Gateway:
- Per-IP rate limit on `/auth/register` (e.g. 5/min)
- Per-IP rate limit on `/auth/signin` (e.g. 10/min)
- Per-IP rate limit on `/auth/verify` and `/auth/password/forgot` (e.g. 10/min)
- Global request size cap (e.g. 8KB for auth bodies)

## Databricks App tier (AppKit)

This is your real backend. Express routes, AppKit plugins, Lakebase plugin for pooled pg connections with auto-managed OAuth tokens.

### Endpoints

```
POST   /api/auth/register         email + password → 202 (always), sends verify email
GET    /api/auth/verify           ?token= → consume, mark verified, auto-signin
POST   /api/auth/verify/resend    email → re-send if unverified (rate-limited)
POST   /api/auth/signin           email + password → access + refresh tokens
POST   /api/auth/refresh          refresh_token → rotated access + refresh
POST   /api/auth/signout          revokes refresh token family
POST   /api/auth/password/forgot  email → sends reset email (always 202)
POST   /api/auth/password/reset   reset_token + new_password → revokes all families
GET    /api/.well-known/jwks.json public keys for any downstream verifier
```

Every authenticated endpoint (`/refresh`, `/signout`, and future POST/GET data endpoints) re-verifies the JWT from `X-Mobile-Token` against cached JWKS on every call. Defense in depth: even if Lambda is compromised, a forged JWT won't pass App-side verification.

### Code layout

```
/databricks-app/
  databricks.yml                  # asset bundle config
  app.yaml                        # Databricks Apps manifest
  package.json
  server/
    index.ts                      # AppKit bootstrap
    plugins/
      lakebase.ts                 # @databricks/lakebase pool
    middleware/
      jwt-verify.ts               # re-verifies X-Mobile-Token on protected routes
      request-context.ts          # ip, user-agent, request id
      rate-limit-account.ts       # per-email lockout (Lakebase-backed)
    routes/
      register.ts
      verify.ts                   # GET verify + POST verify/resend
      signin.ts
      refresh.ts
      signout.ts
      password.ts                 # forgot + reset
      jwks.ts
    services/
      jwt-signer.ts               # reads PEM from secret scope on boot, signs locally
      jwt-verifier.ts             # caches public keys, verifies X-Mobile-Token
      passwords.ts                # @node-rs/argon2
      email-tokens.ts             # generate, hash, consume
      refresh-tokens.ts           # issue, rotate, family-revoke
      mailer.ts                   # SES via AWS SDK
      secrets.ts                  # reads secret scope once at boot
      audit.ts
    db/
      schema.ts                   # Drizzle
      migrations/
    config.ts
  client/                         # React admin UI (optional, internal only)
```

### Lakebase schema

```sql
users (
  id uuid pk default gen_random_uuid(),
  email citext unique not null,
  password_hash text not null,
  status text not null default 'active',     -- active, bounced, complained, disabled
  email_verified bool not null default false,
  email_verified_at timestamptz,
  failed_attempts int not null default 0,
  locked_until timestamptz,
  created_at, updated_at timestamptz
);

refresh_tokens (
  id uuid pk default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  family_id uuid not null,
  token_hash bytea not null,
  issued_at, expires_at timestamptz,
  revoked_at timestamptz,
  replaced_by uuid references refresh_tokens(id),
  ip inet, user_agent text
);
create index on refresh_tokens (token_hash);
create index on refresh_tokens (family_id) where revoked_at is null;

email_tokens (
  id uuid pk default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  purpose text not null check (purpose in ('verify_email','password_reset')),
  token_hash bytea not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  ip inet, user_agent text
);
create unique index on email_tokens (token_hash);
create index on email_tokens (user_id, purpose) where consumed_at is null;

signing_keys (
  kid text pk,
  alg text not null,                         -- RS256 or ES256
  public_pem text not null,                  -- JWKS source of truth
  active bool not null default true,         -- the kid currently used for signing
  created_at timestamptz not null default now(),
  retired_at timestamptz
);

auth_events (
  id bigserial pk,
  user_id uuid,
  event_type text not null,
  ip inet, user_agent text,
  ts timestamptz not null default now(),
  detail jsonb
);
```

### Databricks secret scope layout

Scope: `mobile-auth`

```
signing-active-kid        → "2026-04-k1"
signing-key-2026-04-k1    → base64(PEM private)
signing-key-2026-01-k0    → base64(PEM private)  (previous, kept for verify)
ses-access-key-id         → AWS key for SES SendEmail
ses-secret-access-key     → AWS secret for SES SendEmail
ses-from-address          → "noreply@yourapp.com"
verify-base-url           → "https://app.yourdomain.com"
```

The App reads these once at boot into module-scope cache. No Lambda access. Rotation is a four-step runbook: write new private key, insert `signing_keys` row with public PEM, flip `signing-active-kid`, delete old private after access-token-TTL × 2.

### JWT design

- **Algorithm**: RS256 or ES256
- **Header**: `kid` matching a `signing_keys` row
- **Access token**: 15-minute TTL, claims `sub` (user_id), `iat`, `exp`, `jti`, `iss`, `aud`
- **Refresh token**: opaque 32-byte random, base64url, stored SHA-256 hashed in Lakebase, 30-day TTL, rotated on every use with family tracking

Re-verification path (`middleware/jwt-verify.ts`):
- Read `X-Mobile-Token` header
- Look up `kid` in in-memory JWKS cache (loaded from `signing_keys` at boot, refreshed every 5 min)
- Verify signature, `exp`, `iss`, `aud`
- Attach `userId` to request context for handlers

## Auth flows

### Registration

1. Mobile → `POST /auth/register {email, password}` to API Gateway
2. Lambda forwards to App `/api/auth/register` with M2M token
3. App: begin transaction, lock user row by email, branch:
   - No row: insert user (argon2id hash), issue verify token
   - Unverified row: update password, issue new verify token (max 3/hr per user)
   - Verified row: silent no-op (anti-enumeration)
4. Commit, then send SES email with deep link `https://app.yourdomain.com/verify?token=…`
5. Constant-time response: 202 with generic message, padded to a floor delay

### Verification (deep link)

1. User taps link → OS opens mobile app via App Links / Universal Links
2. Mobile app extracts `token`, calls `GET /auth/verify?token=…`
3. Lambda forwards, App consumes token atomically (`FOR UPDATE`, check purpose + expiry + unused, mark consumed)
4. Mark `email_verified = true`, issue access + refresh pair in same transaction, audit-log
5. Return tokens; mobile app stores them and enters signed-in state

### Sign-in

1. Mobile → `POST /auth/signin {email, password}`
2. App: check `locked_until`, argon2id verify, increment or reset `failed_attempts`
3. If `email_verified = false`: return 403 `email_not_verified` (distinct from 401 bad credentials)
4. Issue access + refresh, audit-log

### Refresh

1. Mobile → `POST /auth/refresh {refresh_token}` with `X-Mobile-Token: <access_token>` (may be expired; still useful for context)
2. App hashes the refresh token, locks the row:
   - Not found: 401
   - `revoked_at` set: **reuse detected** — revoke entire `family_id`, log `reuse_detected`, return 401
   - Expired: 401
   - Valid: mark this token revoked, insert new token in same family, return new access + refresh pair

### Sign-out

1. Mobile → `POST /auth/signout` with refresh token
2. App revokes the token's entire family, audit-logs

### Password reset

1. `POST /auth/password/forgot {email}` → always 202, sends reset email if account exists (rate-limited, constant-time)
2. Email deep-links to `/reset?token=…` → mobile app collects new password → `POST /auth/password/reset {token, new_password}`
3. App consumes token, updates hash, **revokes every refresh family for the user**, audit-logs

## Cross-cutting behaviors

**Constant-time responses** on `register`, `signin`, `verify/resend`, `password/forgot` — floor delay (e.g. 250ms) to mask branching in response time. Prevents user enumeration and timing attacks on password hash comparison.

**Generic public-facing errors** — internal errors get distinct codes in logs; external errors collapse to `invalid_request`, `invalid_credentials`, `invalid_token`, `rate_limited`, `internal_error`.

**Per-account lockout** — 5 consecutive failed signins → lock 15 min (`locked_until`). Middleware checks before password verify so hashing isn't wasted on locked accounts.

**SES bounce/complaint handling** — SNS topic → small handler (can be inside the Databricks App as a separate route hit by SNS HTTPS subscription) → marks `users.status` to suppress future sends. Important for deliverability.

**Key rotation runbook**:
1. Generate new RSA-2048 keypair offline
2. Write new private to `signing-key-<new-kid>` in secret scope
3. Insert `signing_keys` row with new kid and public PEM, `active=false`
4. Update `signing-active-kid` to new kid
5. Set old row `active=false`, new row `active=true`; App picks up on next 5-min refresh
6. After access-token-TTL × 2 has elapsed, delete old private key from secret scope
7. Keep old public PEM in `signing_keys` until `retired_at + 2 × access-token-TTL`, then remove

**JWKS serving** — `GET /api/.well-known/jwks.json` returns all non-retired public keys with `Cache-Control: public, max-age=300`. Mobile app doesn't consume this; it's for any future verifier (e.g., another Databricks App).

## Mobile app responsibilities

- Refresh token: iOS Keychain / Android Keystore with biometric gate
- Access token: in-memory only, cleared on backgrounding after N minutes
- On 401 from any endpoint: attempt one refresh, then redirect to signin on failure
- Deep link handlers for `/verify` and `/reset` — extract token, POST to backend
- TLS pinning on `api.yourdomain.com` (pin the CloudFront/ACM cert chain, update on rotation)
- Show distinct UX for `email_not_verified` (offer resend) vs. `invalid_credentials`

## Deep linking specifics

- **Universal/App Links only** — no custom schemes (hijackable)
- **iOS**: `apple-app-site-association` on `app.yourdomain.com`, with `/verify` and `/reset` path patterns
- **Android**: `assetlinks.json` with both upload cert and Play App Signing cert SHA-256 fingerprints
- **Fallback**: if app isn't installed, static page on same domain pointing to store listings

## What lives where — final map

| Concern | Location |
|---|---|
| TLS termination for mobile | API Gateway + ACM |
| Public endpoint surface | Proxy Lambda |
| WAF / per-IP rate limiting | API Gateway + WAF |
| SP credential for Databricks App access | Lambda env (from Secrets Manager) |
| Domain association files | S3 + CloudFront |
| All business logic | Databricks App (AppKit/Express) |
| Users, tokens, audit, public keys | Lakebase |
| Signing private keys, SES creds, config | Databricks secret scope |
| Password hashing | Databricks App |
| JWT sign + re-verify | Databricks App |
| Email sending | Databricks App → SES |
| Per-account lockout state | Lakebase |

Only six AWS-side things: API Gateway, Lambda, S3, CloudFront, ACM, SES. Five of those are pure infrastructure; only the Lambda has code, and it's ~150 lines with no business logic.

## Preview/risk callouts

- **AppKit is preview.** Databricks ships it with a "do not use in production" banner as of this planning window. Factor this into your launch criteria. If you need production-readiness before AppKit GAs, plain Express on Databricks Apps is a safe fallback; you lose the Lakebase plugin's token auto-refresh but can replicate it in ~40 lines.
- **Lakebase Postgres** is GA, but the private-link variant for isolating the DB endpoint is still preview. Not blocking since you're connecting App-to-Lakebase inside Databricks' network, but worth knowing if compliance later demands no-public-endpoint for the DB.
- **Databricks App always-on compute** — confirm your pricing/capacity for this; it changes the cost profile from serverless-idle to reserved.

## Open decisions before implementation

1. **Email provider** — SES assumed; if you have a preferred transactional sender (Postmark, Resend, SendGrid) the swap is one service file
2. **Refresh TTL** — 30 days default; adjust per your session-lifetime risk tolerance
3. **Access TTL** — 15 min default; shorter = more refresh traffic, longer = larger blast radius on leak
4. **Verify link TTL** — 24 hours default
5. **Reset link TTL** — 30 minutes default
6. **Universal link fallback page** — build or skip for v1

## Next steps (suggested order)

1. Lambda proxy spec (detailed)
2. App-side handler designs for each route
3. JWT sign/verify module design
4. Terraform + asset-bundle deployment plan
