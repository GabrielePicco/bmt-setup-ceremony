#!/usr/bin/env bash
set -euo pipefail

# Create service account key for URL signing
# Usage: ./create_key.sh [bucket-name]
# Default bucket: light-protocol-proving-keys

BUCKET="${1:-light-protocol-proving-keys}"

echo "Creating service account key for URL signing..."
echo "Bucket: $BUCKET"
echo "NOTE: This creates a JSON key file in ./service-account-key.json. Keep it SECRET."

# Dependency checks
if ! command -v gcloud >/dev/null 2>&1; then
    echo "Error: gcloud not found. Please install Google Cloud SDK." >&2
    exit 1
fi
if ! command -v gsutil >/dev/null 2>&1; then
    echo "Error: gsutil not found. Please install Google Cloud SDK." >&2
    exit 1
fi

# Find existing service account
SERVICE_ACCOUNT=$(gcloud iam service-accounts list --filter="email:ceremony-coordinator*" --format="value(email)" 2>/dev/null | head -1)

if [[ -n "$SERVICE_ACCOUNT" ]]; then
    echo "Found existing service account: $SERVICE_ACCOUNT"

    # Grant necessary permissions to the service account
    echo "Granting permissions to service account..."

    # Grant object admin permission on the bucket
    gsutil iam ch "serviceAccount:${SERVICE_ACCOUNT}:objectAdmin" "gs://$BUCKET"
    echo "Granted objectAdmin permission on gs://$BUCKET"

    echo "Creating key..."
    gcloud iam service-accounts keys create ./service-account-key.json \
        --iam-account="$SERVICE_ACCOUNT"
    chmod 600 ./service-account-key.json || true
    echo "Key created: ./service-account-key.json (permissions set to 600)"
else
    echo "No ceremony-coordinator service account found."
    echo ""
    echo "You can use any service account that has access to the bucket."
    echo "List available service accounts:"
    gcloud iam service-accounts list --format="table(email,displayName)"
    echo ""
    echo "To create a key for a specific service account:"
    echo "gcloud iam service-accounts keys create ./service-account-key.json --iam-account=<SERVICE-ACCOUNT-EMAIL>"
fi
