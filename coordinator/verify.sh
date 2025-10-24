#!/usr/bin/env bash
set -euo pipefail

# Verify a contribution
# Usage: ./verify.sh <contribution_id> [bucket]

CONTRIBUTION_ID="${1:-}"
BUCKET="${2:-light-protocol-proving-keys}"
SEMAPHORE_MTB_BIN="../semaphore-mtb-setup/semaphore-mtb-setup"
INITIAL_DIR="../contributions/0000_initial"
TEMP_DIR="./verify_temp_$$"

[[ -z "$CONTRIBUTION_ID" ]] && echo "Usage: $0 <contribution_id> [bucket]" && exit 1

[[ ! -f "$SEMAPHORE_MTB_BIN" ]] && echo "Error: semaphore-mtb-setup binary not found at $SEMAPHORE_MTB_BIN" && exit 1

# Download initial contributions if they don't exist
if [[ ! -d "$INITIAL_DIR" ]]; then
    echo "Initial contribution directory not found. Downloading from GCS..."
    mkdir -p "$INITIAL_DIR"
    if ! gsutil -m cp -r "gs://$BUCKET/ceremony/contributions/0000_initial/*" "$INITIAL_DIR/" 2>/dev/null; then
        echo "Error: Could not download initial contributions from GCS"
        rm -rf "$INITIAL_DIR"
        exit 1
    fi
    echo "Initial contributions downloaded successfully"
fi

# Check if contribution is local or in GCS
if [[ -d "../contributions/$CONTRIBUTION_ID" ]]; then
    echo "Using local contribution: ../contributions/$CONTRIBUTION_ID"
    CONTRIBUTION_DIR="../contributions/$CONTRIBUTION_ID"
else
    echo "Downloading contribution from GCS: gs://$BUCKET/ceremony/contributions/$CONTRIBUTION_ID/"

    # Create temp directory and download with subdirectories
    mkdir -p "$TEMP_DIR"
    if ! gsutil -m cp -r "gs://$BUCKET/ceremony/contributions/$CONTRIBUTION_ID/*" "$TEMP_DIR/" 2>/dev/null; then
        echo "Error: Could not download contribution from GCS"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    CONTRIBUTION_DIR="$TEMP_DIR"
fi

# Verify function for a single version directory
verify_version() {
    local version_dir="$1"
    local version_name="$2"
    local local_failed=0
    local local_total=0

    echo ""
    echo "Verifying $version_name circuits..."

    shopt -s nullglob
    for ph2_file in "$version_dir"/*.ph2; do
        [[ ! -f "$ph2_file" ]] && continue

        local_total=$((local_total + 1))
        base=$(basename "$ph2_file" .ph2)
        circuit=$(echo "$base" | sed -E 's/_[^_]+_contribution_[0-9]+$//')

        # Find initial file with correct naming: circuit_0000.ph2
        initial_file="$INITIAL_DIR/$version_name/${circuit}_0000.ph2"

        if [[ ! -f "$initial_file" ]]; then
            echo "FAIL: $circuit - Initial file not found: $initial_file"
            local_failed=$((local_failed + 1))
            continue
        fi

        # Verify
        if "$SEMAPHORE_MTB_BIN" p2v "$ph2_file" "$initial_file" >/dev/null 2>&1; then
            echo "PASS: $circuit"
        else
            echo "FAIL: $circuit - Verification failed"
            local_failed=$((local_failed + 1))
        fi
    done

    if [[ $local_total -eq 0 ]]; then
        echo "No circuits found in $version_name"
    fi

    echo "$version_name: $((local_total - local_failed))/$local_total verified"
    echo "$local_failed $local_total"
}

# Verify each version subdirectory
failed=0
total=0

for version in v1 v2 batch; do
    version_dir="$CONTRIBUTION_DIR/$version"
    if [[ -d "$version_dir" ]]; then
        result=$(verify_version "$version_dir" "$version")
        version_failed=$(echo "$result" | tail -1 | cut -d' ' -f1)
        version_total=$(echo "$result" | tail -1 | cut -d' ' -f2)
        failed=$((failed + version_failed))
        total=$((total + version_total))
    fi
done

# If no version subdirectories, check root directory (legacy support)
if [[ $total -eq 0 ]]; then
    echo "No version subdirectories found, checking root directory..."
    shopt -s nullglob
    for ph2_file in "$CONTRIBUTION_DIR"/*.ph2; do
        [[ ! -f "$ph2_file" ]] && continue

        total=$((total + 1))
        base=$(basename "$ph2_file" .ph2)
        circuit=$(echo "$base" | sed -E 's/_[^_]+_contribution_[0-9]+$//')

        # Try to find initial file in any version directory
        initial_file=""
        for ver in v1 v2 batch; do
            candidate="$INITIAL_DIR/$ver/${circuit}_0000.ph2"
            if [[ -f "$candidate" ]]; then
                initial_file="$candidate"
                break
            fi
        done

        if [[ -z "$initial_file" ]]; then
            echo "FAIL: $circuit - Initial file not found"
            failed=$((failed + 1))
            continue
        fi

        # Verify
        if "$SEMAPHORE_MTB_BIN" p2v "$ph2_file" "$initial_file" >/dev/null 2>&1; then
            echo "PASS: $circuit"
        else
            echo "FAIL: $circuit - Verification failed"
            failed=$((failed + 1))
        fi
    done
fi

# Clean up temp directory if used
[[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"

echo ""
echo "========================================="
echo "Verification Complete"
echo "========================================="
echo "Total: $((total - failed))/$total circuits verified"
[[ $failed -gt 0 ]] && echo "Failed: $failed circuits"
echo ""

[[ $failed -eq 0 ]] && [[ $total -gt 0 ]] && exit 0 || exit 1
