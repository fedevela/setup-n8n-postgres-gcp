#!/usr/bin/env bash
set -euo pipefail

# main.sh - simple orchestrator for the repository
#
# Purpose:
# Run the numbered setup scripts in order so newcomers can execute a single
# command to perform the full GCP + n8n deployment workflow. Each script is
# idempotent where possible and the orchestrator accepts small env overrides.

# Ensure we're running under bash (not sh/dash) because some scripts rely on
# bash-specific features like arrays and parameter expansion.
if [ -z "${BASH_VERSION:-}" ]; then
  echo "This orchestrator must be run with bash. Use: bash main.sh or ./main.sh" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

# Allow passing simple environment overrides on the command line. Example:
#   bash main.sh DB_ACTION=destroy_sql_instance
# These overrides are exported into the environment so scripts can consume them.
for arg in "$@"; do
  if [[ "$arg" == *=* ]]; then
    export "$arg"
    echo "Exported override: $arg"
  fi
done

# DB_ACTION controls how the SQL setup script behaves. Options are:
# - destroy_sql_instance: delete the entire Cloud SQL instance (destructive)
# - drop_db: drop the created database and user
# - ignore (default): create resources non-destructively
DB_ACTION="${DB_ACTION:-ignore}"
export DB_ACTION
echo "DB_ACTION=$DB_ACTION"

SCRIPTS=(
  "0_setup.sh"
  "1_setup_psql.sh"
  "2_setup_secrets.sh"
  "3_setup_docker_n8n.sh"
  "4_deploy_cloudrun_n8n.sh"
  # "5_display_logs.sh" # optional helper; enable if you want logs after deploy
)

echo "Running setup scripts from: $ROOT_DIR"

for script in "${SCRIPTS[@]}"; do
  if [ ! -f "$script" ]; then
    echo "Skipping missing script: $script"
    continue
  fi

  echo "--- Sourcing $script ---"
  # shellcheck disable=SC1090
  if ! . "$script"; then
    echo "Script $script failed while sourcing. Exiting." >&2
    exit 1
  fi
  echo "--- Finished $script ---"
done

echo "All setup scripts completed."
