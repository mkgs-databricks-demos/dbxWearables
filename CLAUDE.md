# CLAUDE.md

## Project Overview

**dbxWearables** is a Databricks solution for ingesting and analyzing wearable and health app data. It uses the Databricks ecosystem: AppKit, ZeroBus, Spark Declarative Pipelines, Lakebase, and AI/BI.

- **Owner:** MKG Solutions Databricks Demos
- **License:** MIT
- **Repository:** `mkgs-databricks-demos/dbxWearables`

## Current State

The project is in early development. What exists so far:
- `README.md` — project description
- `LICENSE` — MIT license
- `CLAUDE.md` — this file
- `dbxWearablesApp/` — iOS app scaffolding for Apple HealthKit integration (Swift/SwiftUI, MVVM architecture, with models, services, and test stubs)

Not yet created: Databricks-side source code (`src/`), pipeline definitions, notebooks, `databricks.yml`, `requirements.txt`, or CI/CD configuration. The Xcode project file (`.xcodeproj`) has not been generated yet — the Swift source files are in place and ready to be added to an Xcode project.

## Architecture

The initial implementation targets **Apple HealthKit** as the first data source. The end-to-end data flow is:

```
┌─────────────────┐     JSON POST     ┌──────────────────────────────────┐
│  Apple HealthKit │ ───────────────►  │  Databricks App (AppKit)         │
│  (Apple Watch /  │                   │  ┌────────────┐  ┌────────────┐ │
│   Health app)    │                   │  │  REST API   │─►│ ZeroBus SDK│ │
└─────────────────┘                   │  └────────────┘  └─────┬──────┘ │
                                       └────────────────────────┼────────┘
                                                                │ stream
                                                                ▼
                                       ┌────────────────────────────────┐
                                       │  Unity Catalog Bronze Table     │
                                       │  (key-value style, VARIANT)     │
                                       └───────────────┬────────────────┘
                                                       │ read
                                                       ▼
                                       ┌────────────────────────────────┐
                                       │  Spark Declarative Pipeline     │
                                       │  (silver → gold processing)     │
                                       └────────────────────────────────┘
```

### Component Responsibilities

1. **Apple HealthKit** — Source system. Apple Watch and apps that share data to Apple's Health app post standard activity measures as a JSON payload to the REST API.

2. **Databricks App (AppKit)** — Hosts a REST API endpoint that receives the HealthKit JSON POST. The app forwards the request payload and metadata (headers, etc.) to the ZeroBus SDK running within the same app process.

3. **ZeroBus SDK** — Streams the received data into a Unity Catalog bronze table. Decouples the REST API from table writes, providing streaming semantics without external infrastructure.

4. **Unity Catalog Bronze Table** — Schema-on-read storage. The full HealthKit JSON body is stored as a `VARIANT` column. Additional columns capture request metadata:
   - Record GUID
   - Record timestamp
   - Forwarded request headers
   - (Exact schema TBD)

5. **Spark Declarative Pipeline** — Reads from the bronze table and processes data through silver (cleaned/validated) and gold (aggregated) layers.

### Key Design Decisions

- **Schema-on-read at bronze** — Storing raw HealthKit JSON as `VARIANT` keeps ingestion flexible and avoids coupling intake to any specific HealthKit data structure.
- **Request metadata preserved** — HTTP headers and context travel alongside the payload for auditing, deduplication, and debugging.
- **ZeroBus as the bridge** — Decouples the REST API from table writes, providing streaming semantics without managing Kafka or similar infrastructure directly.
- **Apple HealthKit first** — The architecture is designed to start with HealthKit but can extend to other wearable sources (Fitbit, Garmin, etc.) by adding new ingestion endpoints that feed the same bronze table pattern.

## Technology Stack

- **AppKit** — Databricks application framework (hosts the REST API)
- **ZeroBus** — event/message bus for streaming data from the app to Unity Catalog
- **Spark Declarative Pipelines** (formerly Delta Live Tables / DLT) — ETL pipeline definitions
- **Unity Catalog** — data governance and storage; bronze table uses `VARIANT` type for raw JSON
- **Lakebase** — Databricks managed database (PostgreSQL-compatible)
- **AI/BI** — Databricks AI and BI dashboards/analytics
- **Apple HealthKit** — initial data source (wearable activity measures via JSON)
- **Language:** Python (primary), SQL (pipeline definitions and queries)
- **Platform:** Databricks on cloud (Azure, AWS, or GCP)

## Repository Structure

