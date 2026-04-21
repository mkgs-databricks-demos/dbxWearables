# ZeroBus

Databricks-side ingestion infrastructure and application for the **dbxWearables** project. This folder hosts all ZeroBus-related bundles, deployment scripts, and configuration for streaming wearable health data into Unity Catalog.

## Architecture

```
zeroBus/
├── deploy.sh                  # Shared deployment script (infra-first ordering)
├── dbxW_zerobus_infra/        # Infrastructure bundle (schemas, secrets, SPN, warehouse, DDL)
└── dbxW_zerobus_app/          # Application bundle (AppKit app, ZeroBus SDK streaming, pipelines)
```

### Data Flow

```
Client App (HealthKit, Android Health Connect, etc.)
  → Databricks App (AppKit REST API)                   ← dbxW_zerobus_app
    ├─ ZeroBus SDK stream pool → UC Bronze Table        ← persistent gRPC streams
    │    → Spark Declarative Pipeline (silver → gold)   ← dbxW_zerobus_app (planned)
    └─ Lakebase (Postgres) → app state                  ← dbxW_zerobus_infra creates the project
```

The AppKit application uses the **ZeroBus Ingest SDK** (`@databricks/zerobus-ingest-sdk`) with a persistent gRPC stream pool for high-throughput ingestion. Each stream is an independent connection with SDK-managed OAuth, offset-based durability (`waitForOffset`), and automatic recovery. The pool size is configurable per-target via bundle variables.

## Bundles

| Bundle | Purpose | Status |
| --- | --- | --- |
| [`dbxW_zerobus_infra`](dbxW_zerobus_infra/README.md) | Shared infrastructure — UC schema, secret scope, SQL warehouse, service principal, bronze table DDL, Lakebase project | Active |
| [`dbxW_zerobus_app`](dbxW_zerobus_app/README.md) | Application — AppKit REST API, ZeroBus SDK stream pool, Lakebase CRUD, post-deploy tagging, Spark Declarative Pipelines | Active |

Infrastructure must be deployed **before** the application bundle. Use `deploy.sh` to handle ordering automatically:

```bash
./deploy.sh --target dev            # deploys infra first, then app
./deploy.sh --target dev --infra    # deploy only infra bundle
./deploy.sh --target dev --app      # deploy only app bundle (with readiness checks)
./deploy.sh --target dev --run-setup # infra + UC setup job + app
```

## Documentation

* [dbxWearables project README](../README.md)
* [Infrastructure bundle README](dbxW_zerobus_infra/README.md)
* [Application bundle README](dbxW_zerobus_app/README.md)
* [ZeroBus Ingest overview](https://docs.databricks.com/aws/en/ingestion/zerobus-overview/)
* [ZeroBus Ingest SDK](https://github.com/databricks/zerobus-sdk)
* [ZeroBus Ingest connector](https://docs.databricks.com/aws/en/ingestion/zerobus-ingest/)
