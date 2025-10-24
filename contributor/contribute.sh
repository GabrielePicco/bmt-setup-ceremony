#!/usr/bin/env bash
set -euo pipefail

# Usage: curl -sSL https://gist.github.com/sergeytimoshin/contribute.sh | bash -s <urls.json>
#    or: ./contribute.sh <urls.json>

URLS_FILE="${1:-}"
WORK_DIR="./ceremony_contribution_$(date +%s)"
SEMAPHORE_REPO="https://github.com/lightprotocol/semaphore-mtb-setup.git"
SEMAPHORE_DIR="$WORK_DIR/semaphore-mtb-setup"
SEMAPHORE_REF="${SEMAPHORE_REF:-}"

[[ -z "$URLS_FILE" ]] && echo "Usage: $0 <urls.json>" && exit 1
[[ ! -f "$URLS_FILE" ]] && echo "Error: $URLS_FILE not found" && exit 1


check_dependencies() {
    local missing=()

    command -v jq >/dev/null 2>&1 || missing+=("jq")
    command -v git >/dev/null 2>&1 || missing+=("git")
    command -v go >/dev/null 2>&1 || missing+=("go")
    command -v curl >/dev/null 2>&1 || missing+=("curl")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: Missing required dependencies: ${missing[*]}"
        echo ""
        echo "Please install them first:"
        echo "  Ubuntu/Debian: apt-get install ${missing[*]}"
        echo "  macOS: brew install ${missing[*]}"
        echo "  Fedora: dnf install ${missing[*]}"
        exit 1
    fi
}

