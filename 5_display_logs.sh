# 5_display_logs.sh - convenience helper to show recent Cloud Run logs
#
# This small helper shows recent stdout/stderr logs for the deployed Cloud Run
# service. It's useful while developing or verifying that the service started
# successfully.

# Load env helpers to get values like CLOUD_RUN_SERVICE_NAME and REGION from .env
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env_utils.sh"

echo "Fetching APPLICATION logs (stdout/stderr) for Cloud Run service: $CLOUD_RUN_SERVICE_NAME in $REGION..."
# This command specifically filters for logs from the container's stdout/stderr
gcloud logging read "resource.type=cloud_run_revision AND \
resource.labels.service_name=$CLOUD_RUN_SERVICE_NAME AND \
resource.labels.location=$REGION" \
    --project=$PROJECT_ID \
    --limit=200 \
    --order=desc \
    --format="table(timestamp, logName, textPayload)"

echo ""
echo "--- End of logs ---"
