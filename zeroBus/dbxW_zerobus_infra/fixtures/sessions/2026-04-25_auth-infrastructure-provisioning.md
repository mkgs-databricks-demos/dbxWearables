## Session: Auth Infrastructure — iOS SPN, JWT Secret, Apple Bundle ID Provisioning

**Date:** 2026-04-25
**Bundle:** `dbxW_zerobus_infra`

### Summary

Extended the infra bundle to auto-provision three new auth secrets and create a second service principal for iOS bootstrap authentication. The UC setup job now creates both the ZeroBus SPN (data ingestion) and the iOS Bootstrap SPN (mobile auth), generates the JWT signing secret on first run, and stores the Apple bundle ID — all in the shared secret scope. The deploy.sh readiness gate now verifies 8 keys (up from 5).

This work supports the JWT Authentication (Phase 1) and security hardening implemented in the companion `dbxW_zerobus_app` bundle during the same session.

---

### Problem

The app bundle's Phase 1 auth implementation requires three new secrets in the shared scope:

| Secret | Purpose | App Env Var |
| --- | --- | --- |
| `jwt_signing_secret` | HS256 key for app-issued JWTs | `JWT_SIGNING_SECRET` |
| `apple_bundle_id` | iOS app bundle ID for Apple token `aud` validation | `APPLE_BUNDLE_ID` |
| `ios_spn_application_id` | iOS Bootstrap SPN identity for route guard | `IOS_SPN_APPLICATION_ID` |

The app bundle already declared the resource definitions (secret scope references in `zerobus_ingest.app.yml`) and environment variable mappings (`app.yaml`), but the actual values did not exist in the scope. These needed to be provisioned by the infra bundle, following the existing pattern where the UC setup job auto-provisions ZeroBus credentials.

Additionally, the iOS app needs a dedicated service principal with minimal permissions (`CAN_USE` only) to reach auth endpoints before the user signs in with Apple. This SPN follows the same find-or-create pattern as the existing ZeroBus SPN.

---

### Changes

#### `databricks.yml` — 4 new variables

Added after the `zerobus_stream_pool_size` block, with a comment section explaining the auth key conventions:

| Variable | Default | Purpose |
| --- | --- | --- |
| `jwt_signing_secret_key` | `jwt_signing_secret` | Scope key name for the JWT signing secret |
| `apple_bundle_id` | `com.dbxwearables.healthKit` | The actual Apple bundle ID value (not a key name) |
| `apple_bundle_id_key` | `apple_bundle_id` | Scope key name for the bundle ID |
| `ios_spn_application_id_key` | `ios_spn_application_id` | Scope key name for the iOS SPN's application_id |

**Design decision:** Auth keys are NOT schema-qualified (unlike `client_id_dbs_key` / `client_secret_dbs_key`). These are per-app, not per-schema — all developers sharing a scope need the same JWT secret and iOS SPN identity.

#### `resources/uc_setup.job.yml` — 4 new job parameters

Added 4 parameters matching the new variables, passed to the `ensure-service-principal` notebook via `dbutils.widgets.get()`. Updated the job description to mention both SPNs and auth secrets.

#### `src/uc_setup/ensure-service-principal` (notebook, 8 → 9 cells)

**Cell 0 (markdown):** Updated title to "Ensure ZeroBus & iOS Bootstrap Service Principals". Added auth keys to the auto-provisioned table (3 new rows), added iOS SPN admin steps table, updated admin action notes to cover both SPNs.

**Cell 2 (params):** Added 4 new `dbutils.widgets.get()` calls for the auth parameters.

**Cell 4 (NEW):** Find-or-create iOS Bootstrap SPN. Same pattern as cell 3 (ZeroBus SPN): search by display name `dbxw-ios-bootstrap-{schema}`, create if missing, capture `ios_spn_application_id`.

**Cell 5 (secrets):** Three additions:
1. `apple_bundle_id` and `ios_spn_application_id` added to the `secrets_to_store` dict (refreshed on every run).
2. **JWT signing secret generation** — conditional: only generates on first run if the key doesn't exist in the scope. Uses `secrets.token_urlsafe(32)`. Preserving existing keys prevents invalidating all outstanding JWTs on re-run.
3. Updated `existing_keys` check and print statements to include all auth keys.

**Cell 6 (ACL):** Added explicit comment that iOS SPN does NOT receive scope READ — it authenticates via AppKit's proxy (OAuth M2M), not by reading secrets directly. Granting scope READ would violate least-privilege.

**Cell 7 (task values):** Now outputs `ios_spn_application_id` in addition to the existing `spn_application_id`.

