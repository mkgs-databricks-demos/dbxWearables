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

**Score: 14/18 PASS, 3 PARTIAL, 1 FAIL**

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
| 18 | Generic error messages | PARTIAL (some leak validation details) |

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

---

### Files Modified

| File | Changes | Lines |
| --- | --- | --- |
| `server/services/auth-service.ts` | Nonce verification in `validateAppleToken()`, `real_user_status` in `AppleTokenPayload` + return, updated JSDoc | 569 → 604 |
| `server/routes/auth/auth-routes.ts` | Shared `handleAppleExchange` handler, `/apple/exchange` alias, camelCase field normalization, nonce passthrough, userId cross-check, dual-convention response | 230 → 326 |

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

#### P1 — Should Fix (deferred to next session)

| # | Task | Files |
| --- | --- | --- |
| 7 | Sanitize error messages (generic client, detailed server logs) | `auth-routes.ts` |
| 8 | Structured JSON auth logging (hashed identifiers for OTel) | `auth-routes.ts`, `auth-service.ts` |

#### P2 — Nice to Have

| # | Task | Files |
| --- | --- | --- |
| 9 | Explicit request timeouts (10s on /apple, 5s on /refresh, /revoke) | `auth-routes.ts` |

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
