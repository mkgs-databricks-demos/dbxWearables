# Session: dbxW_zerobus_infra Bundle Scaffold

**Date:** 2025-07-16
**Bundle:** `dbxW_zerobus_infra`
**Project:** dbxWearables-ZeroBus

## Summary

Scaffolded the `dbxW_zerobus_infra` Databricks Asset Bundle from scratch, using the existing `fhir_zerobus` solution (in `synthea-on-fhir/zerobus/`) as a reference architecture. This bundle manages shared infrastructure (secret scopes, UC elements, grants) that must be deployed before the primary `dbxW_zerobus` application bundle.

## Reference Analysis

Reviewed the complete FHIR ZeroBus solution to identify infrastructure-first resources:

| Resource | FHIR Location | Infra-First? |
| --- | --- | --- |
| Secret scope (`fhir_zerobus_credentials`) | `fhir_zerobus/resources/zerobus.secret_scope.yml` | Yes — moved to infra bundle |
| Bronze table DDL + grants | `fhir_zerobus/src/uc_setup/target-table-ddl.ipynb` | Yes — planned for infra |
| UC schema (assumed to exist) | Not declared | Yes — should be declarative |
| Volumes (planned, not implemented) | `fhir_zerobus_infra/README.md` only | Yes |
| Service principal permissions | Dynamic SQL in DDL notebook | Yes |

## Changes Made

### databricks.yml — Full rewrite

* **Variables:** `catalog`, `schema`, `secret_scope_name`, `client_id_dbs_key`, `run_as_user`, `higher_level_service_principal`, `zerobus_service_principal`, `serverless_environment_version`, `dashboard_embed_credentials`, plus 5 tag variables
* **`dev` target:** host `fevm-hls-fde.cloud.databricks.com`, catalog `hls_fde_dev`, schema `wearables`, run_as matthew.giglia
* **`hls_fde` target:** production mode, same workspace, catalog `hls_fde`, SP `acf021b4-...` (matching FHIR hls_fde target), full permissions block
* **`prod` target:** left as original placeholder skeleton

### resources/zerobus.secret_scope.yml — New file

* Databricks-managed backend, `prevent_destroy: true`
* Per-target permissions: dev (user MANAGE + SP READ), hls_fde (admin MANAGE + deploy SP MANAGE + zerobus SP READ), prod (same pattern)
* Header comments with CLI commands for populating secrets

### Earlier in session (prior context)

* Updated `dbxW_zerobus_infra/README.md` — rewritten to describe infra-first purpose
* Created `zeroBus/deploy.sh` — shared deployment orchestrator with `--infra`/`--app` flags

## Design Decisions

1. **Schema name `wearables`** — domain-oriented, not transport-oriented (avoided `zerobus`)
2. **Secret scope in infra, not app** — fixes the chicken-and-egg problem from the FHIR bundle where the scope was in the app bundle but needed before app startup
3. **SP values copied from FHIR `hls_fde`** — `acf021b4-87c6-44ff-b3d7-45c59d63fe4d` for both `higher_level_service_principal` and `zerobus_service_principal` (same SP in this workspace)
4. **`source_linked_deployment: false`** for all targets — matches FHIR pattern, avoids symlink issues

## Files Modified

| File | Action | Path |
| --- | --- | --- |
| `databricks.yml` | Rewritten | `zeroBus/dbxW_zerobus_infra/databricks.yml` |
| `zerobus.secret_scope.yml` | Created | `zeroBus/dbxW_zerobus_infra/resources/zerobus.secret_scope.yml` |
| `README.md` | Rewritten | `zeroBus/dbxW_zerobus_infra/README.md` |
| `deploy.sh` | Created | `zeroBus/deploy.sh` |

## Next Steps

* Add UC setup job + notebook for schema creation, bronze table DDL, and SP grants
* Add volume declarations as YAML resources
* Scaffold the primary `dbxW_zerobus` app bundle alongside this one
* Populate secrets via CLI after first deploy
