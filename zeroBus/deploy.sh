#!/usr/bin/env bash
# deploy.sh — Shared deployment script for the dbxWearables ZeroBus solution.
#
# Deploys Databricks Asset Bundles in dependency order:
#   1. dbxW_zerobus_infra  (secret scopes, UC schemas, SQL warehouses, Lakebase)
#   2. UC setup job        (SPN creation, secret provisioning, table DDL)
#   3. Readiness checks    (all secret scope keys + bronze table + Lakebase status)
#   4. dbxW_zerobus_app    (AppKit app, pipelines, jobs)
#
# Usage:
#   ./deploy.sh --target dev                          # deploy all bundles (with readiness checks)
#   ./deploy.sh --target dev --run-setup              # deploy infra + run UC setup job + app
#   ./deploy.sh --target dev --infra                  # deploy only the infra bundle
#   ./deploy.sh --target dev --infra --run-setup      # deploy infra + run UC setup job
#   ./deploy.sh --target dev --app                    # deploy only the app bundle (with checks)
#   ./deploy.sh --target dev --app --skip-checks      # deploy app without readiness checks
#   ./deploy.sh --target dev --validate               # validate only, no deploy
#   ./deploy.sh --target dev --destroy                # destroy deployed resources
#
# Infrastructure Readiness Checks (gate before app bundle deploy):
#   Secret scope keys — all 8 must be present:
#     Auto-provisioned:  {client_id_dbs_key}, workspace_url, zerobus_endpoint, target_table_name,
#                        jwt_signing_secret, apple_bundle_id, ios_spn_application_id
#     Admin-provisioned: {client_secret_dbs_key}
#   Key names are schema-qualified in dev/hls_fde targets (e.g. client_id_wearables).
#   Bronze table — wearables_zerobus must exist in the target catalog.schema
#   Lakebase project — informational; notes Data API status (optional, not required for AppKit)
#
# iOS Bootstrap SPN permissions:
#   After readiness checks pass, deploy.sh reads the iOS SPN application_id
#   from the secret scope and passes it as --var ios_bootstrap_spn_id=<value>
#   to the app bundle deploy. This grants CAN_USE on the app declaratively.
#
# Requirements:
#   - Databricks CLI installed and authenticated (databricks auth login)
#   - python3 (for JSON parsing of CLI output)

set -euo pipefail

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_BUNDLE="dbxW_zerobus_infra"
APP_BUNDLE="dbxW_zerobus_app"

# Infrastructure readiness — expected secret scope keys.
# The client_id and client_secret key names are schema-qualified and resolved
# at runtime by resolve_infra_vars() from the bundle summary variables
# (client_id_dbs_key, client_secret_dbs_key). The arrays below are
# populated after resolution; see build_key_arrays().
REQUIRED_SCOPE_KEYS=()
AUTO_PROVISIONED_KEYS=()
ADMIN_PROVISIONED_KEYS=()
BRONZE_TABLE="wearables_zerobus"
UC_SETUP_JOB="wearables_uc_setup"

# Resolved at runtime by resolve_infra_vars()
SCOPE_NAME=""
CATALOG=""
SCHEMA=""
CLIENT_ID_DBS_KEY=""
CLIENT_SECRET_DBS_KEY=""
IOS_BOOTSTRAP_CLIENT_SECRET_KEY=""
LAKEBASE_PROJECT_ID=""

# Resolved at runtime after readiness checks — iOS SPN application_id
# for the app bundle's permissions block (passed via --var override).
IOS_BOOTSTRAP_SPN_ID=""

# --------------------------------------------------------------------------- #
# Defaults
# --------------------------------------------------------------------------- #
TARGET=""
DEPLOY_INFRA=true
DEPLOY_APP=true
VALIDATE_ONLY=false
DESTROY=false
RUN_SETUP=false
SKIP_CHECKS=false

