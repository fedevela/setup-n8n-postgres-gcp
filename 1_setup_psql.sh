#!/usr/bin/env bash
set -euo pipefail

# 1_setup_psql.sh - create Cloud SQL (Postgres) instance, database, and user
#
# Behavior:
# - Uses `env_utils.sh` to persist values like REGION and the generated DB password.
# - By default the script is non-destructive and will create a new Cloud SQL
#   instance and user only if they do not exist. Use the `DB_ACTION` env var to
#   control destructive behaviors.
#
# Notes on DB_ACTION:
# - destroy_sql_instance: attempts to delete the entire Cloud SQL instance
# - drop_db: deletes the specific database and user
# - ignore (default): create non-destructively

# Load env helpers so REGION and other saved values are available
if [ -f "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env_utils.sh" ]; then
    . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env_utils.sh"
fi

# Ensure REGION is set (safe default). Persist it so other scripts see the same value.
if [ -z "${REGION:-}" ]; then
    REGION="us-central1"
    # if save_var is available from env_utils, persist it
    if command -v save_var >/dev/null 2>&1; then
        save_var REGION "$REGION"
    else
        export REGION
    fi
fi

 # Define your Cloud SQL instance name, database name, and user
SQL_INSTANCE_NAME="n8n-postgres-instance"
SQL_DATABASE_NAME="n8n_db"
SQL_USER_NAME="n8n_user"

# Determine whether to drop existing database resources (options: "destroy_sql_instance" or "ignore" default)
DB_ACTION="${DB_ACTION:-ignore}"
export DB_ACTION
echo "DB_ACTION for SQL setup: $DB_ACTION"
if [ "$DB_ACTION" = "destroy_sql_instance" ]; then
    echo "Dropping existing Cloud SQL instance: $SQL_INSTANCE_NAME"
    if ! gcloud sql instances delete "$SQL_INSTANCE_NAME" --quiet; then
        echo "Warning: insufficient permissions to delete instance $SQL_INSTANCE_NAME. Continuing setup."
    fi
    echo "Finished deletion command for instance: $SQL_INSTANCE_NAME"
fi

# Persist key values to .env so individual scripts can be run later
save_var SQL_INSTANCE_NAME "$SQL_INSTANCE_NAME"
save_var SQL_DATABASE_NAME "$SQL_DATABASE_NAME"
save_var SQL_USER_NAME "$SQL_USER_NAME"

# Create the Cloud SQL instance (if not present). We prefer IAM DB authentication
# for Cloud Run connections, so cloudsql.iam_authentication is enabled on the instance.
if gcloud sql instances describe $SQL_INSTANCE_NAME --format="value(name)" >/dev/null 2>&1; then
    echo "Cloud SQL instance $SQL_INSTANCE_NAME already exists in $REGION, skipping creation."
    echo "Retrieving existing instance password from environment..."
    if [ -z "${SQL_USER_PASSWORD:-}" ]; then
        echo "ERROR: SQL_USER_PASSWORD is not set in your environment for the existing instance." >&2
        echo "If you have run this script before, the password should be in your .env file. If not, please add it manually." >&2
        exit 1
    fi
else
    echo "Creating Cloud SQL PostgreSQL instance: $SQL_INSTANCE_NAME in $REGION..."
    # Generate a strong random password for the database user since we are creating a new instance
    SQL_USER_PASSWORD=$(openssl rand -base64 12)
    save_var SQL_USER_PASSWORD "$SQL_USER_PASSWORD"

    gcloud sql instances create $SQL_INSTANCE_NAME \
        --database-version=POSTGRES_15 \
        --region=$REGION \
        --tier=db-g1-small \
        --network=default \
        --no-assign-ip \
        --database-flags=cloudsql.iam_authentication=on \
        --root-password=$SQL_USER_PASSWORD \
        --quiet
fi

echo "Creating database: $SQL_DATABASE_NAME on $SQL_INSTANCE_NAME..."
if [ "$DB_ACTION" = "drop_db" ]; then
    echo "Dropping database $SQL_DATABASE_NAME..."
    gcloud sql databases delete "$SQL_DATABASE_NAME" --instance="$SQL_INSTANCE_NAME" --quiet || echo "Database did not exist."
fi

if gcloud sql databases describe $SQL_DATABASE_NAME --instance=$SQL_INSTANCE_NAME >/dev/null 2>&1; then
    echo "Database $SQL_DATABASE_NAME already exists on $SQL_INSTANCE_NAME, skipping creation."
else
    gcloud sql databases create $SQL_DATABASE_NAME --instance=$SQL_INSTANCE_NAME
fi

echo "Creating user: $SQL_USER_NAME for $SQL_DATABASE_NAME..."
if [ "$DB_ACTION" = "drop_db" ]; then
    echo "Dropping user $SQL_USER_NAME..."
    gcloud sql users delete "$SQL_USER_NAME" --instance="$SQL_INSTANCE_NAME" --quiet || echo "User did not exist."
fi

# Create the user without a permissive host and prefer IAM DB auth for Cloud Run connections
if gcloud sql users describe $SQL_USER_NAME --instance=$SQL_INSTANCE_NAME >/dev/null 2>&1; then
    echo "User $SQL_USER_NAME already exists on $SQL_INSTANCE_NAME, skipping creation."
else
    gcloud sql users create $SQL_USER_NAME --instance=$SQL_INSTANCE_NAME --password=$SQL_USER_PASSWORD
fi

echo "Cloud SQL setup complete. Database user password saved to $ENV_FILE (permissions 600)"
