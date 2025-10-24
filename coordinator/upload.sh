#!/usr/bin/env bash
set -euo pipefail

# Upload initial commitments to cloud storage
# Usage:
#   ./upload.sh [version] [bucket]
#
# Examples:
#   ./upload.sh                                    # Upload all (v1 + v2 + batch)
#   ./upload.sh v1                                 # Upload only v1
#   ./upload.sh v2                                 # Upload only v2
#   ./upload.sh batch                              # Upload only batch
#   ./upload.sh v1 my-bucket                       # Upload v1 to custom bucket

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTRIBUTIONS_DIR="$SCRIPT_DIR/../contributions"
INITIAL_DIR="$CONTRIBUTIONS_DIR/0000_initial"

VERSION="${1:-all}"
BUCKET="${2:-light-protocol-proving-keys}"

echo "========================================="
echo "Uploading Initial Commitments"
echo "========================================="
echo "Version: $VERSION"
echo "Bucket: gs://$BUCKET"
echo ""

# Check if 0000_initial directory exists
if [[ ! -d "$INITIAL_DIR" ]]; then
    echo "Error: Initial commitments directory not found: $INITIAL_DIR"
    echo ""
    echo "Run './init.sh' or './init.sh --v1' first."
    exit 1
fi

# Check if gsutil is available
if ! command -v gsutil &> /dev/null; then
    echo "Error: gsutil not found. Please install Google Cloud SDK."
    echo "Visit: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Check if bucket exists
if ! gsutil ls "gs://$BUCKET" >/dev/null 2>&1; then
    echo "Error: Bucket gs://$BUCKET does not exist or you don't have access."
    echo ""
    echo "To create a bucket:"
    echo "  gsutil mb gs://$BUCKET"
    echo ""
    echo "To check your access:"
    echo "  gsutil ls"
    exit 1
fi

# Determine which directories to upload
UPLOAD_DIRS=()
if [[ "$VERSION" == "all" ]]; then
    [[ -d "$INITIAL_DIR/v1" ]] && UPLOAD_DIRS+=("v1")
    [[ -d "$INITIAL_DIR/v2" ]] && UPLOAD_DIRS+=("v2")
    [[ -d "$INITIAL_DIR/batch" ]] && UPLOAD_DIRS+=("batch")
elif [[ "$VERSION" == "v1" ]] || [[ "$VERSION" == "v2" ]] || [[ "$VERSION" == "batch" ]]; then
    if [[ ! -d "$INITIAL_DIR/$VERSION" ]]; then
        echo "Error: Directory not found: $INITIAL_DIR/$VERSION"
        echo ""
        echo "Run './init.sh' or './init.sh --v1' first."
        exit 1
    fi
    UPLOAD_DIRS+=("$VERSION")
else
    echo "Error: Invalid version: $VERSION"
    echo "Valid options: all, v1, v2, batch"
    exit 1
fi

if [[ ${#UPLOAD_DIRS[@]} -eq 0 ]]; then
    echo "Error: No directories to upload found in $INITIAL_DIR"
    exit 1
fi

# Upload each directory
total_uploaded=0
for dir in "${UPLOAD_DIRS[@]}"; do
    SOURCE="$INITIAL_DIR/$dir"
    DEST="gs://$BUCKET/ceremony/contributions/0000_initial/$dir/"

    # Count files
    file_count=$(find "$SOURCE" -type f | wc -l | tr -d ' ')

    if [[ $file_count -eq 0 ]]; then
        echo "Skipping $dir (no files)"
        continue
    fi

    echo "Uploading $dir/ ($file_count files)..."

    # Use gsutil -m for parallel upload
    # Expand files explicitly to avoid quoted glob literal
    if gsutil -m cp -r "$SOURCE"/* "$DEST" >/dev/null 2>&1; then
        echo "  ✓ Uploaded $file_count files to: $DEST"
        total_uploaded=$((total_uploaded + file_count))
    else
        echo "  ✗ Failed to upload $dir/"
    fi
    echo ""
done

echo "========================================="
echo "Upload Complete!"
echo "========================================="
echo "Total files uploaded: $total_uploaded"
echo ""
echo "Next steps:"
if [[ "$VERSION" == "all" ]]; then
    echo "  # For V1 ceremony:"
    echo "  ./generate_urls.sh $BUCKET <contributor> 0000_initial/v1"
    echo ""
    echo "  # For V2 ceremony:"
    echo "  ./generate_urls.sh $BUCKET <contributor> 0000_initial/v2"
    echo ""
    echo "  # For Batch ceremony:"
    echo "  ./generate_urls.sh $BUCKET <contributor> 0000_initial/batch"
else
    echo "  ./generate_urls.sh $BUCKET <contributor> 0000_initial/$VERSION"
fi
echo ""
