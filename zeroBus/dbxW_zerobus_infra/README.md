# dbxW_zerobus_infra

Shared infrastructure bundle for the **dbxWearables ZeroBus** solution. This Databricks Asset Bundle provisions foundational resources — secret scopes, Unity Catalog schemas, SQL warehouses, and other shared elements — that must exist **before** the primary ZeroBus application bundle (or any other zeroBus-dependent bundle) is deployed.

## Relationship to dbxWearables

The [dbxWearables](../../README.md) project ingests wearable and health app data into Databricks using AppKit, ZeroBus, Spark Declarative Pipelines, Lakebase, and AI/BI. The end-to-end flow is:

```
Client App (HealthKit, etc.)
  → Databricks App (AppKit REST API)
    → ZeroBus SDK → Unity Catalog Bronze Table
      → Spark Declarative Pipeline (silver → gold)
```

This infrastructure bundle sits at the base of that stack. It creates the shared catalog objects, secrets, and compute that the AppKit application, ZeroBus streaming layer, and downstream pipelines all depend on.

## What This Bundle Manages

| Resource Type | Examples | Purpose |
| --- | --- | --- |
| Secret Scopes | API keys, service credentials | Secure storage for secrets consumed by the AppKit app and pipelines |
| Unity Catalog Schemas | `wearables` schema with grants | Namespace isolation for medallion-layer tables |
| SQL Warehouses | Preview-channel serverless warehouse | Compute for DDL jobs and ad-hoc queries |
| Jobs | UC setup job (table DDL + grants) | Bootstrap bronze table and service principal permissions |
| Grants / Permissions | Schema, table, and catalog grants | Access control for service principals and user groups |

> **Note:** The exact resource list will grow as the solution matures. This bundle should remain limited to **shared, environment-level infrastructure** — application-specific resources (apps, pipelines, serving endpoints) belong in the primary ZeroBus bundle.

## Predictive Optimization Requirement

The `wearables_zerobus` bronze table uses **liquid clustering** (`CLUSTER BY AUTO`). ZeroBus writes data into the table, but optimal clustering is applied asynchronously by the **predictive optimization** service.

Predictive optimization uses an inheritance model: **account → catalog → schema**. If the catalog already has it enabled, the schema inherits automatically and no action is needed. If not, it must be enabled at the schema level before liquid clustering provides any benefit.

The DDL notebook (`src/uc_setup/target-table-ddl`) includes a `DESCRIBE SCHEMA EXTENDED` cell to verify the current status. If predictive optimization is not active, use the SQL editor query:

> **[dbxWearables ZeroBus — Enable Predictive Optimization](#query-afefd2e3-6a00-462c-965c-22452e1747f7)** — SQL editor query with widgets for catalog, schema, and environment. Includes parameterized `DESCRIBE SCHEMA EXTENDED` check and an `ALTER SCHEMA ... ENABLE PREDICTIVE OPTIMIZATION` statement (Step 2) and verification (Step 3).

> *Note: The file `fixtures/examples/queries/enable_predictive_optimization.sql` is superseded by the SQL editor query above and can be safely deleted.*

For more information, see the [Predictive Optimization documentation](https://docs.databricks.com/en/optimizations/predictive-optimization/).

## Deployment Order

Infrastructure resources must be deployed **first**, before any dependent bundle:

```
1. dbxW_zerobus_infra   ← this bundle (schemas, secrets, warehouse, DDL job, grants)
2. dbxW_zerobus          ← primary bundle (AppKit app, pipelines, jobs) — coming soon
```

Use the shared [`deploy.sh`](../deploy.sh) script in the parent `zeroBus/` directory to deploy bundles in the correct order.

## Targets

| Target | Mode | Workspace | Catalog | Default |
| --- | --- | --- | --- | --- |
| `dev` | development | `fevm-hls-fde.cloud.databricks.com` | `hls_fde_dev` | Yes |
| `hls_fde` | production | `fevm-hls-fde.cloud.databricks.com` | `hls_fde` | No |
| `prod` | production | `fevm-hls-fde.cloud.databricks.com` | (TBD) | No |

## Quick Start

### Deploy via shared script (recommended)

```bash
cd zeroBus
./deploy.sh --target dev            # deploys infra first, then app (when available)
./deploy.sh --target dev --infra    # deploy only this infra bundle
```

### Deploy standalone

```bash
cd zeroBus/dbxW_zerobus_infra
databricks bundle validate --target dev
databricks bundle deploy --target dev
```

### Run the UC setup job (after first deploy)

```bash
databricks bundle run wearables_uc_setup --target dev
```

### Managing Resources

- Use the **Deployments** panel (rocket icon 🚀) in the workspace to deploy and run resources interactively.
- Use the **Add** dropdown to add new resource YAML files under `resources/`.
- Click **Schedule** on a notebook to create a job definition.

## Documentation

- [Declarative Automation Bundles in the workspace](https://docs.databricks.com/aws/en/dev-tools/bundles/workspace-bundles)
- [Bundle Configuration Reference](https://docs.databricks.com/aws/en/dev-tools/bundles/reference)
- [Predictive Optimization](https://docs.databricks.com/en/optimizations/predictive-optimization/)
- [Liquid Clustering](https://docs.databricks.com/en/delta/clustering/)
- [ZeroBus Limitations (liquid clustering)](https://docs.databricks.com/en/ingestion/zerobus-limits/)