process_version() {
    local version="$1"
    local download_section="$2"
    local upload_section="$3"

    echo " Processing Version: $version"
    echo ""

    echo "Downloading previous contribution ($version)..."
    while IFS='|' read -r filename url; do
        echo "  Downloading $filename"

        retry=0
        max_retries=10
        while [[ $retry -lt $max_retries ]]; do
            if curl -sSL "$url" \
                --connect-timeout 60 \
                --max-time 3600 \
                --retry 3 \
                --retry-delay 5 \
                -o "$WORK_DIR/download/$filename"; then
                echo "    Download successful"
                break
            else
                retry=$((retry + 1))
                if [[ $retry -lt $max_retries ]]; then
                    delay=$((5 * (2 ** (retry - 1))))
                    [[ $delay -gt 300 ]] && delay=300
                    echo "    Download failed, retrying in ${delay}s ($retry/$max_retries)..."
                    sleep $delay
                else
                    echo "    Download failed after $max_retries attempts"
                    echo "Error: Failed to download $filename after $max_retries attempts"
                    echo "Please cleanup the workspace and restart the entire process afterwards. If the issues persist, please contact the coordinator. Clean up via: rm -rf $WORK_DIR"
                    exit 1
                fi
            fi
        done
    done < <(echo "$download_section" | jq -r 'to_entries[] | "\(.key)|\(.value)"')

    echo ""
    echo "Adding your contribution to $version circuits..."
    echo ""

    circuit_count=0
    for ph2_file in "$WORK_DIR"/download/*.ph2; do
        [[ ! -f "$ph2_file" ]] && continue

        base=$(basename "$ph2_file" .ph2)
        circuit=$(echo "$base" | sed -E 's/(_0000|_[^_]+_contribution_[0-9]+)$//')

        num=$(echo "$CONTRIBUTION_ID" | cut -d'_' -f1)
        output_file="$WORK_DIR/output/${circuit}_${CONTRIBUTOR}_contribution_${num}.ph2"

        echo "  Contributing to $circuit..."
        hash=$("$SEMAPHORE_BIN" p2c "$ph2_file" "$output_file" 2>&1 | tail -1)
        
        if [[ ! -f "$output_file" ]]; then
            echo "Error: Contribution failed for $circuit (output file not created)"
            echo "Please cleanup the workspace and restart the entire process afterwards. If the issues persist, please contact the coordinator. Clean up via: rm -rf $WORK_DIR"
            exit 1
        fi
        
        echo "$circuit: $hash" >> "$hash_file"

        [[ -f "${ph2_file%.ph2}.evals" ]] && \
            cp "${ph2_file%.ph2}.evals" "${output_file%.ph2}.evals"

        circuit_count=$((circuit_count + 1))
    done

    if [[ $circuit_count -eq 0 ]]; then
        echo "Error: No circuits were processed"
        echo "Please cleanup the workspace and restart the entire process afterwards. If the issues persist, please contact the coordinator. Clean up via: rm -rf $WORK_DIR"
        exit 1
    fi

    echo ""
    echo "Contributed to $circuit_count $version circuits"

    echo ""
    echo "Uploading $version contribution..."
    upload_count=0
    while IFS='|' read -r filename url; do
        local_file="$WORK_DIR/output/$filename"
        
        if [[ ! -f "$local_file" ]]; then
            echo "Error: Expected output file not found: $filename"
            echo "Please cleanup the workspace and restart the entire process afterwards. If the issues persist, please contact the coordinator. Clean up via: rm -rf $WORK_DIR"
            exit 1
        fi
        
        echo "  Uploading $filename ($(du -h "$local_file" | cut -f1))"

        retry=0
        max_retries=10
        while [[ $retry -lt $max_retries ]]; do
            if curl -X PUT -H "Content-Type: application/octet-stream" \
                --upload-file "$local_file" \
                --connect-timeout 60 \
                --max-time 3600 \
                --retry 3 \
                --retry-delay 5 \
                "$url" -s -o /dev/null -w "%{http_code}" | grep -q "^20[0-9]"; then
                echo "    Upload successful"
                break
            else
                retry=$((retry + 1))
                if [[ $retry -lt $max_retries ]]; then
                    delay=$((5 * (2 ** (retry - 1))))
                    [[ $delay -gt 300 ]] && delay=300
                    echo "    Upload failed, retrying in ${delay}s ($retry/$max_retries)..."
                    sleep $delay
                else
                    echo "    Upload failed after $max_retries attempts"
                    echo "Error: Failed to upload $filename after $max_retries attempts"
                    echo "Please cleanup the workspace and restart the entire process afterwards. If the issues persist, please contact the coordinator. Clean up via: rm -rf $WORK_DIR"
                    exit 1
                fi
            fi
        done
        upload_count=$((upload_count + 1))
    done < <(echo "$upload_section" | jq -r 'to_entries[] | "\(.key)|\(.value)"')

    mkdir -p "$WORK_DIR/verify_inputs/$version"
    cp "$WORK_DIR"/download/*.ph2 "$WORK_DIR/verify_inputs/$version"/ 2>/dev/null || true
    cp "$WORK_DIR"/download/*.evals "$WORK_DIR/verify_inputs/$version"/ 2>/dev/null || true
    rm -f "$WORK_DIR"/download/*

    echo ""
    echo "Completed $version contribution"
    echo ""
}

main() {
    echo "========================================="
    echo "BMT Trusted Setup Ceremony for ZK Compression"
    echo "========================================="
    echo ""

    check_dependencies

    CONTRIBUTOR=$(jq -r '.contributor' "$URLS_FILE")
    CONTRIBUTION_ID=$(jq -r '.contribution_id' "$URLS_FILE")

    echo "Contributor: $CONTRIBUTOR"
    echo "Contribution ID: $CONTRIBUTION_ID"
    echo ""

    echo "Setting up workspace..."
    mkdir -p "$WORK_DIR"/{download,output}

    echo "Preparing ceremony tools..."
    git clone --quiet --depth 1 "$SEMAPHORE_REPO" "$SEMAPHORE_DIR"
    if [[ -n "$SEMAPHORE_REF" ]]; then
        (cd "$SEMAPHORE_DIR" && git fetch --quiet --depth 1 origin "$SEMAPHORE_REF" && git checkout --quiet "$SEMAPHORE_REF") || {
            echo "Error: Failed to checkout semaphore-mtb-setup ref: $SEMAPHORE_REF"
            echo "Please cleanup the workspace and restart the entire process afterwards. If the issues persist, please contact the coordinator. Clean up via: rm -rf $WORK_DIR"
            exit 1
        }
    fi
    (cd "$SEMAPHORE_DIR" && go build -o semaphore-mtb-setup .) || {
        echo "Error: Failed to build semaphore-mtb-setup"
        echo "Please cleanup the workspace and restart the entire process afterwards. If the issues persist, please contact the coordinator. Clean up via: rm -rf $WORK_DIR"
        exit 1
    }
    SEMAPHORE_BIN="$SEMAPHORE_DIR/semaphore-mtb-setup"

    hash_file="$WORK_DIR/output/contribution_hashes.txt"
    {
        echo "Contribution: $CONTRIBUTION_ID"
        echo "Contributor: $CONTRIBUTOR"
        echo "Date: $(date -u)"
        echo ""
        echo "Circuit contributions:"
    } > "$hash_file"

    if jq -e '.versions' "$URLS_FILE" >/dev/null 2>&1; then
        version_count=$(jq '.versions | length' "$URLS_FILE")
        for ((i=0; i<version_count; i++)); do
            version=$(jq -r ".versions[$i].version" "$URLS_FILE")
            download_section=$(jq -c ".versions[$i].download" "$URLS_FILE")
            upload_section=$(jq -c ".versions[$i].upload" "$URLS_FILE")

            process_version "$version" "$download_section" "$upload_section"
        done
    else
        # Download previous contribution
        echo "Downloading previous contribution..."
        while IFS='|' read -r filename url; do
            echo "  Downloading $filename"

            # Retry download up to 10 times with exponential backoff
            retry=0
            max_retries=10
            while [[ $retry -lt $max_retries ]]; do
                if curl -sSL "$url" \
                    --connect-timeout 60 \
                    --max-time 3600 \
                    --retry 3 \
                    --retry-delay 5 \
                    -o "$WORK_DIR/download/$filename"; then
                    echo "    Download successful"
                    break
                else
                    retry=$((retry + 1))
                    if [[ $retry -lt $max_retries ]]; then
                        delay=$((5 * (2 ** (retry - 1))))
                        [[ $delay -gt 300 ]] && delay=300
                        echo "    Download failed, retrying in ${delay}s ($retry/$max_retries)..."
                        sleep $delay
                    else
                        echo "    Download failed after $max_retries attempts"
                        echo "Error: Failed to download $filename after $max_retries attempts"
                        echo "Please cleanup the workspace and restart the entire process afterwards. If the issues persist, please contact the coordinator. Clean up via: rm -rf $WORK_DIR"
                        exit 1
                    fi
                fi
            done
        done < <(jq -r '.download | to_entries[] | "\(.key)|\(.value)"' "$URLS_FILE")

        mkdir -p "$WORK_DIR/verify_inputs"
        cp "$WORK_DIR"/download/*.ph2 "$WORK_DIR/verify_inputs"/ 2>/dev/null || true
        cp "$WORK_DIR"/download/*.evals "$WORK_DIR/verify_inputs"/ 2>/dev/null || true

        echo ""
        echo "Adding your contribution to circuits..."
        echo "This may take from several minutes to several hours depending on your machine."
        echo "Please be patient and do not interrupt the process."
        echo ""

        circuit_count=0
        for ph2_file in "$WORK_DIR"/download/*.ph2; do
            [[ ! -f "$ph2_file" ]] && continue

            base=$(basename "$ph2_file" .ph2)
            # Remove _0000 suffix (for init files) or _contributor_contribution_num (for previous contributions)
            circuit=$(echo "$base" | sed -E 's/(_0000|_[^_]+_contribution_[0-9]+)$//')


            num=$(echo "$CONTRIBUTION_ID" | cut -d'_' -f1)
            output_file="$WORK_DIR/output/${circuit}_${CONTRIBUTOR}_contribution_${num}.ph2"

            # Add entropy and contribute
            echo "  Contributing to $circuit..."
            hash=$("$SEMAPHORE_BIN" p2c "$ph2_file" "$output_file" 2>&1 | tail -1)
            
            if [[ ! -f "$output_file" ]]; then
                echo "Error: Contribution failed for $circuit (output file not created)"
                echo "Please cleanup the workspace and restart the entire process afterwards. If the issues persist, please contact the coordinator. Clean up via: rm -rf $WORK_DIR"
                exit 1
            fi
            
            echo "$circuit: $hash" >> "$hash_file"

            # Copy evals file if exists
            [[ -f "${ph2_file%.ph2}.evals" ]] && \
                cp "${ph2_file%.ph2}.evals" "${output_file%.ph2}.evals"

            circuit_count=$((circuit_count + 1))
        done

        if [[ $circuit_count -eq 0 ]]; then
            echo "Error: No circuits were processed"
            echo "Please cleanup the workspace and restart the entire process afterwards. If the issues persist, please contact the coordinator. Clean up via: rm -rf $WORK_DIR"
            exit 1
        fi

        echo ""
        echo "Contributed to $circuit_count circuits"
        echo ""


        echo "Uploading your contribution..."
        upload_count=0
        while IFS='|' read -r filename url; do
            local_file="$WORK_DIR/output/$filename"
            
            if [[ ! -f "$local_file" ]]; then
                echo "Error: Expected output file not found: $filename"
                echo "Please cleanup the workspace and restart the entire process afterwards. If the issues persist, please contact the coordinator. Clean up via: rm -rf $WORK_DIR"
                exit 1
            fi
            
            echo "  Uploading $filename ($(du -h "$local_file" | cut -f1))"

            retry=0
            max_retries=10
            while [[ $retry -lt $max_retries ]]; do
                if curl -X PUT -H "Content-Type: application/octet-stream" \
                    --upload-file "$local_file" \
                    --connect-timeout 60 \
                    --max-time 3600 \
                    --retry 3 \
                    --retry-delay 5 \
                    "$url" -s -o /dev/null -w "%{http_code}" | grep -q "^20[0-9]"; then
                    echo "    Upload successful"
                    break
                else
                    retry=$((retry + 1))
                    if [[ $retry -lt $max_retries ]]; then
                        delay=$((5 * (2 ** (retry - 1))))
                        [[ $delay -gt 300 ]] && delay=300
                        echo "    Upload failed, retrying in ${delay}s ($retry/$max_retries)..."
                        sleep $delay
                    else
                        echo "    Upload failed after $max_retries attempts"
                        echo "Error: Failed to upload $filename after $max_retries attempts"
                        echo "Please cleanup the workspace and restart the entire process afterwards. If the issues persist, please contact the coordinator. Clean up via: rm -rf $WORK_DIR"
                        exit 1
                    fi
                fi
            done
            upload_count=$((upload_count + 1))
        done < <(jq -r '.upload | to_entries[] | "\(.key)|\(.value)"' "$URLS_FILE")
    fi

    echo ""
    echo "========================================="
    echo " Contribution Complete!"
    echo "========================================="
    echo ""
    cat "$hash_file"
    echo ""
    echo "Attestation instructions:"
    echo "1) Save the file above: $hash_file"
    echo "2) Keep a local copy in a safe place"
    echo "3) Optionally publish a public attestation (choose one):"
    echo "   - Upload the file as a GitHub Gist and share the link"
    echo "   - Or open a PR to add it under attestations/<contribution_id> in this repo"
    echo "   - Or publish the SHA256 of the file: shasum -a 256 $hash_file"

    if command -v shasum >/dev/null 2>&1; then
        hash_sha=$(shasum -a 256 "$hash_file" | awk '{print $1}')
        echo "SHA256(contribution_hashes.txt): $hash_sha"
    elif command -v sha256sum >/dev/null 2>&1; then
        hash_sha=$(sha256sum "$hash_file" | awk '{print $1}')
        echo "SHA256(contribution_hashes.txt): $hash_sha"
    fi
    echo ""
    echo "Offline verification inputs saved in: $WORK_DIR/verify_inputs"
    echo "Thank you for contributing to ZK Compression on Solana!"
}

main