```
dbxWearables/
├── CLAUDE.md                              # This file — guidance for AI assistants
├── README.md                              # Project description
├── LICENSE                                # MIT license
│
├── dbxWearablesApp/                       # iOS app — Apple HealthKit integration
│   ├── .gitignore                         # Xcode/Swift-specific ignores
│   ├── dbxWearablesApp/                   # Main app source
│   │   ├── App/                           # App entry point, AppDelegate, Info.plist
│   │   ├── Configuration/                 # API endpoint and HealthKit type configs
│   │   ├── Models/                        # Codable structs (HealthSample, WorkoutRecord, etc.)
│   │   ├── Services/                      # HealthKitManager, QueryService, APIService, SyncCoordinator
│   │   ├── Repositories/                  # Sync state persistence, pending upload queue
│   │   ├── Views/                         # SwiftUI views (dashboard, permissions, settings)
│   │   ├── ViewModels/                    # MVVM view models
│   │   ├── Utilities/                     # Date formatters, HK extensions, Keychain, Logger
│   │   ├── Resources/                     # Asset catalog, localization
│   │   └── Entitlements/                  # HealthKit entitlements plist
│   ├── dbxWearablesAppTests/              # Unit tests (models, services, mocks)
│   └── dbxWearablesAppUITests/            # UI tests
│
└── (future directories below)
```

### Planned directories (Databricks side — create as the project grows)

```
dbxWearables/
├── src/                    # Python source code (Databricks side)
│   ├── pipelines/          # Spark Declarative Pipeline definitions
│   ├── ingestion/          # ZeroBus consumers, AppKit REST API handler
│   ├── transforms/         # Data transformation logic
│   ├── models/             # Data models / schema definitions
│   └── app/                # Databricks AppKit application code
├── notebooks/              # Databricks notebooks (.py or .sql)
├── tests/                  # Python unit and integration tests
│   ├── unit/
│   └── integration/
├── config/                 # Environment and pipeline configuration
├── dashboards/             # AI/BI dashboard definitions
├── resources/              # Static resources, sample data, schemas
├── databricks.yml          # Databricks Asset Bundle configuration
└── requirements.txt        # Python dependencies
```

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

The bronze layer uses a **key-value style** schema. The raw HealthKit JSON POST body is stored as a `VARIANT` column, preserving the full payload without imposing structure at ingestion time. Metadata columns provide context for lineage and debugging.

**Critical: HTTP request headers must be captured in their own `VARIANT` column** — not discarded or merged into the body. The iOS app sends an `X-Record-Type` header with every POST that identifies the kind of payload:

| `X-Record-Type` value | Payload contents |
|------------------------|------------------|
| `samples`              | HealthKit quantity/category samples |
| `workouts`             | Workout records |
| `sleep`                | Sleep session records |
| `activity_summaries`   | Daily activity ring summaries |
| `deletes`              | Deletion records (uuid + sample_type only) |

This header is the **primary mechanism** for distinguishing delete records from regular records at the bronze layer. Without it, the pipeline would have to inspect each NDJSON line's schema to infer its type — fragile and error-prone. Other headers (`X-Device-Id`, `X-Platform`, `X-App-Version`, `X-Upload-Timestamp`) are also valuable for auditing and deduplication.

Preliminary column sketch (exact definitions TBD):

| Column | Type | Description |
|--------|------|-------------|
| `record_id` | `STRING` | Server-generated GUID |
| `ingested_at` | `TIMESTAMP` | Server-side ingestion timestamp |
| `body` | `VARIANT` | Raw NDJSON line (one row per line) |
| `headers` | `VARIANT` | Full HTTP request headers as JSON |
| `record_type` | `STRING` | Extracted from `X-Record-Type` header for fast filtering |

### Data Sources

- **Apple HealthKit** (initial) — standard activity measures from Apple Watch and Health app, delivered as JSON via REST API
- Future: other wearable APIs (Fitbit, Garmin, etc.) and health app exports (CSV, JSON, XML)

## Important Notes for AI Assistants

1. **No secrets in code.** Never hardcode API keys, tokens, or credentials. Use Databricks secrets (`dbutils.secrets.get`) or environment variables.
2. **Schema-first approach.** Define explicit schemas (`StructType`) before ingesting data.
3. **Idempotent pipelines.** All pipeline stages should be safe to re-run without duplicating data.
4. **Test data quality.** Use DLT expectations or explicit assertions for data validation.
5. **Minimize notebook logic.** Put reusable code in `src/` Python modules; notebooks should orchestrate, not implement.
6. **Respect the medallion layers.** Don't skip from bronze to gold — transformations should flow through silver.
7. **Pin dependency versions.** In `requirements.txt`, always pin exact versions.
8. **Keep commits focused.** One logical change per commit with a clear message.
