# dbxW_zerobus_infra — Session: Lakebase Resources, Endpoint Conflict, and Data API Investigation

**Date:** 2026-04-17
**Bundle:** `dbxW_zerobus_infra`
**Scope:** Lakebase Autoscaling resource configuration, Terraform deploy fix, Data API architecture discovery, deploy.sh readiness checks, documentation alignment

---

## Problems Encountered

### 1. Terraform endpoint conflict on deploy

```
Error: failed to create postgres_endpoint
  with databricks_postgres_endpoint.wearables_primary

read_write endpoint already exists
```

**Root cause:** When a Lakebase Autoscaling project is created, it auto-provisions a `main` branch and a READ_WRITE endpoint. The bundle declared an explicit `postgres_endpoints` resource for the same branch, attempting to create a second READ_WRITE endpoint — which violates the one-per-branch constraint.

**Fix:** Removed the `postgres_endpoints` resource entirely. Autoscaling limits are now controlled via `default_endpoint_settings` on the `postgres_projects` resource, which configures the auto-created endpoint at project creation time. Per-target overrides (dev: max 2 CU, hls_fde/prod: max 4 CU) moved to target-level `default_endpoint_settings` on the project.

### 2. Data API incorrectly documented as required for AppKit

**Root cause:** Initial assumption was that AppKit's Lakebase plugin connects via the Data API (PostgREST HTTP/REST layer). Investigation revealed this is incorrect.

**Discovery:** Databricks Apps connect to Lakebase via **direct Postgres wire protocol** (port 5432):
- The platform injects `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGSSLMODE` env vars when a `database` resource is configured
- The official Node.js connection examples use `pg.Pool` (node-postgres) with OAuth token rotation
- The `@databricks/lakebase` AppKit plugin wraps this same wire protocol pattern
- The Data API (PostgREST sidecar) is a separate, optional feature for external HTTP/REST consumers

**Impact:** All documentation and deploy.sh messaging had to be corrected — Data API downgraded from "required for AppKit" to "optional, for external REST clients."

### 3. No programmatic way to enable the Data API

The Lakebase Data API can only be enabled via the Lakebase App UI ("Enable Data API" button). There is no REST API endpoint, CLI command, or DAB resource type for it. The `/api/2.0/postgres/` endpoints cover projects, branches, endpoints (compute), and roles — but not the Data API toggle. The `postgres_endpoint.settings` map exists in the DAB schema but its keys are undocumented.

---

## Changes Made

### Lakebase resource file (`resources/wearables.lakebase.yml`)

| Change | Details |
| --- | --- |
| Removed `postgres_endpoints` resource | Auto-created endpoint can't be re-declared; only one READ_WRITE per branch |
| Moved autoscaling to `default_endpoint_settings` | Per-target CU limits now on the project resource |
| Added Connection model header section | Documents that AppKit uses wire protocol (port 5432), not Data API |
| Downgraded Data API to "optional" | Post-deploy step 1 now reads "optional — for external REST clients" |
| Added UC registration step | Post-deploy step 2 for optional Unity Catalog catalog creation |

### deploy.sh

| Change | Details |
| --- | --- |
| Added `LAKEBASE_PROJECT_ID` variable | Resolved from bundle summary `postgres_projects` resources |
| Extended `resolve_infra_vars()` Python block | Extracts `project_id` from `resources.postgres_projects` |
| Added `check_lakebase_status()` function | Verifies project exists, lists endpoints, probes Data API status |
| Integrated into `verify_infra_readiness()` | Runs as section 3 (informational, non-blocking) |
| Renamed function from `check_lakebase_data_api` | Now `check_lakebase_status` — reflects broader scope |
| Removed all "required for AppKit" claims | Data API messaging is purely informational |
| Updated header comments and usage text | Reflects corrected architecture understanding |

### Infra README (`README.md`)

| Change | Details |
| --- | --- |
| Updated resource hierarchy table | Endpoint row shows *(auto-created)* with explanation |
| Added "Post-deploy manual steps" subsection | Data API (optional) and UC registration (optional) |
| Rewrote AppKit integration section | Documents wire protocol connection model, PG* env vars, OAuth token rotation |
| Updated pipeline stages diagram | Reordered: client_secret (step 3, required) before Data API (step 4, optional) |
| Updated readiness gate table | Data API changed from **Warn** to **Info** with "AppKit does not require it" note |
| Updated first deployment instructions | Optional steps moved to end comment |
| Added documentation links | Lakebase Data API, Connect Apps to Lakebase, Register in UC |

### App bundle README (`dbxW_zerobus_app/README.md`)

No changes — grep confirmed no Data API references existed.

---

## Design Decisions

1. **No explicit endpoint resource:** The project auto-creates both the `main` branch and its READ_WRITE endpoint. Declaring them as separate resources causes Terraform conflicts. The branch resource is kept (for `is_protected` and `no_expiry` settings) with a defensive comment noting it may also need removal if the API isn't idempotent for pre-existing branches.

2. **`default_endpoint_settings` for autoscaling:** This is the only declarative mechanism to configure the auto-created endpoint's compute limits. Per-target overrides on the project resource provide environment-appropriate CU ceilings.

3. **Informational (not blocking) Lakebase check:** Since AppKit doesn't need the Data API, the deploy.sh check is purely informational — it confirms the project exists and notes Data API status without failing the deployment.

4. **Data API status detection is best-effort:** The endpoint API response shape for Data API fields is undocumented. The check probes several plausible field locations (`settings.data_api_enabled`, `settings.data_api.enabled`, `data_api_url`) and falls back to "unknown" gracefully.

5. **Lakebase resource coverage is complete for Autoscaling:** The three resource types (`postgres_projects`, `postgres_branches`, `postgres_endpoints`) are the full DAB surface for Lakebase Autoscaling. The remaining Lakebase resources (`database_catalogs`, `database_instances`, `synced_database_tables`) apply to Lakebase Provisioned only.

---

## Lakebase Architecture Reference

```
AppKit Lakebase Plugin
  → pg.Pool (node-postgres, port 5432, OAuth token rotation)
    → Postgres Compute Endpoint (auto-created, autoscaling 0.5–4 CU)
      → databricks_postgres database

Data API (optional, separate layer)
  → PostgREST sidecar (HTTP/REST, Databricks OAuth)
    → authenticator role → pgrst schema → public schema
```

| Layer | Protocol | Required for AppKit? | Enabled by |
| --- | --- | --- | --- |
| Compute endpoint | Postgres wire (5432) | Yes | Auto-created with project |
| Data API | HTTP/REST | No | Manual — Lakebase App UI |
| UC catalog | SQL (via warehouse) | No | Manual — Catalog Explorer |

---

## Files Modified

| File | Action |
| --- | --- |
| `resources/wearables.lakebase.yml` | Modified — removed endpoint resource, added connection model docs |
| `README.md` | Modified — corrected Data API references, added post-deploy steps |
| `../deploy.sh` | Modified — added Lakebase status check, corrected messaging |
| `../dbxW_zerobus_app/README.md` | Checked — no changes needed |
| `fixtures/sessions/2026-04-17_lakebase-resources-and-data-api.md` | Created — this file |
| `fixtures/sessions/INDEX.md` | Updated — added this session entry |
