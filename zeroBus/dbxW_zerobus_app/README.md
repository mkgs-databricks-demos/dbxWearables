# dbxW_zerobus_app

Application bundle for the **dbxWearables ZeroBus** solution. This Databricks Asset Bundle manages the runtime application layer — the AppKit REST API, ZeroBus SDK consumer, Lakebase operational database, Spark Declarative Pipelines (silver/gold), jobs, and dashboards — that sits on top of the shared infrastructure provisioned by the companion [`dbxW_zerobus_infra`](../dbxW_zerobus_infra/README.md) bundle.

## Relationship to dbxWearables

The [dbxWearables](../../README.md) project ingests wearable and health app data into Databricks using AppKit, ZeroBus, Spark Declarative Pipelines, Lakebase, and AI/BI. The end-to-end flow is:

```
Client App (HealthKit, etc.)
  → Databricks App (AppKit REST API)        ← this bundle
    ├─ ZeroBus SDK → UC Bronze Table        ← infra bundle creates the table
    │    → Spark Declarative Pipeline       ← this bundle (silver → gold)
    └─ Lakebase (Postgres) → app state      ← infra bundle creates the project
```

This application bundle owns everything **above** the foundational infrastructure: the AppKit app that receives data, the ZeroBus consumer that streams it, the Lakebase connection for operational state, and the Spark Declarative Pipelines that refine data through the medallion layers.

## Prerequisites — Infrastructure Bundle

The [`dbxW_zerobus_infra`](../dbxW_zerobus_infra/README.md) bundle **must** be deployed and its UC setup job run before this bundle can be deployed. The infra bundle provisions:

| Shared Resource | How This Bundle References It |
| --- | --- |
| UC schema (`wearables`) | `${var.catalog}.${var.schema}` — per-target values kept in sync |
| Secret scope (`dbxw_zerobus_credentials`) | `${var.secret_scope_name}` — same default across both bundles |
| SQL warehouse (2X-Small serverless PRO) | By warehouse ID or name where needed |
| Service principal (`dbxw-zerobus-{schema}`) | OAuth credentials read from the secret scope at runtime |
| Bronze table (`wearables_zerobus`) | ZeroBus SDK streams directly to this table |
| Lakebase project (`dbxw-zerobus-wearables`) | Referenced via `${var.postgres_branch}` and `${var.postgres_database}` |

> **Cross-bundle convention:** DAB does not support cross-bundle resource substitutions (`${resources.*}`). This bundle maintains its own `catalog`, `schema`, and `secret_scope_name` variables with per-target values that **must match** the infra bundle. If the infra target values change, update both bundles.

The shared [`deploy.sh`](../deploy.sh) script enforces deployment order and runs readiness checks (all 5 secret scope keys + bronze table existence) before allowing this bundle to deploy.

## AppKit Application

The app is a **TypeScript/Node.js** project built with `@databricks/appkit` (Express + React + Vite). Source code lives in `src/app/` and is uploaded as the Databricks App source via `source_code_path: ../src/app` in the resource YAML.

### Architecture

```
                    ┌─────────────────────────────────────────────┐
                    │  AppKit App (src/app/)                       │
                    │                                              │
  HealthKit POST ──►│  Express Server (server/server.ts)           │
                    │    ├─ ZeroBus routes → SDK → bronze table    │
                    │    └─ Lakebase routes → pg.Pool → Postgres   │
                    │                                              │
  Browser ─────────►│  React Client (client/src/)                  │
                    │    └─ Vite + Tailwind + appkit-ui             │
                    └─────────────────────────────────────────────┘
```

### Plugins

Configured in `src/app/appkit.plugins.json`:

| Plugin | Package | Purpose | Required |
| --- | --- | --- | --- |
| `server` | `@databricks/appkit` | Express HTTP server, static files, Vite dev mode | Yes (template) |
| `lakebase` | `@databricks/appkit` | Postgres wire protocol via `pg.Pool` with OAuth token rotation | Yes (template) |
| `analytics` | `@databricks/appkit` | SQL query execution against Databricks SQL Warehouses | Optional |
| `files` | `@databricks/appkit` | File operations against Volumes and Unity Catalog | Optional |
| `genie` | `@databricks/appkit` | AI/BI Genie space integration | Optional |

### App Resources (6 total)

Defined in `resources/zerobus_ingest.app.yml` and mapped to environment variables in `src/app/app.yaml`:

