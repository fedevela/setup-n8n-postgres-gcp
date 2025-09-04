#!/usr/bin/env bash
set -euo pipefail

# 3_setup_docker_n8n.sh - prepare n8n container image in Artifact Registry
#
# What it does:
# - Uses the official n8n image (no custom Dockerfile required)
# - Creates an Artifact Registry Docker repository (if missing)
# - Uses Cloud Build to pull the official image and re-push it into your
#   project's Artifact Registry so Cloud Run can reference a regional image.
#
# Rationale:
# Pushing the image into Artifact Registry ensures the image is available
# to Cloud Run in the same region and controlled under your project.

# Load env helpers
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env_utils.sh"

# Check required tools
command -v gcloud >/dev/null 2>&1 || { echo "gcloud is required but not installed" >&2; exit 1; }

# Create a directory for artifacts and switch into it
mkdir -p n8n-cloudrun
pushd n8n-cloudrun >/dev/null

# Use official n8n image directly - no custom Dockerfile needed
N8N_IMAGE="n8nio/n8n:1.108.2"

# Create an Artifact Registry repository if you don't have one
if gcloud artifacts repositories describe n8n-repo --location=$REGION >/dev/null 2>&1; then
    echo "Artifact Registry repository n8n-repo already exists in $REGION, skipping creation."
else
    gcloud artifacts repositories create n8n-repo \
        --repository-format=docker \
        --location=$REGION \
        --description="Docker repository for n8n images"
fi

# Define image name in Artifact Registry (regional hostname style)
DOCKER_IMAGE_NAME="$REGION-docker.pkg.dev/$PROJECT_ID/n8n-repo/n8n:1.108.2"
echo "Using Cloud Build to pull and push the n8n image to: $DOCKER_IMAGE_NAME"

# Enable Cloud Build API if not already enabled
gcloud services enable cloudbuild.googleapis.com

# Use Cloud Build to pull and push the image (no local Docker needed)
cat > cloudbuild.yaml <<EOF
steps:
  - name: 'gcr.io/cloud-builders/docker'
    args: ['pull', '$N8N_IMAGE']
  - name: 'gcr.io/cloud-builders/docker'
    args: ['tag', '$N8N_IMAGE', '$DOCKER_IMAGE_NAME']
images:
  - '$DOCKER_IMAGE_NAME'
EOF

# Submit the build job (Cloud Build will pull, tag, and push the image into Artifact Registry)
gcloud builds submit --config=cloudbuild.yaml --no-source

# Save the image name for the next step
save_var DOCKER_IMAGE_NAME "$DOCKER_IMAGE_NAME"

popd >/dev/null # Go back to the parent directory
