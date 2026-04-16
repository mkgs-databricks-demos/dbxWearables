#!/usr/bin/env bash
# deploy.sh — Shared deployment script for the dbxWearables ZeroBus solution.
#
# Deploys Databricks Asset Bundles in dependency order:
#   1. dbxW_zerobus_infra  (secret scopes, UC schemas, volumes, grants)
#   2. dbxW_zerobus         (AppKit app, pipelines, jobs) — when available
#
# Usage:
#   ./deploy.sh --target dev              # validate + deploy all bundles
#   ./deploy.sh --target prod             # deploy to production
#   ./deploy.sh --target dev --infra      # deploy only the infra bundle
#   ./deploy.sh --target dev --app        # deploy only the app bundle (skip infra)
#   ./deploy.sh --target dev --validate   # validate only, no deploy
#   ./deploy.sh --target dev --destroy    # destroy deployed resources
#
# Requirements:
#   - Databricks CLI installed and authenticated (databricks auth login)

set -euo pipefail

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_BUNDLE="dbxW_zerobus_infra"
APP_BUNDLE="dbxW_zerobus"

# Ordered list of bundles — infra must deploy first
BUNDLES=("${INFRA_BUNDLE}" "${APP_BUNDLE}")

# --------------------------------------------------------------------------- #
# Defaults
# --------------------------------------------------------------------------- #
TARGET=""
DEPLOY_INFRA=true
DEPLOY_APP=true
VALIDATE_ONLY=false
DESTROY=false

# --------------------------------------------------------------------------- #
# Usage
# --------------------------------------------------------------------------- #
usage() {
  cat <<EOF
Usage: $(basename "$0") --target <target> [OPTIONS]

Options:
  --target <name>   Required. Bundle target (dev, prod).
  --infra           Deploy only the infrastructure bundle.
  --app             Deploy only the application bundle (skip infra).
  --validate        Validate bundles without deploying.
  --destroy         Destroy deployed resources for the target.
  -h, --help        Show this help message.

Bundles are deployed in order:
  1. ${INFRA_BUNDLE}   (shared infrastructure)
  2. ${APP_BUNDLE}      (application — when available)
EOF
  exit 0
}

# --------------------------------------------------------------------------- #
# Parse arguments
# --------------------------------------------------------------------------- #
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)   TARGET="$2"; shift 2 ;;
    --infra)    DEPLOY_INFRA=true; DEPLOY_APP=false; shift ;;
    --app)      DEPLOY_INFRA=false; DEPLOY_APP=true; shift ;;
    --validate) VALIDATE_ONLY=true; shift ;;
    --destroy)  DESTROY=true; shift ;;
    -h|--help)  usage ;;
    *)          echo "Error: Unknown option '$1'"; usage ;;
  esac
done

if [[ -z "${TARGET}" ]]; then
  echo "Error: --target is required."
  usage
fi

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
log() { echo -e "\n\033[1;34m==>\033[0m \033[1m$1\033[0m"; }
warn() { echo -e "\033[1;33m  ⚠  $1\033[0m"; }
ok() { echo -e "\033[1;32m  ✓  $1\033[0m"; }
fail() { echo -e "\033[1;31m  ✗  $1\033[0m"; exit 1; }

deploy_bundle() {
  local bundle_name="$1"
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
    (cd "${bundle_dir}" && databricks bundle deploy --target "${TARGET}")
    ok "Deployed: ${bundle_name}"
  fi
}

# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
log "dbxWearables ZeroBus — Bundle Deployment"
echo "  Target:        ${TARGET}"
echo "  Infra bundle:  ${DEPLOY_INFRA}"
echo "  App bundle:    ${DEPLOY_APP}"
echo "  Validate only: ${VALIDATE_ONLY}"
echo "  Destroy:       ${DESTROY}"

if [[ "${DEPLOY_INFRA}" == true ]]; then
  deploy_bundle "${INFRA_BUNDLE}"
fi

if [[ "${DEPLOY_APP}" == true ]]; then
  deploy_bundle "${APP_BUNDLE}"
fi

log "Done."