| Resource | Type | `valueFrom` | Env Var |
| --- | --- | --- | --- |
| `postgres` | Lakebase Postgres | `postgres` | `LAKEBASE_ENDPOINT` |
| `zerobus-client-id` | Secret scope | `zerobus-client-id` | `ZEROBUS_CLIENT_ID` |
| `zerobus-client-secret` | Secret scope | `zerobus-client-secret` | `ZEROBUS_CLIENT_SECRET` |
| `zerobus-workspace-url` | Secret scope | `zerobus-workspace-url` | `ZEROBUS_WORKSPACE_URL` |
| `zerobus-endpoint` | Secret scope | `zerobus-endpoint` | `ZEROBUS_ENDPOINT` |
| `zerobus-target-table` | Secret scope | `zerobus-target-table` | `ZEROBUS_TARGET_TABLE` |

Platform-injected (no `valueFrom` needed): `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGSSLMODE`, `DATABRICKS_CLIENT_ID`, `DATABRICKS_CLIENT_SECRET`.

### What This Bundle Manages

| Resource Type | Resource | Purpose | Status |
| --- | --- | --- | --- |
| Databricks App | `dbxw-zerobus-ingest-${var.schema}` | AppKit REST API + Lakebase + ZeroBus SDK | Defined |
| Spark Declarative Pipeline | Silver/gold processing | Reads bronze → silver → gold | Planned |
| Jobs | Pipeline orchestration | Scheduled runs of the pipeline | Planned |
| Dashboards | AI/BI analytics | Wearable health data visualizations | Planned |

## Bundle Structure

```
dbxW_zerobus_app/
├── databricks.yml                          # Bundle configuration (variables, targets, includes)
├── README.md                               # This file
├── .gitignore                              # Excludes .databricks/, build artifacts, node_modules
├── resources/
│   └── zerobus_ingest.app.yml              # AppKit app resource (6 resources, per-target permissions)
├── src/
│   └── app/                                # AppKit source (source_code_path target)
│       ├── app.yaml                        # Runtime command + env var bindings
│       ├── appkit.plugins.json             # Plugin registry (lakebase, server, analytics, etc.)
│       ├── package.json                    # Node.js dependencies (@databricks/appkit 0.20.3)
│       ├── package-lock.json               # Locked dependency tree
│       ├── server/                         # Express backend
│       │   ├── server.ts                   # Entry point — createApp + plugin init
│       │   └── routes/
│       │       └── lakebase/
│       │           └── todo-routes.ts      # Sample Lakebase CRUD routes (scaffold)
│       ├── client/                         # React frontend
│       │   ├── index.html                  # HTML entry point
│       │   ├── vite.config.ts              # Vite build configuration
│       │   ├── tailwind.config.ts          # Tailwind CSS configuration
│       │   ├── src/
│       │   │   ├── App.tsx                 # Root React component
│       │   │   ├── main.tsx                # React DOM entry
│       │   │   └── pages/lakebase/         # Lakebase demo page
│       │   └── public/                     # Static assets (favicons, manifest)
│       ├── tests/
│       │   └── smoke.spec.ts              # Playwright smoke test
│       ├── tsconfig.json                   # Root TypeScript config
│       ├── tsconfig.server.json            # Server-specific TS config
│       ├── tsconfig.client.json            # Client-specific TS config
│       ├── tsconfig.shared.json            # Shared TS config
│       ├── tsdown.server.config.ts         # Server bundler config
│       ├── vitest.config.ts                # Vitest test runner config
│       ├── playwright.config.ts            # Playwright E2E config
│       ├── eslint.config.js                # ESLint config
│       ├── .prettierrc.json                # Prettier config
│       ├── .env.example                    # Environment variable template
│       ├── CLAUDE.md                       # AppKit AI assistant instructions
│       └── .gitignore                      # AppKit-specific ignores
└── fixtures/
    ├── sessions/                           # Development session logs
    └── AppKit App Bundle Setup Session.ipynb
```

## Variables

All variables are declared in `databricks.yml` and assigned per-target. Variables shared with the infra bundle use identical defaults and per-target values.

### Shared with infra bundle (must stay in sync)

| Variable | Default | Purpose |
| --- | --- | --- |
| `catalog` | *(per-target)* | Unity Catalog catalog — `hls_fde_dev` (dev), `hls_fde` (hls_fde) |
| `schema` | *(per-target)* | Schema name — `wearables` across all targets |
| `secret_scope_name` | `dbxw_zerobus_credentials` | Secret scope for ZeroBus OAuth credentials |
| `client_id_dbs_key` | `client_id` | Key name for the M2M client ID in the secret scope |
| `client_secret_dbs_key` | `client_secret` | Key name for the M2M client secret in the secret scope |
| `run_as_user` | *(per-target)* | User or service principal for workflow execution |
| `higher_level_service_principal` | `acf021b4-...` | SP application ID for production deployments |
| `serverless_environment_version` | `5` | Serverless environment version for tasks |

#### Schema-qualified secret key names

The `dev` and `hls_fde` targets override `client_id_dbs_key` and `client_secret_dbs_key` to schema-qualified names, enabling multiple schemas to share a single secret scope without key collisions:

