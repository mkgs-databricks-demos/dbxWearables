# dbxW_zerobus_app — Session Summary

## Session: AppKit Gateway Migration into Bundle Structure

**Date:** 2026-04-17
**Branch:** `mg-appkit`
**Commits:** `308f500`, `e2f5f7f`

---

### Context

The AppKit CLI (`databricks apps init`) scaffolded a standalone project at
`wearables-0bus-gateway/` inside the app bundle directory. This created a
second `databricks.yml` with its own single-target config, duplicating and
conflicting with the authoritative `dbxW_zerobus_app/databricks.yml` (3
targets, shared variables, cross-bundle contract with infra). This session
migrated the gateway's source code and config into the canonical bundle
structure and reconciled the two sets of resource definitions.

---

### Problems Encountered

#### 1. Dual databricks.yml Conflict

**Symptom:** Two `databricks.yml` files in the app bundle tree — the
bundle's authoritative config at the root, and the CLI-generated one inside
`wearables-0bus-gateway/`.

**Root cause:** `databricks apps init` creates a self-contained project
with its own bundle config. It doesn't know about existing DAB structure.

**Fix:** Dropped the gateway's `databricks.yml` entirely. Merged its
unique content (Lakebase postgres resource, variables) into the existing
bundle config.

#### 2. Resource Definition Divergence

**Symptom:** The two configs declared different app resources with no
overlap:
- App bundle: 5 secret scope resources (ZeroBus credentials)
- Gateway: 1 postgres resource (Lakebase)

Both were needed — they serve different purposes (ZeroBus ingest SDK vs.
Lakebase operational database).

**Fix:** Added the gateway's postgres resource as the 6th resource in
`zerobus_ingest.app.yml`, alongside the existing 5 secrets.

#### 3. Incomplete app.yaml Env Bindings

**Symptom:** The gateway's `app.yaml` only mapped `LAKEBASE_ENDPOINT`
from the postgres resource. The 5 ZeroBus secret resources had no
`valueFrom` bindings, so the app would have no access to ZeroBus
credentials at runtime.

**Fix:** Added all 5 ZeroBus `valueFrom` mappings to `app.yaml`:
`ZEROBUS_CLIENT_ID`, `ZEROBUS_CLIENT_SECRET`, `ZEROBUS_WORKSPACE_URL`,
`ZEROBUS_ENDPOINT`, `ZEROBUS_TARGET_TABLE`.

---

### Migration Plan Executed

#### Step 1: File Moves (`308f500`)

All runtime files moved via `git mv` (40 renames, 100% match — full
history preserved):

| Source (gateway) | Destination |
| --- | --- |
| `wearables-0bus-gateway/server/` | `src/app/server/` |
| `wearables-0bus-gateway/client/` | `src/app/client/` |
| `wearables-0bus-gateway/tests/` | `src/app/tests/` |
| `wearables-0bus-gateway/app.yaml` | `src/app/app.yaml` |
| `wearables-0bus-gateway/appkit.plugins.json` | `src/app/appkit.plugins.json` |
| `wearables-0bus-gateway/package.json` | `src/app/package.json` |
| `wearables-0bus-gateway/package-lock.json` | `src/app/package-lock.json` |
| `wearables-0bus-gateway/tsconfig.*` | `src/app/tsconfig.*` |
| `wearables-0bus-gateway/*.config.*` | `src/app/*.config.*` |
| `wearables-0bus-gateway/.*` (dotfiles) | `src/app/.*` |

Dropped (superseded by app bundle):
- `wearables-0bus-gateway/databricks.yml`
- `wearables-0bus-gateway/README.md`

#### Step 2: Config Merges (`308f500`)

| File | What Was Merged |
| --- | --- |
| `databricks.yml` | Added `postgres_branch` and `postgres_database` variables with per-target values (dev, hls_fde) |
| `resources/zerobus_ingest.app.yml` | Added Lakebase `postgres` resource (6th resource, `CAN_CONNECT_AND_CREATE`) |
| `src/app/app.yaml` | Added 5 ZeroBus `valueFrom` env bindings alongside `LAKEBASE_ENDPOINT` |
| `.gitignore` | Added AppKit build artifact patterns scoped under `src/app/` |

