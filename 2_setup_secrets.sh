#!/usr/bin/env bash
set -euo pipefail

# 2_setup_secrets.sh - store sensitive values in Secret Manager
#
# What it does:
# - Persists secret names to `.env` so later scripts can reference them
# - Stores the generated DB user password into Secret Manager
# - Generates and stores a new n8n encryption key (used by n8n to encrypt credentials)
#
# Rationale:
# Keeping secrets in Secret Manager ensures they are not stored in plaintext in
# the repository. The scripts add new secret versions when a secret already
# exists so rotation is simple.

# Load env helpers
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env_utils.sh"

# Define secret names used by the deployment
DB_PASSWORD_SECRET_NAME="n8n-db-password"
N8N_ENCRYPTION_KEY_SECRET_NAME="n8n-encryption-key"

# Persist secret names for later steps
save_var DB_PASSWORD_SECRET_NAME "$DB_PASSWORD_SECRET_NAME"
save_var N8N_ENCRYPTION_KEY_SECRET_NAME "$N8N_ENCRYPTION_KEY_SECRET_NAME"

# Require the SQL user password to be present (loaded from .env by env_utils)
if [ -z "${SQL_USER_PASSWORD:-}" ]; then
    echo "ERROR: SQL_USER_PASSWORD is not set. Run 1_setup_psql.sh first or export the variable." >&2
    exit 1
fi

# Store the database user password (create secret or add version)
echo "Storing database password in Secret Manager..."
if gcloud secrets describe "$DB_PASSWORD_SECRET_NAME" >/dev/null 2>&1; then
    echo -n "$SQL_USER_PASSWORD" | gcloud secrets versions add "$DB_PASSWORD_SECRET_NAME" --data-file=-
else
    echo -n "$SQL_USER_PASSWORD" | gcloud secrets create "$DB_PASSWORD_SECRET_NAME" \
        --data-file=- \
        --replication-policy="automatic"
fi

# Generate and store a strong n8n encryption key (create or add version)
if gcloud secrets describe "$N8N_ENCRYPTION_KEY_SECRET_NAME" >/dev/null 2>&1; then
    echo "n8n encryption key secret already exists; adding a new version..."
    N8N_ENCRYPTION_KEY=$(openssl rand -base64 32)
    echo -n "$N8N_ENCRYPTION_KEY" | gcloud secrets versions add "$N8N_ENCRYPTION_KEY_SECRET_NAME" --data-file=-
else
    echo "Creating n8n encryption key secret and storing value..."
    N8N_ENCRYPTION_KEY=$(openssl rand -base64 32)
    echo -n "$N8N_ENCRYPTION_KEY" | gcloud secrets create "$N8N_ENCRYPTION_KEY_SECRET_NAME" \
        --data-file=- \
        --replication-policy="automatic"
fi

echo "Secrets stored successfully."
save_var DB_PASSWORD_SECRET_NAME "$DB_PASSWORD_SECRET_NAME"
save_var N8N_ENCRYPTION_KEY_SECRET_NAME "$N8N_ENCRYPTION_KEY_SECRET_NAME"