| Target | `client_id_dbs_key` | `client_secret_dbs_key` |
| --- | --- | --- |
| `dev` | `client_id_${var.schema}` → `client_id_wearables` | `client_secret_${var.schema}` → `client_secret_wearables` |
| `hls_fde` | `client_id_${var.schema}` → `client_id_wearables` | `client_secret_${var.schema}` → `client_secret_wearables` |
| `prod` | `client_id` *(default)* | `client_secret` *(default)* |

### Lakebase Postgres

| Variable | Purpose |
| --- | --- |
| `postgres_branch` | Full branch resource name: `projects/dbxw-zerobus-wearables/branches/production` |
| `postgres_database` | Full database resource name: `projects/.../databases/db-0k31-aj7nvq8pgr` |

Obtain these by running:
```bash
databricks postgres list-branches projects/dbxw-zerobus-wearables
databricks postgres list-databases projects/dbxw-zerobus-wearables/branches/production
```

### App-specific

| Variable | Default | Purpose |
| --- | --- | --- |
| `dashboard_embed_credentials` | `false` | Dashboard credential mode (`true` = owner, `false` = viewer) |

### Tags (applied to all resources via presets)

| Variable | Default |
| --- | --- |
| `tags_project` | `dbxWearables ZeroBus` |
| `tags_businessUnit` | `Healthcare and Life Sciences` |
| `tags_developer` | `matthew.giglia@databricks.com` |
| `tags_requestedBy` | `Healthcare Providers and Health Plans` |
| `tags_RemoveAfter` | `2027-03-04` |

## Targets

| Target | Mode | Workspace | Catalog | Schema | Default |
| --- | --- | --- | --- | --- | --- |
| `dev` | development | `fevm-hls-fde.cloud.databricks.com` | `hls_fde_dev` | `wearables` | Yes |
| `hls_fde` | production | `fevm-hls-fde.cloud.databricks.com` | `hls_fde` | `wearables` | No |
| `prod` | production | `fevm-hls-fde.cloud.databricks.com` | *(TBD)* | *(TBD)* | No |

All three targets mirror the infra bundle's target definitions — same workspace hosts, root paths, presets, and permissions.

## Development

### AppKit local dev

```bash
cd src/app

# Install dependencies
npm install

# Start dev server (hot-reload, Vite dev mode)
npm run dev

# Build for production
npm run build

# Run tests
npm test

# Lint and format
npm run lint
npm run format
```

Local dev requires a `.env` file (see `.env.example`) with Lakebase connection details and Databricks host.

### Deployment

#### Via shared script (recommended)

```bash
cd zeroBus

# Full deployment — infra first, readiness checks, then app
./deploy.sh --target dev

# First-time setup — infra + UC setup job + app
./deploy.sh --target dev --run-setup

# App bundle only (with infrastructure readiness checks)
./deploy.sh --target dev --app

# App bundle only (skip readiness checks)
./deploy.sh --target dev --app --skip-checks

# Validate without deploying
./deploy.sh --target dev --validate

# Destroy app resources
./deploy.sh --target dev --app --destroy
```

#### Standalone (without deploy.sh)

```bash
cd zeroBus/dbxW_zerobus_app
databricks bundle validate --target dev
databricks bundle deploy --target dev
```

> **Warning:** Standalone deployment bypasses the readiness gate. Ensure the infra bundle is deployed, the UC setup job has run, and `client_secret` is provisioned before deploying standalone.

#### Workspace UI

1. Click the **deployment rocket** in the left sidebar to open the **Deployments** panel
2. Click **Deploy** to deploy the bundle
3. Hover over a resource and click **Run** to execute a job or pipeline

#### Managing Resources

* Use the **Add** dropdown in the Deployments panel to add new resources
* Click **Schedule** on a notebook to create a job definition

## Documentation

* [dbxWearables project README](../../README.md)
* [ZeroBus directory README](../README.md)
* [Infrastructure bundle README](../dbxW_zerobus_infra/README.md)
* [Declarative Automation Bundles in the workspace](https://docs.databricks.com/aws/en/dev-tools/bundles/workspace-bundles)
* [Declarative Automation Bundles Configuration reference](https://docs.databricks.com/aws/en/dev-tools/bundles/reference)
* [ZeroBus Ingest overview](https://docs.databricks.com/aws/en/ingestion/zerobus-overview/)
* [ZeroBus Ingest connector](https://docs.databricks.com/aws/en/ingestion/zerobus-ingest/)
* [Databricks Apps (AppKit)](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/)
* [Lakebase Autoscaling](https://docs.databricks.com/aws/en/lakebase/)
* [Spark Declarative Pipelines](https://docs.databricks.com/aws/en/delta-live-tables/)