#### Step 3: README Update (`e2f5f7f`)

Rewrote `README.md` to reflect the migrated structure:
- Added AppKit Application section with architecture diagram
- Added plugin table (lakebase, server, analytics, files, genie)
- Added 6-resource env var mapping table
- Added Lakebase Postgres variables section with CLI lookup commands
- Added Development section with npm commands
- Updated bundle structure tree to show full `src/app/` contents
- Updated data flow diagram to show dual path (ZeroBus + Lakebase)

---

### Key Lakebase Resource IDs

From the gateway's `databricks.yml` (now in app bundle variables):

| Variable | Value |
| --- | --- |
| `postgres_branch` | `projects/dbxw-zerobus-wearables/branches/production` |
| `postgres_database` | `projects/dbxw-zerobus-wearables/branches/production/databases/db-0k31-aj7nvq8pgr` |

---

### AppKit Stack Summary

From the gateway scaffold (now at `src/app/`):

| Component | Technology | Version |
| --- | --- | --- |
| Backend | `@databricks/appkit` (Express) | 0.20.3 |
| Frontend | `@databricks/appkit-ui` (React + Vite + Tailwind) | 0.20.3 |
| Databricks SDK | `@databricks/sdk-experimental` | ^0.14.2 |
| TypeScript | `typescript` | ~5.9.3 |
| Build (server) | `tsdown` | ^0.20.3 |
| Build (client) | `vite` (rolldown-vite) | 7.1.14 |
| Test (unit) | `vitest` | ^4.0.14 |
| Test (E2E) | `@playwright/test` | ^1.57.0 |

Plugins enabled: `server` (required), `lakebase` (required), `analytics`,
`files`, `genie` (optional).

---

### Design Decisions

#### source_code_path Alignment

The existing `zerobus_ingest.app.yml` already declared
`source_code_path: ../src/app`. The migration placed the gateway source
at exactly that path, so no resource YAML change was needed for the path.

#### App Name Preserved

Kept `dbxw-zerobus-ingest-${var.schema}` (schema-qualified, consistent
with infra bundle naming convention) rather than the gateway's
`wearables-0bus-gateway` (CLI default).

#### Dual Resource Types in One App

The app now has both **secret scope** resources (for ZeroBus SDK
credentials) and a **postgres** resource (for Lakebase). These serve
different integration paths:
- ZeroBus: streaming ingest to bronze table via `@databricks/zerobus-ingest-sdk`
- Lakebase: direct Postgres for app state via AppKit `lakebase` plugin

#### Git History Preserved

Used `git mv` for all file moves. Git detected all 40 files as renames
(100% content match), preserving full blame/log history.

---

### Files Modified

| File | Lines Changed | Description |
| --- | --- | --- |
| `databricks.yml` | +16 | `postgres_branch`, `postgres_database` vars + per-target values |
| `resources/zerobus_ingest.app.yml` | +10 | Postgres resource, updated architecture comment |
| `src/app/app.yaml` | +24 / -2 | Full rewrite with 6 env bindings + documentation header |
| `.gitignore` | +10 / -1 | AppKit build artifact patterns |
| `README.md` | +146 / -34 | Full rewrite for migrated structure |
| 40 files | renamed | `wearables-0bus-gateway/` → `src/app/` |
| 3 files | deleted | Gateway's `databricks.yml`, `README.md`, `app.yaml` (replaced) |

### Next Steps

1. **Deploy the app bundle** — `databricks bundle deploy --target dev` to create the Databricks App
2. **Install npm dependencies** — `cd src/app && npm install` (may need to run in web terminal)
3. **Replace sample todo routes** — swap `server/routes/lakebase/todo-routes.ts` with ZeroBus ingest routes
4. **Wire ZeroBus SDK** — add `@databricks/zerobus-ingest-sdk` to package.json, create ingest Express route
5. **Define Spark Declarative Pipeline** — `resources/*.pipeline.yml` for silver/gold processing
