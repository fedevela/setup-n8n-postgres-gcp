#!/usr/bin/env bash
# 0_setup.sh - foundational project and networking setup for Cloud Run + Cloud SQL
#
# What it does:
# - Loads `env_utils.sh` so discovered values are saved to `.env` for later scripts.
# - Ensures a GCP project is selected (via gcloud config or env vars) and persists it.
# - Enables required Google APIs used by the rest of the workflow.
# - Configures Service Networking and a global address range used to peer Google-managed
#   services with your VPC so Cloud SQL private IP works.
# - Ensures a Serverless VPC Access connector exists in the chosen region so Cloud Run
#   can reach private IP resources (Cloud SQL private IP) across the VPC.
#
# Rationale:
# Cloud Run instances running in the managed platform cannot directly reach a Cloud SQL
# private IP without a Serverless VPC connector and proper VPC peering. This script
# prepares those pieces so the later deployment steps can connect securely.

# Load environment utilities (persist discovered values to .env)
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env_utils.sh"

# Get your current Google Cloud Project ID (or set it if missing)
PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)
if [ -z "${PROJECT_ID:-}" ] || [ "$PROJECT_ID" = "unset" ]; then
    echo "No gcloud project is currently set. Trying env vars GCLOUD_PROJECT or GCP_PROJECT..."
    if [ -n "${GCLOUD_PROJECT:-}" ]; then
        PROJECT_ID="$GCLOUD_PROJECT"
    elif [ -n "${GCP_PROJECT:-}" ]; then
        PROJECT_ID="$GCP_PROJECT"
    else
        # No env var provided; pick the first project from gcloud projects list
        echo "No GCLOUD_PROJECT/GCP_PROJECT env var found. Choosing the first available project from 'gcloud projects list'..."
        PROJECT_ID=$(gcloud projects list --format="value(projectId)" | head -n 1)
        if [ -n "${PROJECT_ID:-}" ]; then
            echo "Automatically selected project: $PROJECT_ID"
        else
            echo "No projects available in gcloud. Exiting." >&2
            exit 1
        fi
    fi
        if [ -n "$PROJECT_ID" ]; then
        gcloud config set project "$PROJECT_ID"
        echo "Set gcloud default project to: $PROJECT_ID"
        save_var PROJECT_ID "$PROJECT_ID"
    else
        echo "No project provided. Exiting." >&2
        exit 1
    fi
else
    echo "Your current project ID is: $PROJECT_ID"
    # Persist the detected/unchanged project ID
    save_var PROJECT_ID "$PROJECT_ID"
fi

# Get your project number (used to construct default service account emails)
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
echo "Your project number is: $PROJECT_NUMBER"
save_var PROJECT_NUMBER "$PROJECT_NUMBER"

# Set a region for your services (you can change this to your preferred region)
REGION="us-central1"
echo "Deploying services to region: $REGION"

# Enable necessary Google Cloud APIs for Cloud Run, Cloud SQL, Secret Manager, Cloud Build and Artifact Registry
gcloud services enable \
        run.googleapis.com \
        sqladmin.googleapis.com \
        secretmanager.googleapis.com \
        cloudbuild.googleapis.com \
        artifactregistry.googleapis.com

# Enable Service Networking API for private IP connectivity, required by Cloud SQL private IP
if ! gcloud services list --enabled --format='value(config.name)' | grep -q 'servicenetworking.googleapis.com'; then
    echo 'Enabling Service Networking API (servicenetworking.googleapis.com)...'
    gcloud services enable servicenetworking.googleapis.com
else
    echo 'Service Networking API already enabled, skipping.'
fi

# Configure VPC peering for Service Networking if not already configured
RANGE_NAME=google-managed-services-$PROJECT_ID
if ! gcloud compute addresses describe $RANGE_NAME --global --format='value(name)' 2>/dev/null; then
    echo "Creating global address reservation for service networking: $RANGE_NAME"
    gcloud compute addresses create $RANGE_NAME --global --purpose=VPC_PEERING --network=default --prefix-length=24
else
    echo "Address reservation $RANGE_NAME already exists, skipping."
fi

if ! gcloud services vpc-peerings list --network=default --format='value(name)' | grep -q 'servicenetworking'; then
    echo 'Creating VPC peering for Service Networking...'
    gcloud services vpc-peerings connect --service=servicenetworking.googleapis.com --network=default --ranges=$RANGE_NAME --project=$PROJECT_ID
else
    echo 'VPC peering for Service Networking already exists, skipping.'
fi

# Enable Serverless VPC Access API if needed
if ! gcloud services list --enabled --format='value(config.name)' | grep -q 'vpcaccess.googleapis.com'; then
    echo 'Enabling Serverless VPC Access API (vpcaccess.googleapis.com)...'
    gcloud services enable vpcaccess.googleapis.com
else
    echo 'Serverless VPC Access API already enabled, skipping.'
fi

# Create a Serverless VPC Access connector so Cloud Run can reach resources on the VPC (Cloud SQL private IP)
CONNECTOR_NAME="vpc-connector"
save_var CONNECTOR_NAME "$CONNECTOR_NAME"

echo "Ensuring Serverless VPC Access connector exists: $CONNECTOR_NAME in region $REGION"
if gcloud compute networks vpc-access connectors describe "$CONNECTOR_NAME" --region="$REGION" >/dev/null 2>&1; then
    echo "VPC Access connector $CONNECTOR_NAME already exists in $REGION, skipping creation."
else
    # This script uses a default high-numbered IP range to avoid common conflicts.
    # To use a different range, set the CONNECTOR_RANGE environment variable before running.
    # Example: export CONNECTOR_RANGE="10.128.0.0/28"
    if [ -z "${CONNECTOR_RANGE:-}" ]; then
        CONNECTOR_RANGE="10.88.0.0/28"
        echo "Using default connector IP range: $CONNECTOR_RANGE"
    else
        echo "Using user-provided connector IP range: $CONNECTOR_RANGE"
    fi

    echo "Creating Serverless VPC Access connector $CONNECTOR_NAME with range $CONNECTOR_RANGE"
    gcloud compute networks vpc-access connectors create "$CONNECTOR_NAME" \
        --region="$REGION" \
        --network=default \
        --range="$CONNECTOR_RANGE" || {
            echo "Failed to create VPC Access connector. This can happen if the IP range $CONNECTOR_RANGE is already in use." >&2
            echo "Please try setting a different /28 range by exporting CONNECTOR_RANGE and re-running." >&2
            exit 1
        }
    echo "Connector $CONNECTOR_NAME created."
fi

