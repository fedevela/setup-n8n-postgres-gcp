#!/usr/bin/env bash
# env_utils.sh - small helper used by the setup scripts
#
# Responsibilities:
# - Load a local `.env` file (if present) so subsequent scripts can reuse values.
# - Provide `save_var KEY VALUE` which safely writes/updates the `.env` file and
#   exports the value in the current shell. The `.env` file is created with
#   restrictive permissions (chmod 600) to avoid accidental exposure.
#
# Rationale:
# Many deployment steps need to share values like PROJECT_ID, REGION,
# SQL instance names and generated passwords. Persisting them to a single
# `.env` file makes it safe and repeatable to run individual scripts later
# without re-generating secrets or looking up values in the console.

set -euo pipefail

# Path to the local .env used by the repo (created in the repo root)
ENV_FILE="$(cd "$(dirname "$0")" && pwd)/.env"

# Load existing .env if present so variables are available to scripts that
# source this file. `set -a` exports any variables loaded from the file.
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  set -a
  # shellcheck disable=SC1091
  source "$ENV_FILE"
  set +a
fi

# save_var KEY VALUE
# Appends or updates an assignment in the .env file in a safe way and
# exports the variable in the current shell so other sourced scripts can use it.
# - Ensures the .env exists with 600 permissions
# - Removes any previous assignment for the key and then appends the new one
# - Escapes single quotes in the value so it remains safe for single-quoted assignment
save_var() {
  local key="$1"
  local val="$2"
  # ensure .env exists with safe perms
  touch "$ENV_FILE"
  chmod 600 "$ENV_FILE" || true

  # Remove any existing entry for the key then append the new value safely.
  if grep -qE "^${key}=" "$ENV_FILE" 2>/dev/null; then
    grep -v -E "^${key}=" "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
  fi

  # Escape single quotes in the value for single-quoted assignment
  local esc
  esc=$(printf "%s" "$val" | sed "s/'/'\"'\"'/g")
  printf "%s='%s'\n" "$key" "$esc" >> "$ENV_FILE"

  # Export in current shell so scripts which source this file immediately
  # see the new value without requiring a separate `source .env` call.
  export "$key"="$val"
}

export ENV_FILE
