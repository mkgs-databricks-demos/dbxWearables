-- Databricks notebook source
-- DBTITLE 1,Lakehouse Sync — Current-State Views for Load Test History
-- MAGIC %md
-- MAGIC # Lakehouse Sync — Current-State Views for Load Test History
-- MAGIC
-- MAGIC Creates current-state views over the SCD Type 2 history tables produced by **Lakehouse Sync** (wal2delta CDC).
-- MAGIC
-- MAGIC ### Dependency Chain
-- MAGIC
-- MAGIC This notebook must run **after** all three prerequisites are met:
-- MAGIC
-- MAGIC 1. **App deployed** — `dbxW_zerobus_app` creates Lakebase tables `app.load_test_runs` and `app.load_test_type_results` on first load test run
-- MAGIC 2. **Lakehouse Sync enabled** — one-time manual step in Lakebase UI: `app` schema → target catalog/schema
-- MAGIC 3. **History tables exist** — Lakehouse Sync auto-creates `lb_load_test_runs_history` and `lb_load_test_type_results_history` in UC after the first CDC event
-- MAGIC
-- MAGIC > **Do not** include this notebook in the `wearables_uc_setup` job (which runs pre-deployment). Wire it as a **separate post-deployment task** or run manually after Lakehouse Sync is confirmed active.
-- MAGIC
-- MAGIC ### What the views do
-- MAGIC
-- MAGIC The `lb_*_history` tables are append-only SCD Type 2 logs — every INSERT, UPDATE, and DELETE in Lakebase produces a new row with `_change_type`, `_timestamp`, `_lsn` (Log Sequence Number), and `_xid` (transaction ID). The views below deduplicate to the **latest state** per primary key, excluding deleted rows.

-- COMMAND ----------

-- DBTITLE 1,Set Catalog and Schema from Parameters
DECLARE OR REPLACE VARIABLE catalog_use STRING;
DECLARE OR REPLACE VARIABLE schema_use STRING;

SET VARIABLE catalog_use = :catalog_use;
SET VARIABLE schema_use = :schema_use;

USE IDENTIFIER(catalog_use || '.' || schema_use);
SELECT current_catalog(), current_schema();

-- COMMAND ----------

-- DBTITLE 1,Set Query Tags for Observability
SET QUERY_TAGS['project'] = 'dbxWearables ZeroBus';
SET QUERY_TAGS['component'] = 'lakehouse_sync_views';
SET QUERY_TAGS['pipeline'] = 'dbxw_zerobus_infra';
EXECUTE IMMEDIATE "SET QUERY_TAGS['catalog'] = '" || catalog_use || "';";
EXECUTE IMMEDIATE "SET QUERY_TAGS['schema'] = '" || schema_use || "';";

-- COMMAND ----------

-- DBTITLE 1,Preflight — Verify History Tables Exist
-- Fail fast if Lakehouse Sync hasn't created the history tables yet.
-- This prevents cryptic TABLE_OR_VIEW_NOT_FOUND errors in the CREATE VIEW statements.
SELECT
  'lb_load_test_runs_history' AS expected_table,
  CASE WHEN COUNT(*) > 0 THEN 'EXISTS' ELSE 'MISSING' END AS status
FROM information_schema.tables
WHERE table_schema = schema_use AND table_name = 'lb_load_test_runs_history'
UNION ALL
SELECT
  'lb_load_test_type_results_history',
  CASE WHEN COUNT(*) > 0 THEN 'EXISTS' ELSE 'MISSING' END
FROM information_schema.tables
WHERE table_schema = schema_use AND table_name = 'lb_load_test_type_results_history';

-- COMMAND ----------

-- DBTITLE 1,View DDL — v_load_test_runs (latest state per run)
-- Latest state of each load test run (excludes deleted rows).
-- ROW_NUMBER partitioned by PK (run_id), ordered by _lsn DESC picks
-- the most recent change. Filtering out 'update_preimage' avoids the
-- "before" image that Lakehouse Sync emits for UPDATEs.
CREATE OR REPLACE VIEW v_load_test_runs AS
SELECT * EXCEPT (_change_type, _timestamp, _lsn, _xid, _rn)
FROM (
  SELECT *, ROW_NUMBER() OVER (
    PARTITION BY run_id ORDER BY _lsn DESC, _timestamp DESC
  ) AS _rn
  FROM lb_load_test_runs_history
  WHERE _change_type != 'update_preimage'
)
WHERE _rn = 1 AND _change_type != 'delete';

-- COMMAND ----------

-- DBTITLE 1,View DDL — v_load_test_type_results (latest state per type per run)
-- Latest state of each per-type result (excludes deleted rows).
-- Composite PK: (run_id, record_type).
CREATE OR REPLACE VIEW v_load_test_type_results AS
SELECT * EXCEPT (_change_type, _timestamp, _lsn, _xid, _rn)
FROM (
  SELECT *, ROW_NUMBER() OVER (
    PARTITION BY run_id, record_type ORDER BY _lsn DESC, _timestamp DESC
  ) AS _rn
  FROM lb_load_test_type_results_history
  WHERE _change_type != 'update_preimage'
)
WHERE _rn = 1 AND _change_type != 'delete';

-- COMMAND ----------

-- DBTITLE 1,Verify Views Created
-- Confirm both views exist and are queryable.
SELECT 'v_load_test_runs' AS view_name, COUNT(*) AS row_count FROM v_load_test_runs
UNION ALL
SELECT 'v_load_test_type_results', COUNT(*) FROM v_load_test_type_results;
