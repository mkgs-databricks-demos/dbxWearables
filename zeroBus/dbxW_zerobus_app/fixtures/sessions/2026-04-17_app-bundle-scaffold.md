# dbxW_zerobus_app — Session Summary

## Session: App Bundle Scaffold & AppKit Resource Definition

**Date:** 2026-04-17
**Branch:** `mg-main-zerobus-app`
**Commits:** `ff59430`, `80379fe`, `bea10f2`, `1e8b6e0`, `361d869`

---

### What Was Built

The `dbxW_zerobus_app` application bundle was scaffolded from scratch alongside the companion `dbxW_zerobus_infra` infrastructure bundle. This bundle owns the runtime layer — the AppKit app, ZeroBus consumer, and (future) Spark Declarative Pipelines.

---

### Changes Made

#### 1. Bundle Initialization (`ff59430`)

Created the bundle skeleton:
- `databricks.yml` — bundle config with variables, three targets (`dev`, `hls_fde`, `prod`)
- `README.md` — comprehensive documentation of the bundle's purpose, relationship to infra, variables, targets, and deployment commands
- `.gitignore` — excludes `.databricks/` state directory
- `resources/` directory for resource YAML definitions

The `databricks.yml` mirrors the infra bundle's target structure (same workspace hosts, root paths, presets, permissions) and maintains its own copies of shared variables (`catalog`, `schema`, `secret_scope_name`) since DAB does not support cross-bundle resource substitutions.

#### 2. Target Configuration (`80379fe`)

Refined per-target variable assignments:
- `dev` — `hls_fde_dev` catalog, `dev_matthew_giglia_wearables` schema, user identity
- `hls_fde` — `hls_fde` catalog, `wearables` schema, service principal identity
- `prod` — placeholder (same workspace, TBD catalog/schema)

Added preset tags (project, businessUnit, developer, requestedBy, RemoveAfter) applied to all deployed resources via DAB presets.

#### 3. Schema-Qualified Secret Keys (`bea10f2`)

**Problem:** Multiple targets (dev and hls_fde) share the same workspace and secret scope. If both use bare `client_id` / `client_secret` keys, they collide.

**Solution:** Overrode `client_id_dbs_key` and `client_secret_dbs_key` per target to schema-qualified names:
- `client_id_${var.schema}` → e.g., `client_id_wearables`
- `client_secret_${var.schema}` → e.g., `client_secret_wearables`

This enables a single secret scope to hold credentials for multiple schemas without key collisions.

#### 4. ZeroBus Ingest App Resource (`1e8b6e0`)

Created `resources/zerobus_ingest.app.yml` — the AppKit app definition:

| Property | Value |
| --- | --- |
| Name | `dbxw-zerobus-ingest-${var.schema}` |
| Source code | `../src/app` (not yet created) |
| Stack | TypeScript/Node.js (AppKit + Express + React + Vite) |
| Ingest SDK | `@databricks/zerobus-ingest-sdk` (TypeScript, Rust-backed) |

**App resources** (5 secrets from the infra bundle's scope):
- `zerobus-client-id` — SPN application_id for ZeroBus auth
- `zerobus-client-secret` — SPN OAuth secret
- `zerobus-workspace-url` — Databricks workspace URL
- `zerobus-endpoint` — ZeroBus Ingest server endpoint
- `zerobus-target-table` — Fully qualified bronze table name

Each secret resource is available in `app.yaml` via `valueFrom:` directives, mapped to environment variables that the AppKit server reads at startup.

**Per-target permissions:**
- `dev` — user CAN_MANAGE only
- `hls_fde` — user + SP CAN_MANAGE, users group CAN_USE
- `prod` — user CAN_MANAGE only

#### 5. Notebook Cleanup (`361d869`)

Removed stray `%sql` magic command from the session fixture notebook.

---

### Design Decisions

#### Cross-Bundle Variable Convention

DAB does not support `${resources.*}` references across bundles. The app bundle maintains its own `catalog`, `schema`, and `secret_scope_name` variables with per-target values that **must match** the infra bundle. The README documents this contract and the shared `deploy.sh` enforces deployment order.

#### Secret Scope as the Cross-Bundle Bridge

The app's auto-provisioned service principal reads ZeroBus SPN credentials from the infra bundle's secret scope via `valueFrom:` in `app.yaml`. This is the primary cross-bundle integration point — no hardcoded credentials, no cross-bundle resource refs.

#### AppKit Stack Choice (TypeScript/Node.js)

The ZeroBus Ingest SDK is TypeScript-native (`@databricks/zerobus-ingest-sdk`, Rust-backed via NAPI). AppKit's `@databricks/appkit` framework provides Express + React + Vite scaffolding. The app receives HealthKit JSON POSTs through a custom Express route and streams payload + HTTP headers to the bronze table via the SDK.

#### Source Code Not Yet Created

`src/app/` does not exist yet — the next step is `databricks apps init` to scaffold the AppKit project, then wire in the ZeroBus SDK and custom Express routes. The resource YAML is defined first to validate the bundle structure and permissions.

---

### Files Created / Modified

| File | Status | Description |
| --- | --- | --- |
| `databricks.yml` | Created | Bundle configuration — variables, 3 targets, includes |
| `README.md` | Created | Full documentation — architecture, variables, targets, deployment |
| `.gitignore` | Created | Excludes `.databricks/` |
| `resources/zerobus_ingest.app.yml` | Created | AppKit app resource — 5 secret resources, per-target permissions |
| `fixtures/AppKit App Bundle Setup Session.ipynb` | Created | Interactive session notebook (exploratory) |

### Bundle Structure (Current State)

```
dbxW_zerobus_app/
├── databricks.yml                          # Bundle config
├── README.md                               # Documentation
├── .gitignore                              # .databricks/ excluded
├── resources/
│   └── zerobus_ingest.app.yml              # AppKit app definition
├── fixtures/
│   ├── sessions/                           # Session summaries (this file)
│   │   ├── INDEX.md
│   │   └── 2026-04-17_app-bundle-scaffold.md
│   └── AppKit App Bundle Setup Session.ipynb
└── src/                                    # (not yet created)
    └── app/                                # AppKit source — next step: `databricks apps init`
```

### Next Steps

1. **Bootstrap AppKit app** — `databricks apps init` in `src/app/` to scaffold the TypeScript/Node.js project
2. **Configure `app.yaml`** — map the 5 secret resources to environment variables via `valueFrom:`
3. **Add Lakebase database resource** — reference the `production` branch for app-side Postgres access
4. **Wire ZeroBus SDK** — custom Express route to receive HealthKit POSTs and stream to bronze table
5. **Define Spark Declarative Pipeline** — `resources/*.pipeline.yml` for silver/gold processing
