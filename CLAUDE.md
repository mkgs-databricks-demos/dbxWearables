# CLAUDE.md

## Project Overview

**dbxWearables** is a Databricks solution for ingesting and analyzing wearable and health app data. It uses the Databricks ecosystem: AppKit, ZeroBus, Spark Declarative Pipelines, Lakebase, and AI/BI.

- **Owner:** MKG Solutions Databricks Demos
- **License:** MIT
- **Repository:** `mkgs-databricks-demos/dbxWearables`

## Current State

The project has been restructured as a **platform** — one AppKit gateway, one shared bronze table, N pluggable cloud-API connectors, N phone-SDK client apps. Garmin is the first full reference connector; other vendors are contributor-ready stubs.

What exists:
- `README.md` — platform overview + capability matrix
- `LICENSE` — MIT
- `CLAUDE.md` — this file
- `app/` — Databricks AppKit (Node.js + TypeScript) gateway. Pre-authored plugin skeletons under `app/plugins/`. Merge procedure in `app/SETUP.md`.
- `app/plugins/zerobus/` — Tier-1 generic ZeroBus writer (candidate for upstream contribution to AppKit)
- `app/plugins/wearable-core/` — Tier-2 platform plugin (Lakebase migrations, credential store, bronze writer, OAuth base classes, connector registry)
- `app/plugins/garmin/` — Tier-3 full reference connector (OAuth 1.0a + webhook PING→PULL)
- `app/plugins/fitbit|whoop|oura|withings|strava/` — Tier-3 stubs (manifest + contributor README)
- `providers/common/` — shared Python (`HealthEvent`, `ConnectorProtocol`, `LakebaseCredentialStore`)
- `providers/garmin/` — Garmin domain code (pull via python-garminconnect, Connect IQ watch widget, silver normalizer, DABs bundle)
- `providers/fitbit|whoop|oura|withings|strava/` — contributor-ready stub READMEs
- `providers/samsung_health_cloud/` — explicit README: no cloud API, use `clients/samsungHealth`
- `clients/healthKit/` — iOS app for Apple HealthKit integration (Swift/SwiftUI, MVVM). Databricks-branded UI with Dashboard / Data Explorer / Payloads / About tabs, onboarding flow, SyncLedger, anchored NDJSON sync pipeline, unit tests. The Xcode project file hasn't been generated yet — see `clients/healthKit/XCODE_SETUP.md`.
- `clients/androidHealthConnect/`, `clients/samsungHealth/` — placeholder apps
- `lakeflow/wearable_daily_fanout.ipynb`, `lakeflow/wearable_backfill_fanout.ipynb` — cross-provider pull fan-out notebooks that discover enrolled users from Lakebase and dispatch to each provider's Python `ConnectorProtocol` impl
- `zeroBus/dbxW_zerobus_infra/` — DABs bundle for shared infrastructure (schema, secret scope, SPN, bronze table, SQL warehouse)

