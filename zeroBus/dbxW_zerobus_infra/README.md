# dbxW_zerobus_infra

Shared infrastructure bundle for the **dbxWearables ZeroBus** solution. This Databricks Asset Bundle provisions foundational resources — secret scopes, Unity Catalog schemas, volumes, and other shared elements — that must exist **before** the primary ZeroBus application bundle (or any other zeroBus-dependent bundle) is deployed.

## Relationship to dbxWearables

The [dbxWearables](../../README.md) project ingests wearable and health app data into Databricks using AppKit, ZeroBus, Spark Declarative Pipelines, Lakebase, and AI/BI. The end-to-end flow is:

```
Client App (HealthKit, etc.)
  → Databricks App (AppKit REST API)
    → ZeroBus SDK → Unity Catalog Bronze Table
      → Spark Declarative Pipeline (silver → gold)
```

This infrastructure bundle sits at the base of that stack. It creates the shared catalog objects and secrets that the AppKit application, ZeroBus streaming layer, and downstream pipelines all depend on.

## What This Bundle Manages

| Resource Type | Examples | Purpose |
| --- | --- | --- |
| Secret Scopes | API keys, service credentials | Secure storage for secrets consumed by the AppKit app and pipelines |
| Unity Catalog Schemas | Bronze/silver/gold schemas | Namespace isolation for medallion-layer tables |
| Unity Catalog Volumes | Landing zones, artifacts | Managed storage for raw uploads and pipeline artifacts |
| Grants / Permissions | Schema and volume grants | Access control for service principals and user groups |

> **Note:** The exact resource list will grow as the solution matures. This bundle should remain limited to **shared, environment-level infrastructure** — application-specific resources (jobs, pipelines, serving endpoints) belong in the primary ZeroBus bundle.

## Deployment Order

Infrastructure resources must be deployed **first**, before any dependent bundle:

```
1. dbxW_zerobus_infra   ← this bundle (schemas, secrets, volumes, grants)
2. dbxW_zerobus          ← primary bundle (AppKit app, pipelines, jobs) — coming soon
```

Use the shared [`deploy.sh`](../deploy.sh) script in the parent `zeroBus/` directory to deploy bundles in the correct order.

## Targets

| Target | Mode | Workspace | Default |
| --- | --- | --- | --- |
| `dev` | development | `fevm-hls-fde.cloud.databricks.com` | Yes |
| `prod` | production | `fevm-hls-fde.cloud.databricks.com` | No |

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

### Managing Resources

- Use the **Deployments** panel (rocket icon 🚀) in the workspace to deploy and run resources interactively.
- Use the **Add** dropdown to add new resource YAML files under `resources/`.
- Click **Schedule** on a notebook to create a job definition.

## Documentation

- [Declarative Automation Bundles in the workspace](https://docs.databricks.com/aws/en/dev-tools/bundles/workspace-bundles)
- [Bundle Configuration Reference](https://docs.databricks.com/aws/en/dev-tools/bundles/reference)
