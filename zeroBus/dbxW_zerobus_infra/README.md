# dbxW_zerobus_infra

Shared infrastructure bundle for the **dbxWearables ZeroBus** solution. This Databricks Asset Bundle provisions foundational resources — secret scopes, Unity Catalog schemas, SQL warehouses, Lakebase databases, service principals, and bootstrap jobs — that must exist **before** the primary ZeroBus application bundle (or any other zeroBus-dependent bundle) is deployed.

## Relationship to dbxWearables

The [dbxWearables](../../README.md) project ingests wearable and health app data into Databricks using AppKit, ZeroBus, Spark Declarative Pipelines, Lakebase, and AI/BI. The end-to-end flow is:

```
Client App (HealthKit, etc.)
  → Databricks App (AppKit REST API)
    → ZeroBus SDK → Unity Catalog Bronze Table
      → Spark Declarative Pipeline (silver → gold)
```

This infrastructure bundle sits at the base of that stack. It creates the shared catalog objects, secrets, compute, databases, and service principals that the AppKit application, ZeroBus streaming layer, and downstream pipelines all depend on.

## What This Bundle Manages

| Resource Type | Resource | Purpose |
| --- | --- | --- |
| Unity Catalog Schema | `wearables` schema with grants | Namespace isolation for medallion-layer tables |
| Secret Scope | `dbxw_zerobus_credentials` | ZeroBus endpoint, workspace URL, target table name, OAuth credentials |
| SQL Warehouse | 2X-Small serverless PRO (preview channel) | Compute for DDL jobs and ad-hoc queries |
| Lakebase Autoscaling | `dbxw-zerobus-wearables` (Postgres 17) | OLTP database for app state, sync metadata, operational data |
| Service Principal | `dbxw-zerobus-{schema}` (created dynamically) | Least-privilege SPN for ZeroBus ingestion |
| Service Principal | `dbxw-ios-bootstrap-{schema}` (created dynamically) | Minimal-privilege SPN for iOS auth bootstrap |
| Bronze Table | `wearables_zerobus` (liquid clustering) | Target table for ZeroBus streaming writes |
| Grants | Catalog, schema, and table grants | Access control for the ZeroBus SPN and user groups |

> **Note:** The exact resource list will grow as the solution matures. This bundle should remain limited to **shared, environment-level infrastructure** — application-specific resources (apps, pipelines, serving endpoints) belong in the primary ZeroBus bundle.

## UC Setup Job

The **dbxW ZeroBus — UC Setup** job (`resources/uc_setup.job.yml`) is a two-task workflow that bootstraps the ingestion infrastructure:

| Task | Notebook | What it does |
| --- | --- | --- |
| `ensure_service_principal` | `src/uc_setup/ensure-service-principal` (Python) | Creates or finds two SPNs: `dbxw-zerobus-{schema}` (ZeroBus ingestion) and `dbxw-ios-bootstrap-{schema}` (iOS auth). Stores client ID, workspace URL, ZeroBus endpoint, target table, stream pool size, JWT signing secret (auto-generated on first run), Apple bundle ID, and iOS SPN application ID. Grants scope READ to ZeroBus SPN. Checks for admin-provisioned client secret. |
| `create_wearables_table` | `src/uc_setup/target-table-ddl` (SQL) | Creates the bronze table with liquid clustering, grants USE CATALOG / USE SCHEMA / MODIFY / SELECT to the SPN |

The SPN's `application_id` is passed from task 1 to task 2 via a Databricks **task value**. The job is idempotent — safe to re-run at any time.

### Secret Scope Contents

The `dbxw_zerobus_credentials` scope contains two categories of secrets. The client ID and client secret key names are **schema-qualified** in dev and hls_fde targets (e.g. `client_id_wearables`) so that multiple schemas can share a single scope without key collisions.

**Auto-provisioned** (by the UC setup job — refreshed on every run unless noted):