# --------------------------------------------------------------------------- #
# Usage
# --------------------------------------------------------------------------- #
usage() {
  cat <<EOF
Usage: $(basename "$0") --target <target> [OPTIONS]

Options:
  --target <name>    Required. Bundle target (dev, hls_fde, prod).
  --infra            Deploy only the infrastructure bundle.
  --app              Deploy only the application bundle (skip infra).
  --run-setup        Run the UC setup job after deploying the infra bundle.
  --skip-checks      Skip infrastructure readiness checks before app deploy.
  --validate         Validate bundles without deploying.
  --destroy          Destroy deployed resources for the target.
  -h, --help         Show this help message.

Deployment order:
  1. ${INFRA_BUNDLE}   — shared infrastructure (schema, scope, warehouse, Lakebase)
  2. UC setup job       — SPN creation, secret provisioning, table DDL
  3. Readiness checks   — verifies all secret keys + bronze table + Lakebase project
  4. ${APP_BUNDLE}      — application (AppKit app, pipelines)

First deployment:
  ./deploy.sh --target dev --run-setup
  # Then: admin provisions client_secret (see README)
  ./deploy.sh --target dev --app
EOF
  exit 0
}

# --------------------------------------------------------------------------- #
# Parse arguments
# --------------------------------------------------------------------------- #
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)       TARGET="$2"; shift 2 ;;
    --infra)        DEPLOY_INFRA=true;  DEPLOY_APP=false; shift ;;
    --app)          DEPLOY_INFRA=false; DEPLOY_APP=true;  shift ;;
    --run-setup)    RUN_SETUP=true; shift ;;
    --skip-checks)  SKIP_CHECKS=true; shift ;;
    --validate)     VALIDATE_ONLY=true; shift ;;
    --destroy)      DESTROY=true; shift ;;
    -h|--help)      usage ;;
    *)              echo "Error: Unknown option '$1'"; usage ;;
  esac
done

if [[ -z "${TARGET}" ]]; then
  echo "Error: --target is required."
  usage
fi

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
log()  { echo -e "\n\033[1;34m==>\033[0m \033[1m$1\033[0m"; }
warn() { echo -e "\033[1;33m  ⚠  $1\033[0m"; }
ok()   { echo -e "\033[1;32m  ✓  $1\033[0m"; }
fail() { echo -e "\033[1;31m  ✗  $1\033[0m"; exit 1; }

# --------------------------------------------------------------------------- #
# Prerequisites
# --------------------------------------------------------------------------- #
command -v databricks &>/dev/null || fail "Databricks CLI not found. Install: https://docs.databricks.com/dev-tools/cli/install.html"
command -v python3    &>/dev/null || fail "python3 not found (required for JSON parsing)."

