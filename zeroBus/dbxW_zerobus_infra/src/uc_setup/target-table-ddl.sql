-- Databricks notebook source
-- DBTITLE 1,Wearable Data UC Setup — Target Table DDL
-- MAGIC %md
-- MAGIC # Wearable Data UC Setup — Target Table DDL
-- MAGIC
-- MAGIC Creates and maintains the `wearables_zerobus` bronze table in Unity Catalog, applies optimization, and grants access to the ZeroBus service principal.
-- MAGIC
-- MAGIC This notebook is invoked by the `wearables_uc_setup` job in the `dbxW_zerobus_infra` bundle. Parameters are passed from the job definition, which derives catalog/schema from `${resources.schemas.wearables_schema.*}`.
-- MAGIC
-- MAGIC > **Note:** This table uses **liquid clustering** (`CLUSTER BY AUTO`) instead of traditional Z-ORDER. ZeroBus supports writing to liquid-clustered tables (Beta). **Predictive optimization should remain enabled** on the target schema/table so that optimal clustering is applied asynchronously after ZeroBus writes.

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
-- Tag all subsequent statements in this session for cost tracking and auditing.
-- These tags appear in query history, system tables, and usage dashboards.
SET QUERY_TAGS['project'] = 'dbxWearables ZeroBus';
SET QUERY_TAGS['component'] = 'uc_setup';
SET QUERY_TAGS['pipeline'] = 'dbxw_zerobus_infra';
EXECUTE IMMEDIATE "SET QUERY_TAGS['catalog'] = '" || catalog_use || "';";
EXECUTE IMMEDIATE "SET QUERY_TAGS['schema'] = '" || schema_use || "';";

-- COMMAND ----------

-- DBTITLE 1,Target Table DDL — wearables_zerobus
CREATE TABLE IF NOT EXISTS wearables_zerobus
(
  record_id STRING NOT NULL COMMENT 'Server-generated GUID for each ingested record',
  ingested_at TIMESTAMP COMMENT 'Server-side ingestion timestamp',
  body VARIANT COMMENT 'Raw NDJSON line payload stored as VARIANT for flexible JSON querying',
  headers VARIANT COMMENT 'All HTTP headers except auth/cookie (blocklist stripped)',
  record_type STRING COMMENT 'Extracted from X-Record-Type header — any non-empty string (open validation)',
  source_platform STRING COMMENT 'Extracted from X-Platform header — identifies data source (apple_healthkit, android_health_connect, etc.)',
  user_id STRING COMMENT 'App-authenticated user ID from JWT claims — NULL until JWT auth is implemented',
  CONSTRAINT wearables_zerobus_pk PRIMARY KEY (record_id)
)
USING DELTA
CLUSTER BY AUTO
COMMENT 'Bronze table for wearable health data ingested via Databricks ZeroBus with VARIANT JSON storage'
TBLPROPERTIES (
  'delta.enableChangeDataFeed' = 'true',
  'delta.feature.variantType-preview' = 'supported',
  'delta.minReaderVersion' = '3',
  'delta.minWriterVersion' = '7',
  'quality' = 'bronze',
  'pipeline' = 'dbxw_zerobus',
  'description' = 'ZeroBus streaming target table for wearable health data'
);

-- COMMAND ----------

-- DBTITLE 1,Schema Evolution — Add source_platform Column
-- MAGIC %skip
-- MAGIC -- Schema evolution: adds columns to an existing table that was created
-- MAGIC -- before these columns were added to the DDL.
-- MAGIC -- Existing rows will have NULL for these columns (backfill not needed —
-- MAGIC -- the silver layer can coalesce from headers::"x-platform" if required).
-- MAGIC --
-- MAGIC -- Note: ADD COLUMNS is idempotent in practice — if the column already exists
-- MAGIC -- with the same type, Databricks silently succeeds. If it exists with a
-- MAGIC -- different type, the command will fail (which is the correct behavior).
-- MAGIC
-- MAGIC ALTER TABLE wearables_zerobus
-- MAGIC ADD COLUMNS (
-- MAGIC   source_platform STRING COMMENT 'Extracted from X-Platform header — identifies data source (apple_healthkit, android_health_connect, etc.)',
-- MAGIC   user_id STRING COMMENT 'App-authenticated user ID from JWT claims — NULL until JWT auth is implemented'
-- MAGIC );

-- COMMAND ----------

-- DBTITLE 1,Verify Predictive Optimization Status
-- Liquid clustering (CLUSTER BY AUTO) relies on predictive optimization
-- to trigger OPTIMIZE asynchronously after ZeroBus writes.
--
-- If the DESCRIBE output below shows predictive optimization is NOT enabled
-- for this schema, open the SQL editor query:
--   "dbxWearables ZeroBus — Enable Predictive Optimization"

DESCRIBE SCHEMA EXTENDED IDENTIFIER(catalog_use || '.' || schema_use);

-- COMMAND ----------

-- DBTITLE 1,Declare Service Principal Variable
DECLARE OR REPLACE VARIABLE spn_application_id STRING;
SET VARIABLE spn_application_id = :spn_application_id;
SELECT spn_application_id;

-- COMMAND ----------

-- DBTITLE 1,Grant USE CATALOG to Service Principal
DECLARE OR REPLACE use_catalog_grnt_stmnt STRING DEFAULT
  "GRANT USE CATALOG ON CATALOG " || catalog_use || " TO `" || spn_application_id || "`;"; 

SELECT use_catalog_grnt_stmnt;

-- COMMAND ----------

-- DBTITLE 1,Execute USE CATALOG Grant
EXECUTE IMMEDIATE use_catalog_grnt_stmnt;

-- COMMAND ----------

-- DBTITLE 1,Grant USE SCHEMA to Service Principal
DECLARE OR REPLACE use_schema_grnt_stmnt STRING DEFAULT
  "GRANT USE SCHEMA ON SCHEMA " || catalog_use || "." || schema_use || " TO `" || spn_application_id || "`;"; 

SELECT use_schema_grnt_stmnt;

-- COMMAND ----------

-- DBTITLE 1,Execute USE SCHEMA Grant
EXECUTE IMMEDIATE use_schema_grnt_stmnt;

-- COMMAND ----------

-- DBTITLE 1,Grant MODIFY and SELECT on Table to Service Principal
DECLARE OR REPLACE tbl_grnt_stmnt STRING DEFAULT
  "GRANT MODIFY, SELECT ON TABLE wearables_zerobus TO `" || spn_application_id || "`;"; 

SELECT tbl_grnt_stmnt;

-- COMMAND ----------

-- DBTITLE 1,Execute Table Grant
EXECUTE IMMEDIATE tbl_grnt_stmnt;

-- COMMAND ----------

-- DBTITLE 1,Verify Grants
SHOW GRANTS ON TABLE wearables_zerobus;

-- COMMAND ----------

-- DBTITLE 1,Show Table Definition
SHOW CREATE TABLE wearables_zerobus;