| Key | Name Variable | Source | Description |
| --- | --- | --- | --- |
| Client ID | `client_id_dbs_key` | ZeroBus SPN `application_id` | OAuth M2M client identifier |
| Workspace URL | `workspace_url` (fixed) | Derived from config | Databricks workspace URL |
| ZeroBus endpoint | `zerobus_endpoint` (fixed) | Derived from workspace ID + region | ZeroBus Ingest server endpoint |
| Target table name | `target_table_name` (fixed) | From job params | Fully qualified bronze table name |
| Stream pool size | `zerobus_stream_pool_size` (fixed) | From job params | Number of concurrent gRPC streams in the SDK stream pool |
| JWT signing secret | `jwt_signing_secret_key` | Auto-generated (first run only) | HS256 key for app-issued JWTs — preserved on re-runs |
| Apple bundle ID | `apple_bundle_id_key` | From job params | iOS app bundle identifier for Apple token `aud` validation |
| iOS SPN app ID | `ios_spn_application_id_key` | iOS Bootstrap SPN `application_id` | Route guard identity verification |

**Admin-provisioned** (manual step required after first deploy):

| Key | Name Variable | Source | Description |
| --- | --- | --- | --- |
| Client secret | `client_secret_dbs_key` | Admin-generated | ZeroBus SPN OAuth M2M client secret |

**Admin steps NOT stored in the secret scope:**

| Step | SPN | Action | Purpose |
| --- | --- | --- | --- |
| Generate OAuth secret | `dbxw-ios-bootstrap-{schema}` | Workspace UI or CLI | iOS app needs `client_id` + `client_secret` for AppKit proxy auth |
| Grant CAN_USE on app | `dbxw-ios-bootstrap-{schema}` | Apps UI or API | iOS SPN must reach the Databricks App endpoint |
| Embed in iOS binary | `dbxw-ios-bootstrap-{schema}` | Xcode project | OAuth credentials compiled into the app |

#### Schema-qualified key names per target

| Target | `client_id_dbs_key` | `client_secret_dbs_key` |
| --- | --- | --- |
| `dev` | `client_id_wearables` | `client_secret_wearables` |
| `hls_fde` | `client_id_wearables` | `client_secret_wearables` |
| `prod` | `client_id` *(default)* | `client_secret` *(default)* |

The actual key names are passed to the UC setup job as parameters (`client_id_dbs_key`, `client_secret_dbs_key`) and resolved from the bundle variables at deploy time. The companion `dbxW_zerobus_app` bundle declares matching variables with identical per-target values.

> **Admin actions required after first run:**
> 1. **ZeroBus SPN** (`dbxw-zerobus-{schema}`): Generate an OAuth secret and store it under the schema-qualified key name (shown in the table above) in the scope. The client ID is stored automatically.
> 2. **iOS Bootstrap SPN** (`dbxw-ios-bootstrap-{schema}`): Generate an OAuth secret and embed the `client_id` + `client_secret` in the iOS app binary. Then grant `CAN_USE` on the Databricks App (after app bundle deploy).
>
> Provisioning methods:
> * **Workspace UI:** Settings → Identity and access → Service principals → Secrets → Generate secret
> * **Databricks CLI:** `databricks account service-principal-secrets create <sp_id>`
> * **External keystore:** Sync from Azure Key Vault, AWS Secrets Manager, or HashiCorp Vault

## Lakebase Autoscaling

The `wearables.lakebase.yml` resource file defines a **Lakebase Autoscaling** project (`dbxw-zerobus-wearables`) — a fully managed, PostgreSQL 17-compatible OLTP database for the application layer. It provides low-latency storage for data that doesn't belong in the analytical lakehouse: user sessions, app state, sync metadata, and operational records.

### Resource hierarchy

The project auto-creates a `production` branch and a read-write endpoint at creation time. Only the project and branch are declared as bundle resources — the endpoint is managed implicitly via `default_endpoint_settings` on the project because each branch allows only one READ_WRITE endpoint.

| Resource | Key | Description |
| --- | --- | --- |
| Project | `wearables_lakebase` | Top-level container (`project_id: dbxw-zerobus-wearables`, Postgres 17) |
| Branch | `wearables_production` | Default protected branch (`production`), no expiry |
| Endpoint | *(auto-created)* | Read-write endpoint; autoscaling controlled by `default_endpoint_settings` |

### Autoscaling limits per target

| Target | Min CU | Max CU |
| --- | --- | --- |
| `dev` | 0.5 | 2 |
| `hls_fde` | 0.5 | 4 |
| `prod` | 0.5 | 4 |

The endpoint uses autoscaling with scale-to-zero capability (min 0.5 CU) to minimize idle cost. Both the project and production branch have `lifecycle.prevent_destroy: true` to prevent accidental deletion.

### Post-deploy manual steps

