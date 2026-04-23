# deploy.sh Patch — Lakehouse Sync Views Gate Check

The following changes add a **Step 5** to `zeroBus/deploy.sh` that:
1. Checks if Lakehouse Sync has created the `lb_*_history` Delta tables in UC
2. If present, runs the `lakehouse_sync_views` job to create current-state views
3. If missing, prints an informational message (non-blocking)

## 1. Update header comment (line 7-8)

After:
```
#   3. Readiness checks    (all secret scope keys + bronze table + Lakebase status)
#   4. dbxW_zerobus        (AppKit app, pipelines, jobs) — when available
```
Add:
```
#   5. Lakehouse Sync views (post-deploy: creates current-state views if
#                            Lakehouse Sync history tables exist in UC)
```

## 2. Add --run-views usage example (after line 16)

After the `--app --skip-checks` example, add:
```bash
#   ./deploy.sh --target dev --run-views              # run Lakehouse Sync views job (post-deploy)
#   ./deploy.sh --target dev --app --run-views         # deploy app + create views if history tables exist
```

## 3. Add constants (after line 49, BRONZE_TABLE / UC_SETUP_JOB)

```bash
SYNC_VIEWS_JOB="lakehouse_sync_views"
SYNC_HISTORY_TABLES=("lb_load_test_runs_history" "lb_load_test_type_results_history")
```

## 4. Add RUN_VIEWS default (after RUN_SETUP=false, line 68)

```bash
RUN_VIEWS=false
```

## 5. Add --run-views flag parsing (in the case block, after --run-setup)

```bash
    --run-views)    RUN_VIEWS=true; shift ;;
```

## 6. Add --run-views to usage() output (after --run-setup line)

```
  --run-views        Run the Lakehouse Sync views job after app deployment.
```

## 7. Add display line in Main section (after "Skip checks" echo)

```bash
echo "  Run views:     ${RUN_VIEWS}"
```

## 8. Add the gate check function (after check_lakebase_status, before verify_infra_readiness)

```bash
# --------------------------------------------------------------------------- #
# check_and_run_sync_views — gate check + run Lakehouse Sync views job
#
# Checks if Lakehouse Sync has created the lb_*_history Delta tables.
# If all tables exist, runs the lakehouse_sync_views job to create
# current-state views. If any are missing, prints an informational
# message (non-blocking — the views can be created later).
# --------------------------------------------------------------------------- #
check_and_run_sync_views() {
  log "Checking for Lakehouse Sync history tables"

  # Resolve infra vars if not already done
  if [[ -z "${CATALOG}" ]]; then
    resolve_infra_vars
  fi

  local all_present=true
  for table_name in "${SYNC_HISTORY_TABLES[@]}"; do
    local full_table="${CATALOG}.${SCHEMA}.${table_name}"
    if databricks tables get "${full_table}" &>/dev/null; then
      ok "History table exists: ${full_table}"
    else
      warn "History table MISSING: ${full_table}"
      all_present=false
    fi
  done

  if [[ "${all_present}" == true ]]; then
    log "All history tables present — running Lakehouse Sync views job"
    local bundle_dir="${SCRIPT_DIR}/${INFRA_BUNDLE}"
    (cd "${bundle_dir}" && databricks bundle run "${SYNC_VIEWS_JOB}" --target "${TARGET}") || {
      warn "Lakehouse Sync views job failed. Views can be created manually later."
      warn "Run: databricks bundle run ${SYNC_VIEWS_JOB} --target ${TARGET}"
      return 0  # Non-fatal
    }
    ok "Lakehouse Sync views created successfully"
  else
    echo ""
    echo "  Lakehouse Sync history tables are not yet present in UC."
    echo "  This is expected if:"
    echo "    - The app hasn't been deployed yet"
    echo "    - No load test has been run (Lakebase tables don't exist yet)"
    echo "    - Lakehouse Sync hasn't been enabled in the Lakebase UI"
    echo ""
    echo "  After enabling Lakehouse Sync and running a load test, re-run:"
    echo "    ./deploy.sh --target ${TARGET} --run-views"
    echo "    # or: databricks bundle run ${SYNC_VIEWS_JOB} --target ${TARGET}"
    echo ""
  fi
}
```

## 9. Add Step 5 to Main flow (after Step 4: Deploy app bundle, before "Done.")

```bash
# Step 5: Create Lakehouse Sync views (post-deploy, gated on history table existence)
if [[ "${RUN_VIEWS}" == true ]] && [[ "${VALIDATE_ONLY}" != true ]] && [[ "${DESTROY}" != true ]]; then
  check_and_run_sync_views
fi
```