# --------------------------------------------------------------------------- #
# deploy_bundle — validate and deploy (or destroy) a single bundle
#
# Usage: deploy_bundle <bundle_name> [extra_deploy_args...]
#   Extra args (e.g. --var key=value) are passed to `bundle deploy` only.
# --------------------------------------------------------------------------- #
deploy_bundle() {
  local bundle_name="$1"
  shift
  local extra_args=("$@")
  local bundle_dir="${SCRIPT_DIR}/${bundle_name}"

  if [[ ! -d "${bundle_dir}" ]]; then
    warn "Bundle directory '${bundle_name}' does not exist yet — skipping."
    return 0
  fi

  if [[ ! -f "${bundle_dir}/databricks.yml" ]]; then
    warn "No databricks.yml found in '${bundle_name}' — skipping."
    return 0
  fi

  log "Validating ${bundle_name} (target: ${TARGET})"
  (cd "${bundle_dir}" && databricks bundle validate --target "${TARGET}")
  ok "Validation passed: ${bundle_name}"

  if [[ "${VALIDATE_ONLY}" == true ]]; then
    return 0
  fi

  if [[ "${DESTROY}" == true ]]; then
    log "Destroying ${bundle_name} (target: ${TARGET})"
    (cd "${bundle_dir}" && databricks bundle destroy --target "${TARGET}" --auto-approve)
    ok "Destroyed: ${bundle_name}"
  else
    log "Deploying ${bundle_name} (target: ${TARGET})"
    if [[ ${#extra_args[@]} -gt 0 ]]; then
      (cd "${bundle_dir}" && databricks bundle deploy --target "${TARGET}" "${extra_args[@]}")
    else
      (cd "${bundle_dir}" && databricks bundle deploy --target "${TARGET}")
    fi
    ok "Deployed: ${bundle_name}"
  fi
}

# --------------------------------------------------------------------------- #
# resolve_infra_vars — extract scope name, catalog, schema, secret key names,
#                      and Lakebase project ID from the infra bundle summary
# --------------------------------------------------------------------------- #
resolve_infra_vars() {
  local bundle_dir="${SCRIPT_DIR}/${INFRA_BUNDLE}"

  log "Resolving infrastructure variables (target: ${TARGET})"

  local summary_json
  summary_json=$(cd "${bundle_dir}" && databricks bundle summary --target "${TARGET}" --output json 2>&1) || {
    fail "Could not read bundle summary for ${INFRA_BUNDLE}.\n" \
         "  Deploy the infra bundle first:\n" \
         "    cd ${bundle_dir} && databricks bundle deploy --target ${TARGET}"
  }

  # Parse resolved values with python3.
  # Tries the schema resource first (authoritative), falls back to variables.
  eval "$(echo "${summary_json}" | python3 -c "
import sys, json

try:
    data = json.load(sys.stdin)
except json.JSONDecodeError as e:
    print(f'RESOLVE_ERROR=\"JSON parse error: {e}\"', flush=True)
    sys.exit(0)

vars_block = data.get('variables', {})

def get_var(name, default=''):
    v = vars_block.get(name, {})
    if isinstance(v, dict):
        return v.get('value', default)
    return str(v) if v else default

# --- secret_scope_name ---
scope = get_var('secret_scope_name')

# --- client_id_dbs_key and client_secret_dbs_key ---
client_id_key    = get_var('client_id_dbs_key', 'client_id')
client_secret_key = get_var('client_secret_dbs_key', 'client_secret')

# --- catalog and schema (prefer resource, fall back to variable) ---
catalog = ''
schema  = ''
resources = data.get('resources', {})
schemas_block = resources.get('schemas', {})
for schema_name, ws in schemas_block.items():
    if isinstance(ws, dict):
        catalog = ws.get('catalog_name', '')
        schema  = ws.get('name', '')

# Fallback to variables if resources didn't resolve
if not catalog:
    catalog = get_var('catalog')
if not schema:
    schema = get_var('schema')

# --- lakebase_project_id (from postgres_projects resource) ---
project_id = ''
pg_projects = resources.get('postgres_projects', {})
for proj_name, proj in pg_projects.items():
    if isinstance(proj, dict):
        project_id = proj.get('project_id', '')
        if project_id:
            break

# Sanitise for shell eval safety (strip anything not alphanumeric/underscore/dash/dot)
import re
def safe(v):
    return re.sub(r'[^a-zA-Z0-9_.\-]', '', str(v))

print(f'SCOPE_NAME=\"{safe(scope)}\"')
print(f'CATALOG=\"{safe(catalog)}\"')
print(f'SCHEMA=\"{safe(schema)}\"')
print(f'CLIENT_ID_DBS_KEY=\"{safe(client_id_key)}\"')
print(f'CLIENT_SECRET_DBS_KEY=\"{safe(client_secret_key)}\"')

# iOS bootstrap SPN client secret key (schema-qualified)
ios_bootstrap_secret_key = variables.get('ios_bootstrap_client_secret_key', {})
ios_bootstrap_secret_key = ios_bootstrap_secret_key.get('value', ios_bootstrap_secret_key.get('default', 'ios_bootstrap_client_secret'))
print(f'IOS_BOOTSTRAP_CLIENT_SECRET_KEY=\"{safe(ios_bootstrap_secret_key)}\"')
print(f'LAKEBASE_PROJECT_ID=\"{safe(project_id)}\"')
" 2>/dev/null)" || fail "Could not parse bundle summary JSON."

  # Check for parse error forwarded from python
  if [[ -n "${RESOLVE_ERROR:-}" ]]; then
    fail "Bundle summary parse error: ${RESOLVE_ERROR}"
  fi

  [[ -n "${SCOPE_NAME}" ]]          || fail "Could not resolve secret_scope_name from bundle summary."
  [[ -n "${CATALOG}" ]]             || fail "Could not resolve catalog from bundle summary."
  [[ -n "${SCHEMA}" ]]              || fail "Could not resolve schema from bundle summary."
  [[ -n "${CLIENT_ID_DBS_KEY}" ]]   || fail "Could not resolve client_id_dbs_key from bundle summary."
  [[ -n "${CLIENT_SECRET_DBS_KEY}" ]] || fail "Could not resolve client_secret_dbs_key from bundle summary."

  ok "Secret scope:        ${SCOPE_NAME}"
  ok "Catalog:             ${CATALOG}"
  ok "Schema:              ${SCHEMA}"
  ok "Client ID key:       ${CLIENT_ID_DBS_KEY}"
  ok "Client secret key:   ${CLIENT_SECRET_DBS_KEY}"
  ok "iOS SPN secret key: ${IOS_BOOTSTRAP_CLIENT_SECRET_KEY}"

  if [[ -n "${LAKEBASE_PROJECT_ID}" ]]; then
    ok "Lakebase project:    ${LAKEBASE_PROJECT_ID}"
  else
    warn "No Lakebase project found in bundle resources (may not be deployed yet)."
  fi

  # Build the key arrays now that we have the resolved names
  build_key_arrays
}

# --------------------------------------------------------------------------- #
# build_key_arrays — populate REQUIRED / AUTO / ADMIN key arrays from the
#                    resolved client_id_dbs_key and client_secret_dbs_key.
#                    Auth keys (jwt_signing_secret, apple_bundle_id,
#                    ios_spn_application_id) use fixed names (not schema-qualified).
# --------------------------------------------------------------------------- #
build_key_arrays() {
  AUTO_PROVISIONED_KEYS=("${CLIENT_ID_DBS_KEY}" workspace_url zerobus_endpoint target_table_name jwt_signing_secret apple_bundle_id ios_spn_application_id)
  ADMIN_PROVISIONED_KEYS=("${CLIENT_SECRET_DBS_KEY}" "${IOS_BOOTSTRAP_CLIENT_SECRET_KEY}")
  REQUIRED_SCOPE_KEYS=("${AUTO_PROVISIONED_KEYS[@]}" "${ADMIN_PROVISIONED_KEYS[@]}")
}

# --------------------------------------------------------------------------- #
# run_uc_setup — run the UC setup job via the bundle CLI
# --------------------------------------------------------------------------- #
run_uc_setup() {
  local bundle_dir="${SCRIPT_DIR}/${INFRA_BUNDLE}"

  log "Running UC setup job: ${UC_SETUP_JOB} (target: ${TARGET})"
  (cd "${bundle_dir}" && databricks bundle run "${UC_SETUP_JOB}" --target "${TARGET}") || \
    fail "UC setup job failed. Check the Databricks Jobs UI for details."
  ok "UC setup job completed successfully"
}

# --------------------------------------------------------------------------- #
# check_lakebase_status — informational check for Lakebase project health
#                         and Data API status
#
# The Data API (PostgREST sidecar) is OPTIONAL — AppKit's Lakebase plugin
# connects via direct Postgres wire protocol (port 5432), not the Data API.
# The Data API is useful for external REST clients, browsers, or tools
# without a Postgres driver.
#
# This function:
#   1. Verifies the Lakebase project exists and is accessible
#   2. Lists endpoints on the production branch to confirm compute is active
#   3. Attempts to detect Data API enablement from endpoint settings
#   4. Reports status informatively (does not block deployment)
#
# This is an INFORMATIONAL check — it never fails the deployment.
# --------------------------------------------------------------------------- #
check_lakebase_status() {
  local project_id="${LAKEBASE_PROJECT_ID:-}"
  if [[ -z "${project_id}" ]]; then
    return 0  # No Lakebase project in this bundle — nothing to check
  fi

  log "Checking Lakebase project status (project: ${project_id})"

  # Verify the project is accessible
  local project_json
  project_json=$(databricks postgres get-project "projects/${project_id}" --output json 2>/dev/null) || {
    warn "Lakebase project '${project_id}' not found or not accessible."
    warn "If the project was just created, it may still be initializing."
    return 0
  }
  ok "Lakebase project exists: ${project_id}"

  # List endpoints on the production branch
  local endpoints_json
  endpoints_json=$(databricks postgres list-endpoints "projects/${project_id}/branches/production" --output json 2>/dev/null) || {
    warn "Could not list endpoints for project '${project_id}' branch 'production'."
    warn "The branch or endpoint may still be initializing."
    return 0
  }

  # Attempt to detect Data API enablement from endpoint settings.
  # The API response shape is not fully documented — we check several
  # plausible field locations and fall back to "unknown" gracefully.
  local data_api_status
  data_api_status=$(echo "${endpoints_json}" | python3 -c "
import sys, json

try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError):
    print('unknown')
    sys.exit(0)

endpoints = data.get('endpoints', data.get('items', []))
if isinstance(data, list):
    endpoints = data

for ep in endpoints:
    if not isinstance(ep, dict):
        continue
    settings = ep.get('settings', {})
    # Check known and plausible field locations
    if settings.get('data_api_enabled'):
        print('enabled')
        sys.exit(0)
    if settings.get('data_api', {}).get('enabled'):
        print('enabled')
        sys.exit(0)
    if ep.get('data_api_enabled'):
        print('enabled')
        sys.exit(0)
    # Check for data_api_url presence as indirect evidence
    if ep.get('data_api_url') or settings.get('data_api_url'):
        print('enabled')
        sys.exit(0)

print('unknown')
" 2>/dev/null) || data_api_status="unknown"

  if [[ "${data_api_status}" == "enabled" ]]; then
    ok "Lakebase Data API is enabled (optional — for external REST clients)"
  else
    ok "Lakebase compute endpoint is running"
    echo "  Note: Data API status could not be confirmed. This is optional —"
    echo "  AppKit connects via direct Postgres wire protocol, not the Data API."
    echo "  To enable the Data API for external REST access:"
    echo "    Lakebase App → project '${project_id}' → Data API → 'Enable Data API'"
  fi
}

# --------------------------------------------------------------------------- #
# read_ios_spn_id — read the iOS Bootstrap SPN application_id from the
#                   secret scope. Used as --var override for the app bundle's
#                   permissions block (grants CAN_USE on the app).
#
# Sets IOS_BOOTSTRAP_SPN_ID global variable. Non-fatal — warns on failure.
# --------------------------------------------------------------------------- #
read_ios_spn_id() {
  log "Reading iOS Bootstrap SPN application_id from secret scope"

  IOS_BOOTSTRAP_SPN_ID=$(databricks secrets get-secret "${SCOPE_NAME}" ios_spn_application_id --output json 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('value',''))" 2>/dev/null) || IOS_BOOTSTRAP_SPN_ID=""

  if [[ -n "${IOS_BOOTSTRAP_SPN_ID}" ]]; then
    ok "iOS Bootstrap SPN ID: ${IOS_BOOTSTRAP_SPN_ID:0:8}..."
  else
    warn "Could not read iOS Bootstrap SPN application_id from scope."
    warn "App bundle permissions will not include the iOS SPN grant."
    warn "The app will still deploy, but the iOS SPN won't have CAN_USE."
  fi
}

# --------------------------------------------------------------------------- #
# verify_infra_readiness — gate check before app bundle deployment
#
# Checks:
#   1. Secret scope exists and contains all 8 required keys
#      (key names are schema-qualified, resolved from bundle variables)
#   2. Bronze table wearables_zerobus exists in catalog.schema
#   3. Lakebase project status (informational — does not block deploy)
#
# Exit behaviour:
#   - Missing auto-provisioned keys or table → fail with "run UC setup" message
#   - Missing admin-provisioned key only     → fail with admin instructions
#   - Lakebase status unknown                → info note (non-blocking)
#   - All present                            → return 0
# --------------------------------------------------------------------------- #
verify_infra_readiness() {
  log "Verifying infrastructure readiness"

  local check_failed=false

  # ---- 1. Secret scope keys -----------------------------------------------
  # NOTE: CLI uses positional arg for scope, not --scope flag
  local secrets_json
  secrets_json=$(databricks secrets list-secrets "${SCOPE_NAME}" --output json 2>/dev/null) || {
    echo ""
    echo "  Secret scope '${SCOPE_NAME}' not found or not accessible."
    echo "  The UC setup job must run first to create the SPN and populate secrets:"
    echo ""
    echo "    databricks bundle run ${UC_SETUP_JOB} --target ${TARGET}"
    echo "    # or: ./deploy.sh --target ${TARGET} --run-setup"
    echo ""
    fail "Secret scope '${SCOPE_NAME}' does not exist."
  }

  # Extract the list of key names present in the scope
  local present_keys
  present_keys=$(echo "${secrets_json}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
# Handle both {"secrets": [...]} (old CLI) and direct array [...] (new CLI)
items = data.get('secrets', data) if isinstance(data, dict) else data
for s in items:
    if isinstance(s, dict):
        print(s.get('key', ''))
" 2>/dev/null) || fail "Could not parse secrets list from scope '${SCOPE_NAME}'."

  local missing_auto=()
  local missing_admin=()

  for key in "${REQUIRED_SCOPE_KEYS[@]}"; do
    if echo "${present_keys}" | grep -qx "${key}"; then
      ok "Secret key present: ${key}"
    else
      # Classify as auto-provisioned or admin-provisioned
      local is_admin=false
      for admin_key in "${ADMIN_PROVISIONED_KEYS[@]}"; do
        [[ "${key}" == "${admin_key}" ]] && is_admin=true
      done

      if [[ "${is_admin}" == true ]]; then
        missing_admin+=("${key}")
      else
        missing_auto+=("${key}")
      fi
      warn "Secret key MISSING: ${key}"
    fi
  done

  # ---- 2. Bronze table existence ------------------------------------------
  local full_table="${CATALOG}.${SCHEMA}.${BRONZE_TABLE}"
  local table_missing=false

  if databricks tables get "${full_table}" &>/dev/null; then
    ok "Table exists: ${full_table}"
  else
    warn "Table MISSING: ${full_table}"
    table_missing=true
  fi

  # ---- 3. Lakebase project status (informational) -------------------------
  check_lakebase_status

  # ---- 4. Evaluate results ------------------------------------------------

  # Auto-provisioned resources missing → UC setup job hasn't been run (or failed)
  if [[ ${#missing_auto[@]} -gt 0 ]] || [[ "${table_missing}" == true ]]; then
    echo ""
    echo "  ============================================================="
    echo "  Auto-provisioned resources are missing."
    echo "  The UC setup job must be run before deploying the app bundle."
    echo "  ============================================================="
    echo ""
    [[ ${#missing_auto[@]} -gt 0 ]] && echo "  Missing secret keys: ${missing_auto[*]}"
    [[ "${table_missing}" == true ]] && echo "  Missing table:       ${full_table}"
    echo ""
    echo "  Run the UC setup job:"
    echo "    databricks bundle run ${UC_SETUP_JOB} --target ${TARGET}"
    echo "    # or: ./deploy.sh --target ${TARGET} --run-setup"
    echo ""
    fail "Infrastructure readiness check failed (auto-provisioned resources missing)."
  fi

  # Admin-provisioned key missing → admin action required
  if [[ ${#missing_admin[@]} -gt 0 ]]; then
    echo ""
    echo "  ============================================================="
    echo "  ACTION REQUIRED: An admin must provision the client secret."
    echo "  ============================================================="
    echo ""
    echo "  All auto-provisioned resources are present, but the OAuth"
    echo "  client secret has not been stored in the secret scope yet."
    echo "  Expected key name: ${CLIENT_SECRET_DBS_KEY}"
    echo ""
    echo "  1. Generate an OAuth secret for the ZeroBus service principal:"
    echo "     • Workspace UI:  Settings > Identity and access > Service principals"
    echo "                      > Select the ZeroBus SPN > Secrets > Generate secret"
    echo "     • Databricks CLI: databricks account service-principal-secrets create <sp_id>"
    echo ""
    echo "  2. Store it in the secret scope:"
    echo "     databricks secrets put-secret ${SCOPE_NAME} ${CLIENT_SECRET_DBS_KEY} \\"
    echo '       --string-value "<secret>"'
    echo ""
    echo "  Use --skip-checks to deploy the app bundle without this key."
    echo ""
    fail "Infrastructure readiness check failed (admin-provisioned secret missing)."
  fi

  echo ""
  ok "All infrastructure readiness checks passed"
}

# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
log "dbxWearables ZeroBus — Bundle Deployment"
echo "  Target:        ${TARGET}"
echo "  Infra bundle:  ${DEPLOY_INFRA}"
echo "  App bundle:    ${DEPLOY_APP}"
echo "  Run setup:     ${RUN_SETUP}"
echo "  Skip checks:   ${SKIP_CHECKS}"
echo "  Validate only: ${VALIDATE_ONLY}"
echo "  Destroy:       ${DESTROY}"

# Step 1: Deploy infra bundle
if [[ "${DEPLOY_INFRA}" == true ]]; then
  deploy_bundle "${INFRA_BUNDLE}"
fi

# Step 2: Run UC setup job (optional — creates SPN, stores secrets, creates table)
if [[ "${RUN_SETUP}" == true ]] && [[ "${VALIDATE_ONLY}" != true ]] && [[ "${DESTROY}" != true ]]; then
  run_uc_setup
fi

# Step 3: Verify infrastructure readiness (gate before app bundle deploy)
if [[ "${DEPLOY_APP}" == true ]] && [[ "${SKIP_CHECKS}" != true ]] && [[ "${VALIDATE_ONLY}" != true ]] && [[ "${DESTROY}" != true ]]; then
  resolve_infra_vars
  verify_infra_readiness
  # Read iOS Bootstrap SPN application_id for app bundle permissions
  read_ios_spn_id
fi

# Step 4: Deploy app bundle
# If IOS_BOOTSTRAP_SPN_ID was resolved, pass it as --var so the app bundle's
# permissions block can grant CAN_USE to the iOS SPN declaratively.
if [[ "${DEPLOY_APP}" == true ]]; then
  if [[ -n "${IOS_BOOTSTRAP_SPN_ID}" ]]; then
    deploy_bundle "${APP_BUNDLE}" --var "ios_bootstrap_spn_id=${IOS_BOOTSTRAP_SPN_ID}"
  else
    deploy_bundle "${APP_BUNDLE}"
  fi
fi

log "Done."