These Lakebase integrations have no DAB resource type or API and must be configured manually in the UI after the first deploy. **Neither is required for AppKit** — the Lakebase plugin connects via direct Postgres wire protocol (port 5432), not the Data API.

**1. Enable the Data API** *(optional — for external REST clients)*

The Data API is a PostgREST-compatible HTTP/REST layer on top of the Postgres compute endpoint. It is **not** used by AppKit's Lakebase plugin (which uses direct wire protocol with OAuth token rotation). Enable it if you need HTTP-based database access from browsers, external services, or tools without a Postgres driver:

> Lakebase App → project `dbxw-zerobus-wearables` → **Data API** → **Enable Data API**

This creates the `authenticator` Postgres role, the `pgrst` schema, and exposes the `public` schema via REST endpoints. The `deploy.sh` readiness gate includes an informational check — it notes the Data API status but does not block the deploy.

**2. Register in Unity Catalog** *(optional — enables SQL queries)*

Registering the Lakebase database as a UC catalog allows SQL warehouses, notebooks, and dashboards to query Lakebase tables alongside lakehouse data:

> Catalog Explorer → **Create catalog** → type **Lakebase Autoscaling** → select project / `production` branch / `databricks_postgres` database

Once registered, you can query Lakebase tables from any SQL interface:

```sql
SELECT * FROM lakebase_catalog.public.my_table;
```

### AppKit integration

The app bundle's AppKit application references this database via the **Lakebase plugin**:

```typescript
import { createApp, server, lakebase } from '@databricks/appkit';

const appkit = await createApp({
  plugins: [server(), lakebase()],
});
```

The plugin connects via **direct Postgres wire protocol** (port 5432) using the app's auto-provisioned service principal credentials. When a `database` resource is configured in the app YAML, the platform injects standard Postgres environment variables (`PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGSSLMODE`) and handles OAuth token rotation automatically. No Data API or additional configuration is required.