Not yet done (by design — needs Matt's interactive CLI work):
- Running `databricks apps init` to generate the AppKit scaffold (package.json, server/server.ts, app.yaml, client/). The pre-authored `app/plugins/` tree merges in once this runs. Procedure in `app/SETUP.md`.
- Scaffolding AppKit plugin wrappers via `npx @databricks/appkit plugin create`.
- Lakeflow DABs bundle for the fanout notebooks (currently they live as standalone `.ipynb` files).

## Architecture

Platform-first: one AppKit gateway fronts every source. Every row lands in the same bronze shape in `wearables_zerobus`.

```
Wearable device
  │
  ├── paired with phone  → iOS / Android / Samsung app ─► POST NDJSON ─┐
  │                                                                      │
  └── paired with cloud  → Garmin / Fitbit / Whoop / Oura / ...          │
                                                                         │
                                                         webhook/poll    │
                                                                 ▼       ▼
                                              ┌─────────────────────────────────┐
                                              │ AppKit gateway (Node.js + TS)   │
                                              │  Tier 1:  zerobus plugin        │
                                              │  Tier 2:  wearable-core plugin  │
                                              │  Tier 3:  per-provider plugins  │
                                              │    ┌───────────────────────┐    │
                                              │    │ credentialStore ─► Lakebase
                                              │    │ bronzeWriter    ──┐  │    │
                                              │    │ connectorReg      │  │    │
                                              │    └───────────────────┘  │    │
                                              └───────────────────────────┼────┘
                                                                          │ ZeroBus SDK
                                                                          ▼
                                              ┌─────────────────────────────────┐
                                              │ wearables_zerobus (VARIANT)     │
                                              └──────────────┬──────────────────┘
                                                             ▼
                                              ┌─────────────────────────────────┐
                                              │ Spark Declarative Pipeline      │
                                              │   → silver_health_events        │
                                              │   → gold_* per use case         │
                                              └─────────────────────────────────┘
```

### AppKit plugin tiers

| Tier | Plugin | Concern |
| --- | --- | --- |
| 1 | `zerobus` | Generic ZeroBus writer — row-shape-agnostic, candidate for contribution back to the AppKit project |
| 2 | `wearable-core` | Platform: Lakebase migrations, `credentialStore`, `bronzeWriter`, connector registry, OAuth base classes |
| 3 | `garmin`, `fitbit`, `whoop`, `oura`, `withings`, `strava` | One plugin per vendor: OAuth, webhook, registry registration |

### Two integration patterns

1. **Cloud-API connector pattern** — vendor has OAuth + webhooks or polling. Implemented as an AppKit Tier-3 plugin that registers into `AppKit.wearableCore.connectorRegistry` during `setup()`. Pull path optionally mirrored in Python under `providers/<name>/pull/` for the Lakeflow fanout.
2. **Phone-SDK client pattern** — vendor only exposes the health store on-device. Implemented as a mobile client app under `clients/<name>/` that POSTs NDJSON to the generic `POST /api/wearable-core/ingest/:platform` endpoint.

Both patterns produce identical bronze rows. Silver dispatches on `headers:"X-Platform"` to a small per-provider normalizer and projects everything into one `HealthEvent` schema (`source, user_id, device_id, metric_type, value, unit, recorded_at, metadata`).

### Component responsibilities

1. **Client apps (`clients/`)** — iOS / Android / Samsung apps that read the on-device health store and POST NDJSON to the AppKit gateway. Same `X-Platform` / `X-Record-Type` / `X-Device-Id` / `X-User-Id` / `X-Upload-Timestamp` header contract across all of them.
2. **AppKit gateway (`app/`)** — Databricks App built on AppKit. Plugins do the work; `server/server.ts` wires them up. Hosts every REST endpoint (phone ingest, OAuth flows, webhooks) and the React Connections UI.
3. **Per-provider plugin (`app/plugins/<provider>/`)** — the server-side piece of a cloud-API connector: OAuth manifest resources, webhook handler, route mounting, `connectorRegistry.register(...)` in `setup()`.
4. **Per-provider Python (`providers/<name>/`)** — the Lakeflow-side piece of a cloud-API connector: `pull_batch` satisfying `ConnectorProtocol`, plus the silver `normalizer.py` that maps bronze VARIANT to `HealthEvent`.
5. **`wearable-core` plugin** — Lakebase migrations (via the shared `runMigrations(namespace, dir)` helper any future plugin can reuse), `credentialStore`, `bronzeWriter` that shapes the canonical bronze row.
6. **`zerobus` plugin** — wraps `databricks-zerobus-ingest-sdk` with per-table stream pool, retries, OTel. Has no opinion on row shape.
7. **Unity Catalog bronze table (`wearables_zerobus`)** — schema-on-read, liquid clustered. Columns: `record_id`, `ingested_at`, `body VARIANT`, `headers VARIANT`, `record_type`. Provisioned by `zeroBus/dbxW_zerobus_infra`.
8. **Lakebase** — Postgres store for `app_users`, `wearable_credentials`, `wearable_anchors`, `wearable_sync_runs`, `appkit_migrations`. Vendor-agnostic from day one — `provider` is a column, not a table prefix.
9. **Spark Declarative Pipeline** — reads bronze, dispatches on `headers:"X-Platform"` to each `providers/<name>/silver/normalizer.py`, writes a single `silver_health_events` table.
10. **Lakeflow fanout (`lakeflow/`)** — one `wearable_daily_fanout.ipynb` job iterates `wearable_credentials` × registered Python `ConnectorProtocol` implementations. Rate-limit-aware per provider.

### Key design decisions

- **One bronze table, one wire format** — every producer, cloud or phone, writes `{record_id, ingested_at, body, headers, record_type}`. Silver doesn't know or care which vendor produced a row.
- **`X-Record-Type` header is load-bearing** — primary routing key at bronze. Delete records are distinguished from regular records by this header rather than by schema inspection.
- **Plugin ownership of tables** — `wearable-core` owns its four tables via `runMigrations("wearable-core", ...)`. Any future plugin that owns tables calls the same helper with its own namespace.
- **Two-tier row shaping** — the `zerobus` plugin is generic (contributable upstream); the `wearable-core` `bronzeWriter` layers the canonical wearable-bronze shape on top.
- **OAuth secrets are optional until enabled** — each provider plugin declares its `clientId`/`clientSecret`/`webhookSecret` as optional manifest resources, promoted to required only when that plugin is enabled.
- **Phone-sync upgradeable to webhook** — users get started with the low-friction phone-SDK path; customers who need higher fidelity (Apple Health drops HRV summaries, sleep stages, Body Battery, VO2 max) move to the vendor's cloud webhook path without any change to bronze / silver.

## Technology Stack

- **Databricks AppKit** — TypeScript SDK for Databricks Apps with a plugin-based architecture. See https://databricks.github.io/appkit/docs/. Hosts every REST endpoint and the React Connections UI.
- **ZeroBus** — low-latency streaming writer; the `zerobus` AppKit plugin wraps `databricks-zerobus-ingest-sdk` and every producer writes through it.
- **Spark Declarative Pipelines** (formerly Delta Live Tables) — reads bronze, dispatches on `X-Platform`, writes `silver_health_events` and gold.
- **Unity Catalog** — data governance; `wearables_zerobus` bronze uses `VARIANT` for `body` and `headers`.
- **Lakebase** — Postgres store for `app_users`, `wearable_credentials`, `wearable_anchors`, `wearable_sync_runs`, `appkit_migrations`. Accessed via AppKit's first-party Lakebase plugin (`AppKit.lakebase.query(...)`).
- **AI/BI** — dashboards on the gold layer (planned).
- **Language:** TypeScript (AppKit gateway), Python (pull connectors + silver + notebooks), SQL (migrations + DDL), Swift (iOS client), Kotlin / Java (Android clients, planned).
- **Platform:** Databricks on cloud (Azure, AWS, or GCP).

## Repository Structure

```
dbxWearables/
├── CLAUDE.md                               # This file — guidance for AI assistants
├── README.md                               # Platform overview + capability matrix
├── LICENSE                                 # MIT
│
├── app/                                    # Databricks AppKit gateway (Node.js + TS)
│   ├── README.md
│   ├── SETUP.md                            # How to merge pre-authored plugin skeletons with `databricks apps init` output
│   └── plugins/
│       ├── zerobus/                        # Tier 1 — generic ZeroBus writer (candidate for upstream contribution)
│       │   ├── index.ts                    # toPlugin(ZerobusPlugin)
│       │   └── src/{streamPool.ts, types.ts}
│       ├── wearable-core/                  # Tier 2 — platform plugin
│       │   ├── index.ts                    # toPlugin(WearableCorePlugin)
│       │   ├── migrations/                 # 001_app_users.sql … 004_wearable_sync_runs.sql
│       │   └── src/
│       │       ├── runMigrations.ts        # Shared migrations helper (any plugin can reuse)
│       │       ├── connector.ts            # WearableConnector interface
│       │       ├── connectorRegistry.ts    # registerd connectors list
│       │       ├── credentialStore.ts      # LakebaseCredentialStore (AES-256-GCM envelope encryption)
│       │       ├── bronzeWriter.ts         # Canonical bronze row shape → AppKit.zerobus.writeRow
│       │       ├── baseOAuth2Connector.ts  # PKCE scaffolding for Fitbit/Whoop/Oura/Withings/Strava
│       │       ├── baseOAuth1aConnector.ts # Legacy scaffolding for Garmin Health API
│       │       └── routes/{ingest.ts, connections.ts}
│       ├── garmin/                         # Tier 3 — full reference connector
│       │   ├── index.ts
│       │   └── src/
│       │       ├── garminConnector.ts      # extends BaseOAuth1aConnector
│       │       └── routes/{oauth.ts, webhook.ts}
│       ├── fitbit/   README.md             # Tier 3 stubs — manifest + contributor README only
│       ├── whoop/    README.md
│       ├── oura/     README.md
│       ├── withings/ README.md
│       └── strava/   README.md
│
├── providers/                              # Backend connector code (pull + silver + notebooks)
│   ├── common/
│   │   ├── silver/health_event.py          # Canonical HealthEvent dataclass (single source of truth)
│   │   ├── connector_protocol.py           # Python mirror of WearableConnector for fanout dispatch
│   │   └── credential_store.py             # Python LakebaseCredentialStore (psycopg)
│   ├── garmin/                             # Full impl — Python pull + Connect IQ widget + silver + DABs bundle
│   │   ├── pull/                           # python-garminconnect / garth
│   │   ├── connect_iq/                     # Monkey C watch widget
│   │   ├── silver/normalizer.py            # bronze VARIANT → HealthEvent
│   │   ├── notebooks/                      # Legacy single-user notebooks (to be retired)
│   │   ├── scripts/upload_garmin_tokens.sh # Dev-only fallback (writes tokens to wearable_credentials as _dev)
│   │   ├── schema.md
│   │   └── databricks.yml                  # Existing DABs bundle for Garmin ingestion jobs
│   ├── fitbit/  README.md                  # Contributor stubs
│   ├── whoop/   README.md
│   ├── oura/    README.md
│   ├── withings/ README.md
│   ├── strava/  README.md
│   └── samsung_health_cloud/README.md      # Explicit: no cloud API — use clients/samsungHealth
│
├── clients/                                # Mobile / watch client apps (phone-SDK pattern)
│   ├── healthKit/                          # iOS + Apple Watch — built
│   ├── androidHealthConnect/               # Android placeholder
│   └── samsungHealth/                      # Samsung placeholder
│
├── lakeflow/                               # Shared fan-out jobs across providers
│   ├── wearable_daily_fanout.ipynb         # Iterates wearable_credentials × registered ConnectorProtocol impls
│   ├── wearable_backfill_fanout.ipynb
│   └── README.md
│
└── zeroBus/
    ├── dbxW_zerobus_infra/                 # DABs bundle: schema, secret scope, SPN, warehouse, bronze table
    └── deploy.sh
```

## iOS App UI Architecture

The iOS app lives at `clients/healthKit/` and is a **demo tool** for showcasing Databricks ZeroBus ingestion through the phone-SDK client pattern. It uses Databricks branding and is designed for live presentations. It POSTs NDJSON to the AppKit gateway at `POST /api/wearable-core/ingest/apple_healthkit` — the same endpoint every other phone-SDK client uses.

### Navigation

Tab-based navigation with 4 tabs, plus a first-launch onboarding sheet:

| Tab | View | Purpose |
|-----|------|---------|
| Dashboard | `DashboardView` | Hero header, Sync Now button, per-category record count grid, recent activity feed |
| Data | `DataExplorerView` | Per-category list with drill-down to type breakdowns (samples by HK type, workouts by activity, etc.) |
| Payloads | `PayloadInspectorView` | Terminal-aesthetic NDJSON viewer showing last-sent payload per record type, metadata headers, copy-to-clipboard |
| About | `AboutView` | ZeroBus explanation, visual data flow diagram, HealthKit types list, permissions, settings, replay onboarding |

The **onboarding flow** (`OnboardingView`) is a 4-page swipeable sheet shown on first launch (tracked via `@AppStorage`). It explains ZeroBus, lists HealthKit data types sent, and requests HealthKit permissions. It can be re-triggered from the About tab.

### Theme System

All Databricks branding is centralized in `Theme/`:

- **`DBXTheme.swift`** — `DBXColors` (brand colors: `dbxRed` #FF3621, `dbxDarkTeal` #1B3139, `dbxNavy` #0D2228, `dbxOrange` #FF6A33, `dbxGreen` #00A972, light/dark adaptive grays), `DBXGradients` (primary red-to-orange, dark background), `DBXTypography` (heroTitle, sectionHeader, stat, mono), view modifiers (`.dbxCard()`, `.dbxGlassCard()`), and `DatabricksWordmark` (stylized "databricks" text placeholder — no external image assets)
- **`DBXButtonStyles.swift`** — `DBXPrimaryButtonStyle` (gradient + scale animation), `DBXSecondaryButtonStyle` (outlined)
- **`AccentColor`** asset set to #FF3621

### SyncLedger (Payload & Stats Persistence)

`SyncLedger` is a Swift `actor` that persists sent payloads and aggregation stats as JSON files in the app's Documents directory (`sync_ledger/`). It stores:

- **Last NDJSON payload** per record type (5 files: `last_payload_{type}.json`) — for the Payload Inspector
- **Cumulative stats** (`stats.json`) — total counts, breakdowns by HK type / activity type / sample type
- **Recent sync events** (`recent_events.json`) — last 20 events without payloads, for the Dashboard activity feed

`SyncCoordinator.postBatchWithRetry()` calls `syncLedger.recordSync(...)` after each successful POST, passing the NDJSON string (via `NDJSONSerializer.encodeToString()`) and request headers (via `APIService.buildRequestHeaders()`).

### MVVM Pattern

- **Views** observe `@StateObject` ViewModels and never call Services directly
- **ViewModels** are `@MainActor`, access Services through `AppDelegate` (via `UIApplication.shared.delegate`)
- **AppDelegate** owns `HealthKitManager` and `SyncCoordinator` (which owns `SyncLedger`)
- `dbxWearablesApp.swift` (`@main`) renders `MainTabView` and manages the onboarding sheet

## Development Workflow

### Branching Strategy

- **`main`** — stable, production-ready code
- Feature branches: `feature/<description>` or `claude/<description>`
- Always branch from `main` and open PRs back to `main`

### Setting Up Locally

```bash
# Clone the repository
git clone <repo-url>
cd dbxWearables

# Install Python dependencies (when requirements.txt exists)
pip install -r requirements.txt

# Configure Databricks CLI (if using Databricks Asset Bundles)
databricks configure
```

### Running Tests

No test framework is configured yet. When tests are added:
```bash
# Run all tests
pytest tests/

# Run unit tests only
pytest tests/unit/

# Run with coverage
pytest --cov=src tests/
```

### Deploying Pipelines

When Databricks Asset Bundles are configured:
```bash
# Validate bundle configuration
databricks bundle validate

# Deploy to target environment
databricks bundle deploy --target dev

# Run a pipeline
databricks bundle run <pipeline-name> --target dev
```

## Coding Conventions

### Python

- Follow PEP 8 style guidelines
- Use type hints for function signatures
- Use `snake_case` for variables, functions, and module names
- Use `PascalCase` for class names
- Use `UPPER_SNAKE_CASE` for constants
- Prefer f-strings for string formatting
- Keep functions focused and under 50 lines where practical

### SQL

- Use `UPPER CASE` for SQL keywords (`SELECT`, `FROM`, `WHERE`)
- Use `snake_case` for table and column names
- Prefix staging tables with `stg_`, intermediate with `int_`, final with `fct_` or `dim_`

### Spark / PySpark

- Prefer DataFrame API over RDD operations
- Use `spark.sql()` for complex SQL logic; use DataFrame API for programmatic transforms
- Always define schemas explicitly for ingested data — avoid `inferSchema=True` in production
- Partition large tables by date or another high-cardinality column

### Notebooks

- Use `# MAGIC` prefix for markdown cells in `.py` notebook files
- Keep notebooks focused on a single pipeline stage or analysis task
- Extract reusable logic into `src/` modules rather than duplicating across notebooks

### Pipeline Definitions

- Define Spark Declarative Pipelines using the `@dlt.table` or `@dlt.view` decorators
- Use expectations (`@dlt.expect`) for data quality checks
- Name pipeline tables to match the medallion architecture: `bronze_*`, `silver_*`, `gold_*`

## Data Architecture

This project follows the **medallion architecture**:

| Layer    | Purpose                              | Naming           |
|----------|--------------------------------------|------------------|
| Bronze   | Raw ingested data, minimal transform | `bronze_<source>`|
| Silver   | Cleaned, validated, deduplicated     | `silver_<entity>`|
| Gold     | Business-level aggregations          | `gold_<metric>`  |

### Bronze Table Design

The bronze layer uses a **key-value style** schema. The raw vendor or phone JSON payload is stored as a `VARIANT` column, preserving the full payload without imposing structure at ingestion time. Metadata columns provide context for lineage and debugging.

**Critical: HTTP request headers are captured in their own `VARIANT` column** — not discarded or merged into the body. Every producer (phone-SDK clients, Garmin webhook, Fitbit webhook, Lakeflow pull, …) sets the same contract:

| Header | Required | Description |
|--------|----------|-------------|
| `X-Platform` | yes | Provider identifier: `garmin_connect`, `garmin_connect_iq`, `fitbit`, `whoop`, `oura`, `withings`, `strava`, `apple_healthkit`, `google_health_connect`, `samsung_health` |
| `X-Record-Type` | yes | Vendor-specific record type (`daily_stats`, `sleep`, `workout`, `samples`, `deletes`, ...) |
| `X-Device-Id` | yes | Device identifier reported by the source |
| `X-User-Id` | yes | Platform-scoped UUID from `app_users` (empty string for dev `_dev` user only) |
| `X-Upload-Timestamp` | yes | ISO 8601 UTC upload time |
| `X-Provider-User-Id` | no | Vendor's user ID — useful for webhook-only paths where we resolve user from `wearable_credentials` |

`X-Record-Type` is the **primary mechanism** for distinguishing record kinds at bronze (delete records from regular records, workouts from daily summaries, etc.). Without it, silver would have to infer type from NDJSON schema — fragile and error-prone.

Bronze columns (provisioned by `zeroBus/dbxW_zerobus_infra`):

| Column | Type | Description |
|--------|------|-------------|
| `record_id` | `STRING NOT NULL` | Server-generated GUID (PK) |
| `ingested_at` | `TIMESTAMP` | Server-side ingestion timestamp |
| `body` | `VARIANT` | Raw vendor payload wrapped with source metadata (source, device_id, user_id, provider_user_id, data) |
| `headers` | `VARIANT` | HTTP request headers as JSON (full contract above) |
| `record_type` | `STRING` | Extracted from `X-Record-Type` header for fast filtering |

The bronze row is produced by the `wearable-core` plugin's `bronzeWriter` in a single place, so every source writes the exact same shape.

### Data Sources

Two integration patterns feed bronze:

1. **Cloud-API connector plugins** (`app/plugins/<provider>/`): Garmin (reference impl), Fitbit, Whoop, Oura, Withings, Strava. Each implements `WearableConnector` and registers into `AppKit.wearableCore.connectorRegistry`.
2. **Phone-SDK client apps** (`clients/`): Apple HealthKit (iOS app built), Google Health Connect (Android placeholder), Samsung Health (Samsung placeholder). Each POSTs NDJSON to `POST /api/wearable-core/ingest/:platform`.

## Important Notes for AI Assistants

1. **No secrets in code.** Never hardcode API keys, tokens, or credentials. Use Databricks secrets (`dbutils.secrets.get`) or environment variables.
2. **Schema-first approach.** Define explicit schemas (`StructType`) before ingesting data.
3. **Idempotent pipelines.** All pipeline stages should be safe to re-run without duplicating data.
4. **Test data quality.** Use DLT expectations or explicit assertions for data validation.
5. **Minimize notebook logic.** Put reusable code in `src/` Python modules; notebooks should orchestrate, not implement.
6. **Respect the medallion layers.** Don't skip from bronze to gold — transformations should flow through silver.
7. **Pin dependency versions.** In `requirements.txt`, always pin exact versions.
8. **Keep commits focused.** One logical change per commit with a clear message.
