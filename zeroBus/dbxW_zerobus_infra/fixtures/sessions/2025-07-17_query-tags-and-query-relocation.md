# dbxW_zerobus_infra

## Session: Query Tags, Predictive Optimization Query Fixes, and Query Relocation

**Date:** 2025-07-17

---

### Summary

Added `SET QUERY_TAGS` session-level observability to both the DDL notebook and the SQL editor query. Reviewed and corrected the "Enable Predictive Optimization" query — uncommented Step 2, replaced `IDENTIFIER()` with `EXECUTE IMMEDIATE` for `ALTER SCHEMA` (syntax limitation), and added a proper Step 3 verification statement. Relocated the SQL editor query from the home directory root to the bundle's `fixtures/examples/queries/` path. Updated all references (README, notebook) to point to the new query UUID.

---

### Problems Encountered

#### 1. `IDENTIFIER()` not supported in `ALTER SCHEMA` position

The SQL editor flagged a syntax error on `ALTER SCHEMA IDENTIFIER(...) ENABLE PREDICTIVE OPTIMIZATION`. The Databricks docs confirm the syntax `ALTER SCHEMA schema_name { ENABLE | DISABLE | INHERIT } PREDICTIVE OPTIMIZATION` is correct, but `IDENTIFIER()` is not accepted as a substitute for the literal schema name in this position.

**Root cause:** `IDENTIFIER()` support varies by DDL statement — it works in `USE`, `DESCRIBE`, `CREATE TABLE`, but not in `ALTER SCHEMA`.

**Fix:** Replaced with `EXECUTE IMMEDIATE` using string concatenation:
```sql
EXECUTE IMMEDIATE
  'ALTER SCHEMA ' || catalog_use || '.' || schema_use || ' ENABLE PREDICTIVE OPTIMIZATION';
```

#### 2. SQL editor queries cannot be moved via the REST API `PATCH` endpoint

The queries API `PATCH /api/2.0/sql/queries/{id}` accepts an `update_mask` for fields like `query_text` and `description`, but silently ignores `parent_path` changes. The SDK's `UpdateQueryRequestQuery` class doesn't even expose `parent_path` as a field.

**Root cause:** The queries API treats `parent_path` as immutable after creation.

**Fix:** Create a new query via `POST /api/2.0/sql/queries` with the correct `parent_path` set at creation time, copy the content, then delete the old query.

#### 3. Auto-detected parameters cannot be reconfigured via API

SQL editor queries with `:param_name` syntax auto-detect parameters as text widgets. Deleting a parameter via `deleteQueryParameter` triggers immediate re-creation by the editor. The `addQueryParameter` tool then fails with "already exists."

**Root cause:** The editor's parameter auto-detection fires synchronously on query text changes and deletions.

**Fix:** For text parameters, use `modifyQueryParameterValue` to set correct defaults. For type changes (text → dropdown), manual UI configuration via the gear icon is required.

#### 4. Compute submission transient failures

Multiple `executeCode` calls failed with "command was not accepted within 30s" despite the compute being attached and runnable.

**Root cause:** Transient compute availability issue (serverless auto-selected).

**Fix:** Retried the same command; succeeded on subsequent attempt.

---

### Changes Made

#### DDL Notebook (`src/uc_setup/target-table-ddl`, ID: `3647522242740894`)

| Cell | Change | Description |
| --- | --- | --- |
| 3 (new) | Added | **Set Query Tags for Observability** — `SET QUERY_TAGS` with `project`, `component`, `pipeline`, `catalog`, `schema` using session variables from job params |

Cell ID: `162df3fd-7b3a-4d63-b48d-1f22c0b6fc84`

#### SQL Editor Query — Enable Predictive Optimization

**Old query:** UUID `0db8be1f-b4a4-491d-8b2f-9dc2226875af` (workspace ID `3647522242740934`) at home root — **deleted**

**New query:** UUID `afefd2e3-6a00-462c-965c-22452e1747f7` at `fixtures/examples/queries/`