> **Cost note:** Deploying this resource starts the Lakebase instance immediately. Autoscaling with 0.5 CU minimum keeps idle cost low, but the instance is billable once deployed. See [Lakebase pricing](https://docs.databricks.com/aws/en/oltp/projects/pricing/).

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
1. databricks bundle deploy --target dev       ← creates schema, scope, warehouse, Lakebase project
2. databricks bundle run wearables_uc_setup    ← creates SPN, stores secrets (schema-qualified keys), table, grants
3. Manual: provision client_secret             ← generate OAuth secret, store under {client_secret_dbs_key}
4. Optional: enable Lakebase Data API          ← Lakebase App → project → Data API → Enable (for REST clients)
5. Optional: register Lakebase in UC           ← Catalog Explorer → Create catalog → Lakebase Autoscaling
6. ── Readiness gate ──────────────────────
   │  ✓ Secret scope: {client_id_dbs_key}       (auto-provisioned)
   │  ✓ Secret scope: workspace_url            (auto-provisioned)
   │  ✓ Secret scope: zerobus_endpoint         (auto-provisioned)
   │  ✓ Secret scope: target_table_name        (auto-provisioned)
   │  ✓ Secret scope: jwt_signing_secret       (auto-provisioned, first run only)
   │  ✓ Secret scope: apple_bundle_id          (auto-provisioned)
   │  ✓ Secret scope: ios_spn_application_id   (auto-provisioned)
   │  ✓ Secret scope: {client_secret_dbs_key}   (admin-provisioned)
   │  ✓ Table: catalog.schema.wearables_zerobus
   │  ✓ Secret scope: zerobus_stream_pool_size (auto-provisioned)
   │  ⚠ Lakebase Data API status               (info — warns only)
   └───────────────────────────────────────────
7. dbxW_zerobus app bundle deploy             ← gated on hard checks passing
```

Key names in `{braces}` are resolved from bundle variables at runtime. In dev/hls_fde targets, these resolve to `client_id_wearables` and `client_secret_wearables`.

### What the readiness gate checks

| Check | Missing → behaviour |
| --- | --- |
| Auto-provisioned keys (`{client_id_dbs_key}`, `workspace_url`, `zerobus_endpoint`, `target_table_name`, `jwt_signing_secret`, `apple_bundle_id`, `ios_spn_application_id`) | **Fail** — instructs you to run the UC setup job |
| Bronze table (`wearables_zerobus`) | **Fail** — instructs you to run the UC setup job |
| Admin-provisioned key (`{client_secret_dbs_key}`) | **Fail** — prints admin provisioning instructions; use `--skip-checks` to override |
| Lakebase Data API status | **Info** — notes status if detectable; does not block deploy (AppKit does not require it) |

The `deploy.sh` script resolves the actual key names from the infra bundle summary (`client_id_dbs_key` and `client_secret_dbs_key` variables) before running the checks. The Lakebase project ID is also resolved from the bundle summary's `postgres_projects` resources.

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

# The script will report that the client secret key is MISSING — expected on first run.
# Provision it (see "Provision the client_secret" below), then:
./deploy.sh --target dev --app

# Optional post-deploy steps (not required for AppKit):
#   Enable Data API:  Lakebase App → project → Data API → 'Enable Data API'
#   Register in UC:   Catalog Explorer → Create catalog → Lakebase Autoscaling
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
# 1. Generate an OAuth secret for the ZeroBus SPN (requires workspace or account admin)
#    Via UI: Settings > Identity and access > Service principals > dbxw-zerobus-wearables > Secrets > Generate secret
#    Via CLI: databricks account service-principal-secrets create <sp_workspace_id>

# 2. Store the secret in the scope under the schema-qualified key name.
#    For dev/hls_fde targets, the key is client_secret_wearables:
databricks secrets put-secret dbxw_zerobus_credentials client_secret_wearables --string-value "<secret>"

#    For the prod target (unqualified default):
#    databricks secrets put-secret dbxw_zerobus_credentials client_secret --string-value "<secret>"
```

### Provision the iOS Bootstrap SPN (admin step)

The iOS Bootstrap SPN (`dbxw-ios-bootstrap-{schema}`) is created automatically by the UC setup job, but two manual steps are required:

```bash
# 1. Generate an OAuth secret for the iOS SPN
#    Via UI: Settings > Identity and access > Service principals
#           > dbxw-ios-bootstrap-wearables > Secrets > Generate secret
#    Via CLI: databricks account service-principal-secrets create <ios_sp_workspace_id>

# 2. After the app bundle is deployed, grant CAN_USE on the Databricks App:
#    Via Apps UI: Apps > dbxw-0bus-ingest-{target} > Permissions > Add > dbxw-ios-bootstrap-wearables > CAN_USE

# 3. Embed the iOS SPN's client_id + client_secret in the iOS app binary (Xcode project)
#    The client_id (application_id) is stored in the secret scope as ios_spn_application_id
#    and can be read with:
#    databricks secrets get-secret dbxw_zerobus_credentials ios_spn_application_id

# NOTE: The JWT signing secret and Apple bundle ID are auto-provisioned by the
# UC setup job — no manual action needed for those.
```

### Managing Resources

* Use the **Deployments** panel (rocket icon) in the workspace to deploy and run resources interactively.
* Use the **Add** dropdown to add new resource YAML files under `resources/`.
* Click **Schedule** on a notebook to create a job definition.

## Documentation

* [Declarative Automation Bundles in the workspace](https://docs.databricks.com/aws/en/dev-tools/bundles/workspace-bundles)
* [Bundle Configuration Reference](https://docs.databricks.com/aws/en/dev-tools/bundles/reference)
* [Lakebase Autoscaling](https://docs.databricks.com/aws/en/oltp/projects/)
* [Lakebase Data API](https://docs.databricks.com/aws/en/oltp/projects/data-api/)
* [Connect Apps to Lakebase](https://docs.databricks.com/aws/en/oltp/projects/tutorial-databricks-apps-autoscaling/)
* [Register Lakebase in Unity Catalog](https://docs.databricks.com/aws/en/oltp/projects/register-uc/)
* [Manage Lakebase with Bundles](https://docs.databricks.com/aws/en/oltp/projects/manage-with-bundles/)
* [Predictive Optimization](https://docs.databricks.com/en/optimizations/predictive-optimization/)
* [Liquid Clustering](https://docs.databricks.com/en/delta/clustering/)
* [ZeroBus Ingest overview](https://docs.databricks.com/aws/en/ingestion/zerobus-overview/)
* [ZeroBus Ingest connector](https://docs.databricks.com/aws/en/ingestion/zerobus-ingest/)
* [ZeroBus limitations](https://docs.databricks.com/en/ingestion/zerobus-limits/)
