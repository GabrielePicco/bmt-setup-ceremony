#!/usr/bin/env bash
set -euo pipefail

# Generate presigned URLs for contributor using gsutil
# Usage: ./generate_urls.sh <bucket> <contributor> <prev_contribution> [version]
#
# Examples:
#   ./generate_urls.sh bucket alice 0000_initial v1
#   ./generate_urls.sh bucket bob 0001_alice v1
#   ./generate_urls.sh bucket charlie 0002_bob all

BUCKET="${1:-}"
CONTRIBUTOR="${2:-}"
PREV_CONTRIBUTION="${3:-}"
VERSION="${4:-}"

[[ -z "$BUCKET" ]] && echo "Usage: $0 <bucket> <contributor> <prev_contribution> [version]" && exit 1
[[ -z "$CONTRIBUTOR" ]] && echo "Usage: $0 <bucket> <contributor> <prev_contribution> [version]" && exit 1
[[ -z "$PREV_CONTRIBUTION" ]] && echo "Usage: $0 <bucket> <contributor> <prev_contribution> [version]" && exit 1

# Dependency checks
if ! command -v gsutil >/dev/null 2>&1; then
    echo "Error: gsutil not found. Please install Google Cloud SDK." >&2
    exit 1
fi

# Parse contribution ID
PREV_NUM=$(echo "$PREV_CONTRIBUTION" | cut -d'_' -f1)
NEXT_NUM=$(printf "%04d" $((10#$PREV_NUM + 1)))
CONTRIBUTION_ID="${NEXT_NUM}_${CONTRIBUTOR}"

# Handle all flag - generate merged JSON with all versions
if [[ "$VERSION" == "all" ]]; then
    # Require jq for merging JSON fragments
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq not found. Please install jq." >&2
        exit 1
    fi
    # Detect available versions from previous contribution
    AVAILABLE_VERSIONS=()
    for ver in v1 v2 batch; do
        if gsutil ls "gs://$BUCKET/ceremony/contributions/$PREV_CONTRIBUTION/$ver/*.ph2" >/dev/null 2>&1; then
            AVAILABLE_VERSIONS+=("$ver")
        fi
    done

    if [[ ${#AVAILABLE_VERSIONS[@]} -eq 0 ]]; then
        echo "Error: No versions found in $PREV_CONTRIBUTION" >&2
        exit 1
    fi

    echo "Found versions: ${AVAILABLE_VERSIONS[*]}"
    echo ""

    # Generate individual JSON files for each version (temporary)
    TEMP_FILES=()
    for ver in "${AVAILABLE_VERSIONS[@]}"; do
        echo "Generating URLs for $ver..."
        TEMP_FILE=$(mktemp)
        TEMP_FILES+=("$TEMP_FILE")

        # Call this script recursively to generate individual version
        "$0" "$BUCKET" "$CONTRIBUTOR" "$PREV_CONTRIBUTION" "$ver" > /dev/null

        # Store the generated file
        mv "${CONTRIBUTION_ID}_${ver}_urls.json" "$TEMP_FILE"
    done

    # Merge JSON files
    OUTPUT_FILE="${CONTRIBUTION_ID}_urls.json"

    {
        echo "{"
        echo "  \"contributor\": \"$CONTRIBUTOR\","
        echo "  \"contribution_id\": \"$CONTRIBUTION_ID\","
        echo "  \"previous_contribution\": \"$PREV_CONTRIBUTION\","
        echo "  \"versions\": ["

        # Add each version as an object in the array
        first=true
        for i in "${!AVAILABLE_VERSIONS[@]}"; do
            ver="${AVAILABLE_VERSIONS[$i]}"
            temp_file="${TEMP_FILES[$i]}"

            [[ "$first" == "false" ]] && echo ","
            first=false

            # Extract download and upload sections from temp file and wrap in version object
            echo "    {"
            echo "      \"version\": \"$ver\","

            # Extract download section
            download=$(jq -c '.download' "$temp_file")
            echo "      \"download\": $download,"

            # Extract upload section
            upload=$(jq -c '.upload' "$temp_file")
            echo -n "      \"upload\": $upload"

            echo ""
            echo -n "    }"
        done

        echo ""
        echo "  ]"
        echo "}"
    } > "$OUTPUT_FILE"

    # Clean up temp files
    for temp_file in "${TEMP_FILES[@]}"; do
        rm -f "$temp_file"
    done

    echo ""
    echo "Generated merged URLs file: $OUTPUT_FILE"
    echo ""
    echo "Send this file to $CONTRIBUTOR for their contribution."
    echo ""
    echo "Note: URLs are valid for 7 days"
    exit 0
fi

# Validate version if provided
if [[ -n "$VERSION" ]] && [[ ! "$VERSION" =~ ^(v1|v2|batch|all)$ ]]; then
    echo "Error: Invalid version: $VERSION"
    echo "Valid versions: v1, v2, batch, all"
    exit 1
fi

# Output filename includes version if specified
if [[ -n "$VERSION" ]]; then
    OUTPUT_FILE="${CONTRIBUTION_ID}_${VERSION}_urls.json"
else
    OUTPUT_FILE="${CONTRIBUTION_ID}_urls.json"
fi

echo "Generating URLs for contribution: $CONTRIBUTION_ID"
echo "Previous contribution: $PREV_CONTRIBUTION"

# Check if we have a service account key for signing
# SECURITY: prefer explicit GOOGLE_APPLICATION_CREDENTIALS; fall back to local file
SERVICE_ACCOUNT_KEY=""
if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]] && [[ -f "${GOOGLE_APPLICATION_CREDENTIALS}" ]]; then
    SERVICE_ACCOUNT_KEY="$GOOGLE_APPLICATION_CREDENTIALS"
elif [[ -f "./service-account-key.json" ]]; then
    SERVICE_ACCOUNT_KEY="./service-account-key.json"
fi

if [[ -z "$SERVICE_ACCOUNT_KEY" ]]; then
    echo "ERROR: No service account key found!" >&2
    echo "Please run: ./create_key.sh <bucket-name>" >&2
    echo "Or set GOOGLE_APPLICATION_CREDENTIALS environment variable" >&2
    exit 1
fi

# Function to generate signed URL or public URL
generate_url() {
    local path="$1"
    local method="${2:-GET}"

    # Use signed URLs with service account key (valid for 7 days)
    gsutil signurl -m "$method" -d 7d "$SERVICE_ACCOUNT_KEY" "gs://$BUCKET/$path" 2>/dev/null | tail -1 | awk '{print $NF}'
}

# Build paths with version subfolder if specified
if [[ -n "$VERSION" ]]; then
    PREV_PATH="$PREV_CONTRIBUTION/$VERSION"
else
    PREV_PATH="$PREV_CONTRIBUTION"
fi

# Check if using local files or GCS
if [[ -d "../contributions/$PREV_PATH" ]]; then
    echo "Using local files from ../contributions/$PREV_PATH"
    shopt -s nullglob
    PH2_FILES=(../contributions/"$PREV_PATH"/*.ph2)
    shopt -u nullglob
else
    echo "Fetching file list from GCS..."
    # Get list of ph2 files into array (portable - works in bash and zsh)
    PH2_FILES=()
    while IFS= read -r line; do
        PH2_FILES+=("$line")
    done < <(gsutil ls "gs://$BUCKET/ceremony/contributions/$PREV_PATH/*.ph2" 2>/dev/null || true)
fi

# Check if we have any files
if [[ ${#PH2_FILES[@]} -eq 0 ]]; then
    echo "Error: No .ph2 files found in $PREV_PATH" >&2
    echo "Please ensure the previous contribution exists before generating URLs." >&2
    exit 1
fi

# Start building JSON
echo "Generating download URLs..."
{
    echo "{"
    echo "  \"contributor\": \"$CONTRIBUTOR\","
    echo "  \"contribution_id\": \"$CONTRIBUTION_ID\","
    echo "  \"previous_contribution\": \"$PREV_CONTRIBUTION\","
    if [[ -n "$VERSION" ]]; then
        echo "  \"version\": \"$VERSION\","
    fi
    echo "  \"download\": {"

    # Process download URLs
    FIRST=true
    for file in "${PH2_FILES[@]}"; do
        [[ ! -e "$file" ]] && [[ -z "$file" ]] && continue

        filename=$(basename "$file")
        [[ "$filename" == "*.ph2" ]] && continue  # Skip glob pattern if no files

        evals_file="${filename%.ph2}.evals"

        # Add comma if not first entry
        [[ "$FIRST" == "false" ]] && echo ","
        FIRST=false

        # Generate and add download URLs
        ph2_url=$(generate_url "ceremony/contributions/$PREV_PATH/$filename" GET)
        echo -n "    \"$filename\": \"$ph2_url\""

        # Check if evals file exists
        if [[ -d "../contributions/$PREV_PATH" ]]; then
            # Local check
            [[ -f "../contributions/$PREV_PATH/$evals_file" ]] && {
                echo ","
                evals_url=$(generate_url "ceremony/contributions/$PREV_PATH/$evals_file" GET)
                echo -n "    \"$evals_file\": \"$evals_url\""
            }
        else
            # GCS check
            gsutil ls "gs://$BUCKET/ceremony/contributions/$PREV_PATH/$evals_file" >/dev/null 2>&1 && {
                echo ","
                evals_url=$(generate_url "ceremony/contributions/$PREV_PATH/$evals_file" GET)
                echo -n "    \"$evals_file\": \"$evals_url\""
            }
        fi
    done

    echo ""
    echo "  },"
    echo "  \"upload\": {"

    # Process upload URLs
    echo "Generating upload URLs..." >&2
    FIRST=true
    for file in "${PH2_FILES[@]}"; do
        [[ ! -e "$file" ]] && [[ -z "$file" ]] && continue

        filename=$(basename "$file")
        [[ "$filename" == "*.ph2" ]] && continue  # Skip glob pattern if no files

        # Extract circuit name by removing .ph2 extension and contribution suffix
        # Removes: _0000 (for init files) or _contributor_contribution_NNNN (for previous contributions)
        base="${filename%.ph2}"
        circuit=$(echo "$base" | sed -E 's/(_0000|_[^_]+_contribution_[0-9]+)$//')

        # Generate new filenames
        new_filename="${circuit}_${CONTRIBUTOR}_contribution_${NEXT_NUM}.ph2"
        new_evals="${circuit}_${CONTRIBUTOR}_contribution_${NEXT_NUM}.evals"

        # Add comma if not first entry
        [[ "$FIRST" == "false" ]] && echo ","
        FIRST=false

        # Generate upload destination with version subfolder if specified
        if [[ -n "$VERSION" ]]; then
            upload_dest="ceremony/contributions/$CONTRIBUTION_ID/$VERSION"
        else
            upload_dest="ceremony/contributions/$CONTRIBUTION_ID"
        fi

        # Generate and add upload URLs
        ph2_upload_url=$(generate_url "$upload_dest/$new_filename" PUT)
        evals_upload_url=$(generate_url "$upload_dest/$new_evals" PUT)

        echo -n "    \"$new_filename\": \"$ph2_upload_url\""
        echo ","
        echo -n "    \"$new_evals\": \"$evals_upload_url\""
    done

    # Add upload URLs for hash and attestation files
    if [[ -n "$VERSION" ]]; then
        meta_dest="ceremony/contributions/$CONTRIBUTION_ID/$VERSION"
    else
        meta_dest="ceremony/contributions/$CONTRIBUTION_ID"
    fi

    hash_upload_url=$(generate_url "$meta_dest/contribution_hashes.txt" PUT)
    echo ","
    echo -n "    \"contribution_hashes.txt\": \"$hash_upload_url\""

    echo ""
    echo "  }"
    echo "}"
} > "$OUTPUT_FILE"

echo "Generated URLs file: $OUTPUT_FILE"
echo ""
echo "Send this file to $CONTRIBUTOR for their contribution."
echo ""
echo "Note: URLs are valid for 7 days"