| Change | Detail |
| --- | --- |
| `SET QUERY_TAGS` block added | Tags: `project` (`:project_tag`), `businessUnit` (`:business_unit_tag`), `env` (`:env_tag`), `component` (`'predictive_optimization'`), `catalog` (`:catalog_use`), `schema` (`:schema_use`) |
| Step 2 uncommented | `EXECUTE IMMEDIATE 'ALTER SCHEMA ...'` — active, not commented out |
| Step 3 added | `DESCRIBE SCHEMA EXTENDED` for post-enable verification |
| Relocated | Moved from home root to `fixtures/examples/queries/` via create-new + delete-old pattern |

**Widget parameters configured:**

| Widget | Type | Default |
| --- | --- | --- |
| `catalog_use` | text | `hls_fde_dev` |
| `schema_use` | text | `wearables` |
| `project_tag` | text | `dbxWearables ZeroBus` |
| `business_unit_tag` | text | `Healthcare and Life Sciences` |
| `env_tag` | dropdown | `dev` (choices: dev, hls_fde, prod) |

#### README.md

| Change | Detail |
| --- | --- |
| Query link updated | `#query-3647522242740934` → `#query-afefd2e3-6a00-462c-965c-22452e1747f7` |
| Description updated | "commented-out ALTER SCHEMA" → "ALTER SCHEMA statement (Step 2) and verification (Step 3)" |

#### `.assistant_instructions.md`

| Change | Detail |
| --- | --- |
| Memory added | `dbxWearables ZeroBus — SQL Editor Queries` section with query UUID, bundle path, widget list, and API move technique |

---

### Design Decisions

1. **`SET QUERY_TAGS` pattern adopted** — All SQL statements in both the DDL notebook and ad-hoc queries now carry session-level tags for cost tracking and auditing. Tags appear in query history, system tables, and usage dashboards.

2. **DDL notebook tags are static; query tags use widgets** — The DDL notebook runs via a job with fixed context (`project`, `component`, `pipeline` are known), so tags are hardcoded. The SQL editor query uses widget parameters for flexibility across environments.

3. **`EXECUTE IMMEDIATE` for `ALTER SCHEMA`** — Consistent with the DDL notebook's grant pattern (cells 7–12), which already uses `EXECUTE IMMEDIATE` for `GRANT` statements with dynamic identifiers.

4. **Step 2 left active (uncommented)** — User's explicit instruction. The query is a manual-run utility, not scheduled, so having the `ALTER SCHEMA` active is appropriate — the user chooses when to execute it.

5. **Query relocation via create-new + delete-old** — The queries API doesn't support `parent_path` updates. This technique preserves all content and is documented in `.assistant_instructions.md` for future use.

---

### Files Modified Summary

| File | Path (relative to bundle root) | Action |
| --- | --- | --- |
| target-table-ddl | `src/uc_setup/target-table-ddl` | Cell 3 added (query tags) |
| Enable Predictive Optimization (query) | `fixtures/examples/queries/` | Recreated at new path with tags, Step 2/3 fixes |
| README.md | `README.md` | Query link + description updated |
| .assistant_instructions.md | `~/.assistant_instructions.md` | Memory block added |
| infra_warehouse.sql_warehouse.yml | `resources/infra_warehouse.sql_warehouse.yml` | No changes (reviewed only) |

---

### `SET QUERY_TAGS` Reference

Minimal example for setting session-level query tags in Databricks SQL:

```sql
-- Set tags for the current session
SET QUERY_TAGS['team'] = 'fdew',
    QUERY_TAGS['pipeline'] = 'zerobus_ingest',
    QUERY_TAGS['env'] = 'prod';

-- Any subsequent statement carries those tags
SELECT * FROM demo_frank.zerostream.sensor_data LIMIT 10;

-- Inspect current tags
SET QUERY_TAGS;

-- Update / remove tags
SET QUERY_TAGS['env'] = 'staging',
    QUERY_TAGS['pipeline'] = UNSET;
```

Tags appear in: query history UI, `system.query.history` table, usage dashboards.
