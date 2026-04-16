# dbxW_zerobus_infra

Shared infrastructure bundle for the **dbxWearables ZeroBus** solution. This Databricks Asset Bundle provisions foundational resources — secret scopes, Unity Catalog schemas, SQL warehouses, service principals, and bootstrap jobs — that must exist **before** the primary ZeroBus application bundle (or any other zeroBus-dependent bundle) is deployed.

## Relationship to dbxWearables

The [dbxWearables](../../README.md) project ingests wearable and health app data into Databricks using AppKit, ZeroBus, Spark Declarative Pipelines, Lakebase, and AI/BI. The end-to-end flow is:

```
Client App (HealthKit, etc.)
  → Databricks App (AppKit REST API)
    → ZeroBus SDK → Unity Catalog Bronze Table
      → Spark Declarative Pipeline (silver → gold)
```

This infrastructure bundle sits at the base of that stack. It creates the shared catalog objects, secrets, compute, and service principals that the AppKit application, ZeroBus streaming layer, and downstream pipelines all depend on.

## What This Bundle Manages

| Resource Type | Resource | Purpose |
| --- | --- | --- |
| Unity Catalog Schema | `wearables` schema with grants | Namespace isolation for medallion-layer tables |
| Secret Scope | `dbxw_zerobus_credentials` | ZeroBus endpoint, workspace URL, target table name, OAuth credentials |
| SQL Warehouse | 2X-Small serverless PRO (preview channel) | Compute for DDL jobs and ad-hoc queries |
| Service Principal | `dbxw-zerobus-{schema}` (created dynamically) | Least-privilege SPN for ZeroBus ingestion |
| Bronze Table | `wearables_zerobus` (liquid clustering) | Target table for ZeroBus streaming writes |
| Grants | Catalog, schema, and table grants | Access control for the ZeroBus SPN and user groups |

> **Note:** The exact resource list will grow as the solution matures. This bundle should remain limited to **shared, environment-level infrastructure** — application-specific resources (apps, pipelines, serving endpoints) belong in the primary ZeroBus bundle.

## UC Setup Job

The **dbxW ZeroBus — UC Setup** job (`resources/uc_setup.job.yml`) is a two-task workflow that bootstraps the ingestion infrastructure:

| Task | Notebook | What it does |
| --- | --- | --- |
| `ensure_service_principal` | `src/uc_setup/ensure-service-principal` (Python) | Creates or finds SPN `dbxw-zerobus-{schema}`, stores `client_id` + derived values in secret scope, grants scope READ, checks for `client_secret` |
| `create_wearables_table` | `src/uc_setup/target-table-ddl` (SQL) | Creates the bronze table with liquid clustering, grants USE CATALOG / USE SCHEMA / MODIFY / SELECT to the SPN |

The SPN's `application_id` is passed from task 1 to task 2 via a Databricks **task value**. The job is idempotent — safe to re-run at any time.

### Secret Scope Contents

The `dbxw_zerobus_credentials` scope contains two categories of secrets:

**Auto-provisioned** (by the UC setup job — refreshed on every run):

| Key | Source | Description |
| --- | --- | --- |
| `client_id` | SPN `application_id` | OAuth M2M client identifier |
| `workspace_url` | Derived from config | Databricks workspace URL |
| `zerobus_endpoint` | Derived from workspace ID + region | ZeroBus Ingest server endpoint |
| `target_table_name` | From job params | Fully qualified bronze table name |

**Admin-provisioned** (manual step required after first deploy):

| Key | Source | Description |
| --- | --- | --- |
| `client_secret` | Admin-generated | OAuth M2M client secret |

> **Admin action required:** After the first run of the UC setup job, an admin must generate an OAuth secret for the `dbxw-zerobus-{schema}` service principal and store the `client_secret` in the scope. The `client_id` is stored automatically. This can be done via:
> * **Workspace UI:** Settings → Identity and access → Service principals → Secrets → Generate secret
> * **Databricks CLI:** `databricks account service-principal-secrets create <sp_id>`
> * **External keystore:** Sync from Azure Key Vault, AWS Secrets Manager, or HashiCorp Vault

## Predictive Optimization Requirement

The `wearables_zerobus` bronze table uses **liquid clustering** (`CLUSTER BY AUTO`). ZeroBus writes data into the table, but optimal clustering is applied asynchronously by the **predictive optimization** service.

Predictive optimization uses an inheritance model: **account → catalog → schema**. If the catalog already has it enabled, the schema inherits automatically and no action is needed. If not, it must be enabled at the schema level before liquid clustering provides any benefit.

The DDL notebook (`src/uc_setup/target-table-ddl`) includes a `DESCRIBE SCHEMA EXTENDED` cell to verify the current status. If predictive optimization is not active, use the SQL editor query:

> **[dbxWearables ZeroBus — Enable Predictive Optimization](#query-afefd2e3-6a00-462c-965c-22452e1747f7)** — SQL editor query in `fixtures/examples/queries/`. Includes parameterized `DESCRIBE SCHEMA EXTENDED` check (Step 1), `ALTER SCHEMA ... ENABLE PREDICTIVE OPTIMIZATION` (Step 2), and verification (Step 3). Widgets for catalog, schema, environment, and query tags.

For more information, see the [Predictive Optimization documentation](https://docs.databricks.com/en/optimizations/predictive-optimization/).

## Deployment Order

Infrastructure resources must be deployed **first**, before any dependent bundle. The shared [`deploy.sh`](../deploy.sh) script enforces this order and runs **readiness checks** before allowing the app bundle to deploy.

### Pipeline stages

```
1. databricks bundle deploy --target dev       ← creates schema, scope, warehouse
2. databricks bundle run wearables_uc_setup    ← creates SPN, stores client_id + derived secrets, table, grants
3. ── Readiness gate ──────────────────────────
   │  ✓ Secret scope: client_id                (auto-provisioned)
   │  ✓ Secret scope: workspace_url            (auto-provisioned)
   │  ✓ Secret scope: zerobus_endpoint         (auto-provisioned)
   │  ✓ Secret scope: target_table_name        (auto-provisioned)
   │  ✓ Secret scope: client_secret            (admin-provisioned)
   │  ✓ Table: catalog.schema.wearables_zerobus
   └───────────────────────────────────────────
4. Admin: provision client_secret              ← generate OAuth secret, store in scope
5. dbxW_zerobus app bundle deploy             ← gated on all checks passing
```

### What the readiness gate checks

| Check | Missing → behaviour |
| --- | --- |
| Auto-provisioned keys (`client_id`, `workspace_url`, `zerobus_endpoint`, `target_table_name`) | **Fail** — instructs you to run the UC setup job |
| Bronze table (`wearables_zerobus`) | **Fail** — instructs you to run the UC setup job |
| Admin-provisioned key (`client_secret`) | **Fail** — prints admin provisioning instructions; use `--skip-checks` to override |

### deploy.sh flags

| Flag | Effect |
| --- | --- |
| `--target <name>` | Required. Bundle target (`dev`, `hls_fde`, `prod`). |
| `--infra` | Deploy only the infrastructure bundle. |
| `--app` | Deploy only the application bundle (with readiness checks). |
| `--run-setup` | Run the UC setup job after deploying the infra bundle. |
| `--skip-checks` | Bypass infrastructure readiness checks before app deploy. |
| `--validate` | Validate bundles without deploying. |
| `--destroy` | Destroy deployed resources for the target. |

## Targets

| Target | Mode | Workspace | Catalog | Default |
| --- | --- | --- | --- | --- |
| `dev` | development | `fevm-hls-fde.cloud.databricks.com` | `hls_fde_dev` | Yes |
| `hls_fde` | production | `fevm-hls-fde.cloud.databricks.com` | `hls_fde` | No |
| `prod` | production | `fevm-hls-fde.cloud.databricks.com` | (TBD) | No |

## Quick Start

### First deployment (recommended)

```bash
cd zeroBus

# Deploy infra + run UC setup job in one step
./deploy.sh --target dev --run-setup

# The script will report that client_secret is MISSING — expected on first run.
# Provision it (see "Provision the client_secret" below), then:
./deploy.sh --target dev --app
```

### Deploy via shared script

```bash
cd zeroBus
./deploy.sh --target dev                          # deploy all bundles (with readiness checks)
./deploy.sh --target dev --run-setup              # deploy infra + run UC setup + deploy app
./deploy.sh --target dev --infra                  # deploy only this infra bundle
./deploy.sh --target dev --app                    # deploy only the app bundle (with checks)
./deploy.sh --target dev --app --skip-checks      # deploy app without readiness checks
./deploy.sh --target dev --validate               # validate only, no deploy
./deploy.sh --target dev --destroy                # destroy deployed resources
```

### Deploy standalone (without deploy.sh)

```bash
cd zeroBus/dbxW_zerobus_infra
databricks bundle validate --target dev
databricks bundle deploy --target dev
databricks bundle run wearables_uc_setup --target dev
```

### Provision the client_secret (admin step)

```bash
# 1. Generate an OAuth secret for the SPN (requires workspace or account admin)
#    Via UI: Settings > Identity and access > Service principals > dbxw-zerobus-wearables > Secrets > Generate secret
#    Via CLI: databricks account service-principal-secrets create <sp_workspace_id>

# 2. Store the secret in the scope (client_id is already stored by the job)
databricks secrets put-secret --scope dbxw_zerobus_credentials --key client_secret --string-value "<secret>"
```

### Managing Resources

* Use the **Deployments** panel (rocket icon) in the workspace to deploy and run resources interactively.
* Use the **Add** dropdown to add new resource YAML files under `resources/`.
* Click **Schedule** on a notebook to create a job definition.

## Documentation

* [Declarative Automation Bundles in the workspace](https://docs.databricks.com/aws/en/dev-tools/bundles/workspace-bundles)
* [Bundle Configuration Reference](https://docs.databricks.com/aws/en/dev-tools/bundles/reference)
* [Predictive Optimization](https://docs.databricks.com/en/optimizations/predictive-optimization/)
* [Liquid Clustering](https://docs.databricks.com/en/delta/clustering/)
* [ZeroBus Ingest overview](https://docs.databricks.com/aws/en/ingestion/zerobus-overview/)
* [ZeroBus Ingest connector](https://docs.databricks.com/aws/en/ingestion/zerobus-ingest/)
* [ZeroBus limitations](https://docs.databricks.com/en/ingestion/zerobus-limits/)
