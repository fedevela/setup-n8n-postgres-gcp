#!/usr/bin/env bash
# 4_deploy_cloudrun_n8n.sh - deploy n8n to Cloud Run and wire up Cloud SQL and secrets
set -euo pipefail

# This script deploys the previously prepared Docker image to Cloud Run and
# ensures the service account has access to Secret Manager and Cloud SQL.
# It also generates and prints a basic auth password for the default 'admin'
# user so you can log into the freshly deployed n8n instance.

# Load env helpers (so save_var and previously stored values are available)
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env_utils.sh"

# Define your Cloud Run service name and persist it
CLOUD_RUN_SERVICE_NAME="n8n-service"
save_var CLOUD_RUN_SERVICE_NAME "$CLOUD_RUN_SERVICE_NAME"

# Generate basic auth password upfront so user can see it (this password is
# printed to stdout; for production consider rotating or injecting a secret)
N8N_BASIC_AUTH_PASSWORD_VALUE=$(openssl rand -base64 12)
echo "Your n8n basic auth password (for 'admin' user) is: $N8N_BASIC_AUTH_PASSWORD_VALUE"

# Determine the Cloud Run service account. By default, Cloud Run uses the
# Compute Engine default service account for the project; this email is derived
# from the project number collected earlier in `0_setup.sh`.
CLOUD_RUN_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
echo "Cloud Run service account will be: $CLOUD_RUN_SA"

echo "Granting Cloud Run service account ($CLOUD_RUN_SA) access to secrets BEFORE deployment..."
gcloud secrets add-iam-policy-binding $DB_PASSWORD_SECRET_NAME \
    --member="serviceAccount:$CLOUD_RUN_SA" \
    --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding $N8N_ENCRYPTION_KEY_SECRET_NAME \
    --member="serviceAccount:$CLOUD_RUN_SA" \
    --role="roles/secretmanager.secretAccessor"

# Grant Cloud Run service account the Cloud SQL Client role so it can connect to Cloud SQL
echo "Granting Cloud Run service account ($CLOUD_RUN_SA) Cloud SQL Client role..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$CLOUD_RUN_SA" \
    --role="roles/cloudsql.client"

echo "Permissions granted. Proceeding with Cloud Run deployment..."

echo "Deploying n8n to Cloud Run: $CLOUD_RUN_SERVICE_NAME. This may take a few minutes..."
# Deploy with the Cloud SQL Auth Proxy sidecar by setting the Cloud SQL instance
# name and using the serverless connector for private IP access. Secrets are
# injected using `--set-secrets` so the runtime does not receive plaintext values.
gcloud run deploy $CLOUD_RUN_SERVICE_NAME \
    --image "$DOCKER_IMAGE_NAME" \
    --platform managed \
    --region "$REGION" \
    --allow-unauthenticated \
    --set-cloudsql-instances "${PROJECT_ID}:${REGION}:${SQL_INSTANCE_NAME}" \
    --set-env-vars "DB_TYPE=postgresdb,DB_POSTGRESDB_HOST=/cloudsql/${PROJECT_ID}:${REGION}:${SQL_INSTANCE_NAME},DB_POSTGRESDB_PORT=5432,DB_POSTGRESDB_DATABASE=$SQL_DATABASE_NAME,DB_POSTGRESDB_USER=$SQL_USER_NAME,N8N_BASIC_AUTH_ACTIVE=true,N8N_BASIC_AUTH_USER=admin,N8N_BASIC_AUTH_PASSWORD=$N8N_BASIC_AUTH_PASSWORD_VALUE" \
    --set-secrets "DB_POSTGRESDB_PASSWORD=${DB_PASSWORD_SECRET_NAME}:latest,N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY_SECRET_NAME}:latest" \
    --min-instances=0 \
    --max-instances=1 \
    --cpu=1 \
    --cpu-boost \
    --memory=2Gi \
    --timeout=300s \
    --port=5678 \
    --quiet \
    --vpc-connector="$CONNECTOR_NAME" \
    --vpc-egress=private-ranges-only

echo "Cloud Run service deployed. Fetching its URL..."

# Read the service URL from Cloud Run and persist it so the user can find the instance
N8N_URL=$(gcloud run services describe $CLOUD_RUN_SERVICE_NAME \
    --platform managed \
    --region $REGION \
    --format='value(status.url)')

if [ -z "$N8N_URL" ]; then
    echo "ERROR: Could not retrieve the service URL after deployment. Exiting." >&2
    exit 1
fi

echo "Service URL found: $N8N_URL. Updating service with correct N8N_HOST and WEBHOOK_URL..."

# Now, update the service with the correct host and webhook URLs. This creates a new revision
gcloud run services update $CLOUD_RUN_SERVICE_NAME \
    --platform managed \
    --region $REGION \
    --update-env-vars="N8N_HOST=$N8N_URL,WEBHOOK_URL=$N8N_URL"

# Save the definitive URL for future runs
save_var N8N_URL "$N8N_URL"

echo "Cloud Run deployment and configuration complete."
echo "Your n8n instance is available at: $N8N_URL"