**Cell 8 (summary):** Restructured into sections: ZeroBus SPN, iOS Bootstrap SPN, Secret Scope (with all 9 keys), Derived Values. Includes conditional admin action reminders for missing `client_secret` and newly-created iOS SPN.

#### `deploy.sh` — readiness gate expanded

**`build_key_arrays()`:** Added `jwt_signing_secret`, `apple_bundle_id`, `ios_spn_application_id` to `AUTO_PROVISIONED_KEYS`. Array now contains 7 auto-provisioned + 1 admin-provisioned = 8 total required keys.

**Header comment:** Updated "all 5 must be present" → "all 8 must be present" with the auth keys listed.

**Function comment:** Added note about auth keys using fixed names (not schema-qualified).

#### `README.md` — 8 sections updated

1. **What This Bundle Manages table:** Added iOS Bootstrap SPN row
2. **UC Setup Job section:** Updated task description to mention both SPNs and auth secrets
3. **Secret Scope Contents — auto-provisioned table:** Added 3 new rows (JWT, Apple, iOS SPN)
4. **Secret Scope Contents — admin-provisioned section:** Added iOS SPN admin steps table (generate OAuth secret, grant CAN_USE, embed in iOS binary)
5. **Admin action required note:** Expanded to cover both ZeroBus SPN client_secret and iOS SPN provisioning
6. **Pipeline stages diagram:** Added 3 new readiness gate checks for auth keys
7. **Readiness gate checks table:** Updated auto-provisioned key list
8. **Quick Start:** Added "Provision the iOS Bootstrap SPN" section with step-by-step instructions

---

### Design Decisions

| Decision | Rationale |
| --- | --- |
| Auth keys NOT schema-qualified | Per-app, not per-schema — JWT secret must be consistent across all app instances |
| JWT secret generated only on first run | Regenerating on re-run would invalidate all outstanding access tokens (15 min TTL) |
| `secrets.token_urlsafe(32)` for JWT secret | 256-bit entropy, URL-safe characters, stdlib — no external deps |
| iOS SPN does NOT get scope READ | Least-privilege: it authenticates via AppKit proxy, not by reading secrets |
| iOS SPN OAuth secret NOT in scope | Embedded in iOS binary, not needed by the server — scope stores only `application_id` for route guard verification |
| `apple_bundle_id` is both a variable (value) and scope key | The variable holds the actual value (`com.dbxwearables.healthKit`); `apple_bundle_id_key` names the scope key. This lets the value change per-target if needed. |

---

### Cross-Bundle Alignment

The infra bundle's new variables and scope keys align with the app bundle's existing declarations:

| Infra Variable | Infra Default | App Variable | App Default | Scope Key |
| --- | --- | --- | --- | --- |
| `jwt_signing_secret_key` | `jwt_signing_secret` | `jwt_signing_secret_key` | `jwt_signing_secret` | `jwt_signing_secret` |
| `apple_bundle_id_key` | `apple_bundle_id` | `apple_bundle_id_key` | `apple_bundle_id` | `apple_bundle_id` |
| `ios_spn_application_id_key` | `ios_spn_application_id` | `ios_spn_application_id_key` | `ios_spn_application_id` | `ios_spn_application_id` |

---

### Admin Steps After First UC Setup Job Run

After the UC setup job runs for the first time with auth provisioning:

1. **ZeroBus SPN** (`dbxw-zerobus-{schema}`): Generate OAuth secret → store as `{client_secret_dbs_key}` in scope *(existing step, unchanged)*
2. **iOS Bootstrap SPN** (`dbxw-ios-bootstrap-{schema}`):
   - Generate OAuth secret (Workspace UI or CLI)
   - Grant `CAN_USE` on the Databricks App (after app bundle deploy)
   - Embed `client_id` + `client_secret` in the iOS app binary
3. **JWT signing secret**: Auto-provisioned — no action needed
4. **Apple bundle ID**: Auto-provisioned from variable — no action needed

---

### Files Modified Summary

| File | Change Type | Purpose |
| --- | --- | --- |
| `databricks.yml` | Modified | 4 new auth variables |
| `resources/uc_setup.job.yml` | Modified | 4 new job parameters, updated description |
| `src/uc_setup/ensure-service-principal` | Modified (8→9 cells) | iOS SPN creation, JWT secret gen, auth secret storage |
| `README.md` | Modified (8 sections) | Auth infrastructure documentation |
| `../deploy.sh` | Modified | Readiness gate: 5→8 required keys |

### Validation

- All YAML files parse cleanly (`yaml.safe_load`)
- Variables, job params, and notebook cell structure verified programmatically
- Full `databricks bundle validate --strict` should be run from the infra bundle directory
