#!/usr/bin/env bash
# upload_garmin_tokens.sh
#
# Fresh-deploy Garmin credential bootstrap. Runs an interactive `garth login`
# in your terminal (handles MFA), packs the resulting OAuth token pair into
# a single JSON payload, and uploads it to the Databricks secret scope as
# `garmin_oauth_tokens`.
#
# Your Garmin email, password, and MFA code are typed once into your local
# terminal. They are NEVER written to disk, NEVER passed to a notebook
# widget, and NEVER committed to git. Only the resulting OAuth tokens are
# stored — encrypted at rest in the Databricks secret scope.
#
# Usage:
#   ./upload_garmin_tokens.sh --profile <cli-profile> [--scope <scope-name>] [--key <key-name>]
#
# Examples:
#   ./upload_garmin_tokens.sh --profile my-dev
#   ./upload_garmin_tokens.sh --profile my-dev --scope dbxw_zerobus_credentials
#
# Prerequisites:
#   - databricks CLI authenticated to the target workspace under --profile
#   - python3 with venv support (any 3.9+)
#   - MANAGE access on the target secret scope

set -euo pipefail

PROFILE=""
SCOPE="dbxw_zerobus_credentials"
KEY="garmin_oauth_tokens"

usage() {
  cat <<EOF
Usage: $0 --profile <cli-profile> [--scope <scope>] [--key <key>]

  --profile   Databricks CLI profile (from ~/.databrickscfg). Required.
  --scope     Secret scope name. Default: dbxw_zerobus_credentials
  --key       Secret key name. Default: garmin_oauth_tokens
  -h, --help  Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2;;
    --scope)   SCOPE="$2"; shift 2;;
    --key)     KEY="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

if [[ -z "${PROFILE}" ]]; then
  echo "ERROR: --profile is required" >&2
  usage
  exit 2
fi

if ! command -v databricks >/dev/null 2>&1; then
  echo "ERROR: databricks CLI not found on PATH" >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 not found on PATH" >&2
  exit 2
fi

# Everything happens in a temp dir that gets wiped on exit.
WORK_DIR="$(mktemp -d -t garmin_tokens.XXXXXX)"
trap 'rm -rf "${WORK_DIR}"' EXIT

echo "==> Setting up throwaway Python env in ${WORK_DIR}"
python3 -m venv "${WORK_DIR}/venv"
# shellcheck disable=SC1091
source "${WORK_DIR}/venv/bin/activate"
pip install --quiet --upgrade pip
pip install --quiet "garth>=0.5,<1.0"

TOKEN_DIR="${WORK_DIR}/.garth"
mkdir -p "${TOKEN_DIR}"

echo ""
echo "==> Logging in to Garmin Connect"
echo "    You will be prompted for your email, password, and MFA code."
echo "    Credentials are NOT saved — only the resulting OAuth tokens."
echo ""

python3 - "${TOKEN_DIR}" <<'PY'
import getpass
import sys

import garth

token_dir = sys.argv[1]

email = input("Garmin email: ").strip()
password = getpass.getpass("Garmin password: ")

def prompt_mfa() -> str:
    return input("Garmin MFA code: ").strip()

garth.login(email, password, prompt_mfa=prompt_mfa)
garth.save(token_dir)
print(f"\nTokens written to {token_dir}")
PY

OAUTH1="${TOKEN_DIR}/oauth1_token.json"
OAUTH2="${TOKEN_DIR}/oauth2_token.json"

if [[ ! -f "${OAUTH1}" || ! -f "${OAUTH2}" ]]; then
  echo "ERROR: expected token files not found under ${TOKEN_DIR}" >&2
  ls -la "${TOKEN_DIR}" >&2 || true
  exit 1
fi

echo ""
echo "==> Packaging tokens for upload"
# Single JSON payload containing both tokens. Notebooks read this blob
# and call garth.resume() with a directory rebuilt from it.
PAYLOAD="$(python3 - "${OAUTH1}" "${OAUTH2}" <<'PY'
import json
import sys

with open(sys.argv[1]) as f:
    oauth1 = json.load(f)
with open(sys.argv[2]) as f:
    oauth2 = json.load(f)

print(json.dumps({"oauth1": oauth1, "oauth2": oauth2}))
PY
)"

echo ""
echo "==> Ensuring secret scope '${SCOPE}' exists (profile=${PROFILE})"
if ! databricks secrets list-scopes --profile "${PROFILE}" --output json 2>/dev/null \
  | python3 -c "import sys,json; sys.exit(0 if any(s.get('name')=='${SCOPE}' for s in json.load(sys.stdin)) else 1)"; then
  echo "    scope not found — creating"
  databricks secrets create-scope "${SCOPE}" --profile "${PROFILE}"
else
  echo "    scope exists"
fi

echo ""
echo "==> Uploading to ${SCOPE}/${KEY}"
databricks secrets put-secret "${SCOPE}" "${KEY}" \
  --string-value "${PAYLOAD}" \
  --profile "${PROFILE}"

echo ""
echo "Done. garmin_oauth_tokens is stored in scope '${SCOPE}'."
echo "The temp directory ${WORK_DIR} (including local token files) will be removed on exit."
