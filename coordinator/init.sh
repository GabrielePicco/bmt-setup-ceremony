#!/usr/bin/env bash
set -euo pipefail

# Initialize trusted setup ceremony
# Generates R1CS files and creates initial phase 2 commitments
#
# Usage:
#   ./init.sh          # Initialize V2 ceremony
#   ./init.sh --v1     # Initialize V1 ceremony

VERSION="v2"
if [[ "${1:-}" == "--v1" ]]; then
    VERSION="v1"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIGHT_PROVER="../../light-protocol/prover/server"
R1CS_DIR="$SCRIPT_DIR/../ceremony/r1cs"
CONTRIBUTIONS_DIR="$SCRIPT_DIR/../contributions"
PTAU_FILE="$SCRIPT_DIR/../semaphore-mtb-setup/powersOfTau28_hez_final_19.ptau"
PH1_FILE="$SCRIPT_DIR/../semaphore-mtb-setup/powersOfTau28_hez_final_19.ph1"
SETUP_BIN="$SCRIPT_DIR/../semaphore-mtb-setup/semaphore-mtb-setup"

[[ ! -d "$LIGHT_PROVER" ]] && echo "Error: light-protocol prover not found at $LIGHT_PROVER" && exit 1
[[ ! -f "$SETUP_BIN" ]] && echo "Error: semaphore-mtb-setup binary not found. Build it first: cd ../semaphore-mtb-setup && go build" && exit 1

mkdir -p "$R1CS_DIR"
mkdir -p "$CONTRIBUTIONS_DIR"

echo "========================================="
echo "Initializing $VERSION Ceremony"
echo "========================================="
echo ""

# Step 1: Generate R1CS files
echo "Step 1: Generating R1CS files..."
echo ""

cd "$LIGHT_PROVER"

total_r1cs=0
success_r1cs=0

if [[ "$VERSION" == "v1" ]]; then
    echo "=== V1 R1CS Generation ==="

    # V1 Combined circuits
    for inclusion_accts in 1 2 3 4 8; do
        for non_inclusion_accts in 1 2 4 8; do
            circuit_name="v1_combined_26_${inclusion_accts}_${non_inclusion_accts}"
            total_r1cs=$((total_r1cs + 1))

            echo -n "  $circuit_name.r1cs ... "
            if go run main.go r1cs --circuit combined --legacy \
                --inclusion-tree-height 26 \
                --inclusion-compressed-accounts $inclusion_accts \
                --non-inclusion-tree-height 26 \
                --non-inclusion-compressed-accounts $non_inclusion_accts \
                --output "$R1CS_DIR/${circuit_name}.r1cs" >/dev/null 2>&1; then
                success_r1cs=$((success_r1cs + 1))
                echo "✓"
            else
                echo "✗"
            fi
        done
    done

    # V1 Inclusion circuits
    for accts in 1 2 3 4 8; do
        circuit_name="v1_inclusion_26_${accts}"
        total_r1cs=$((total_r1cs + 1))

        echo -n "  $circuit_name.r1cs ... "
        if go run main.go r1cs --circuit inclusion --legacy \
            --inclusion-tree-height 26 \
            --inclusion-compressed-accounts $accts \
            --output "$R1CS_DIR/${circuit_name}.r1cs" >/dev/null 2>&1; then
            success_r1cs=$((success_r1cs + 1))
            echo "✓"
        else
            echo "✗"
        fi
    done

    # V1 Non-inclusion circuits
    for accts in 1 2; do
        circuit_name="v1_non-inclusion_26_${accts}"
        total_r1cs=$((total_r1cs + 1))

        echo -n "  $circuit_name.r1cs ... "
        if go run main.go r1cs --circuit non-inclusion --legacy \
            --non-inclusion-tree-height 26 \
            --non-inclusion-compressed-accounts $accts \
            --output "$R1CS_DIR/${circuit_name}.r1cs" >/dev/null 2>&1; then
            success_r1cs=$((success_r1cs + 1))
            echo "✓"
        else
            echo "✗"
        fi
    done

else
    echo "=== V2 R1CS Generation ==="

    # V2 Combined circuits
    for inclusion_accts in 1 2 3 4; do
        for non_inclusion_accts in 1 2 3 4; do
            circuit_name="v2_combined_32_${inclusion_accts}_${non_inclusion_accts}"
            total_r1cs=$((total_r1cs + 1))

            echo -n "  $circuit_name.r1cs ... "
            if go run main.go r1cs --circuit combined \
                --inclusion-tree-height 32 \
                --inclusion-compressed-accounts $inclusion_accts \
                --non-inclusion-tree-height 40 \
                --non-inclusion-compressed-accounts $non_inclusion_accts \
                --output "$R1CS_DIR/${circuit_name}.r1cs" >/dev/null 2>&1; then
                success_r1cs=$((success_r1cs + 1))
                echo "✓"
            else
                echo "✗"
            fi
        done
    done

    # V2 Inclusion circuits
    for accts in {1..20}; do
        circuit_name="v2_inclusion_32_${accts}"
        total_r1cs=$((total_r1cs + 1))

        echo -n "  $circuit_name.r1cs ... "
        if go run main.go r1cs --circuit inclusion \
            --inclusion-tree-height 32 \
            --inclusion-compressed-accounts $accts \
            --output "$R1CS_DIR/${circuit_name}.r1cs" >/dev/null 2>&1; then
            success_r1cs=$((success_r1cs + 1))
            echo "✓"
        else
            echo "✗"
        fi
    done

    # V2 Non-inclusion circuits
    for accts in {1..32}; do
        circuit_name="v2_non-inclusion_40_${accts}"
        total_r1cs=$((total_r1cs + 1))

        echo -n "  $circuit_name.r1cs ... "
        if go run main.go r1cs --circuit non-inclusion \
            --non-inclusion-tree-height 40 \
            --non-inclusion-compressed-accounts $accts \
            --output "$R1CS_DIR/${circuit_name}.r1cs" >/dev/null 2>&1; then
            success_r1cs=$((success_r1cs + 1))
            echo "✓"
        else
            echo "✗"
        fi
    done

    # V2 Batch circuits
    echo -n "  batch_append_32_500.r1cs ... "
    total_r1cs=$((total_r1cs + 1))
    if go run main.go r1cs --circuit append \
        --append-tree-height 32 --append-batch-size 500 \
        --output "$R1CS_DIR/batch_append_32_500.r1cs" >/dev/null 2>&1; then
        success_r1cs=$((success_r1cs + 1))
        echo "✓"
    else
        echo "✗"
    fi

    echo -n "  batch_update_32_500.r1cs ... "
    total_r1cs=$((total_r1cs + 1))
    if go run main.go r1cs --circuit update \
        --update-tree-height 32 --update-batch-size 500 \
        --output "$R1CS_DIR/batch_update_32_500.r1cs" >/dev/null 2>&1; then
        success_r1cs=$((success_r1cs + 1))
        echo "✓"
    else
        echo "✗"
    fi

    echo -n "  batch_address-append_40_250.r1cs ... "
    total_r1cs=$((total_r1cs + 1))
    if go run main.go r1cs --circuit address-append \
        --address-append-tree-height 40 --address-append-batch-size 250 \
        --output "$R1CS_DIR/batch_address-append_40_250.r1cs" >/dev/null 2>&1; then
        success_r1cs=$((success_r1cs + 1))
        echo "✓"
    else
        echo "✗"
    fi
fi

echo ""
echo "R1CS Generation: $success_r1cs/$total_r1cs successful"
echo ""

# Step 2: Convert powers of tau
echo "Step 2: Setting up powers of tau..."

if [[ ! -f "$PH1_FILE" ]]; then
    if [[ ! -f "$PTAU_FILE" ]]; then
        echo "Downloading powers of tau..."
        curl -L -o "$PTAU_FILE" \
            "https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_19.ptau"
    fi

    echo "  Converting ptau to ph1 format..."
    "$SETUP_BIN" p1i "$PTAU_FILE" "$PH1_FILE"
fi
echo "  ✓ Powers of tau ready"
echo ""

# Step 3: Create initial commitments
echo "Step 3: Creating initial phase 2 commitments..."
echo ""

total_commitments=0
success_commitments=0

# Determine which R1CS files to process
if [[ "$VERSION" == "v2" ]]; then
    # V2: Process both v2_* and batch_* files
    R1CS_PATTERNS=("$R1CS_DIR/v2_"*.r1cs "$R1CS_DIR/batch_"*.r1cs)
else
    # V1: Process v1_* files
    R1CS_PATTERNS=("$R1CS_DIR/$VERSION"*.r1cs)
fi

for pattern in "${R1CS_PATTERNS[@]}"; do
    for r1cs in $pattern; do
        [[ ! -f "$r1cs" ]] && continue

        base=$(basename "$r1cs" .r1cs)
        ph2_file="$CONTRIBUTIONS_DIR/${base}_0000.ph2"

        # Skip if already exists
        if [[ -f "$ph2_file" ]]; then
            echo "  $base ... (exists)"
            success_commitments=$((success_commitments + 1))
            total_commitments=$((total_commitments + 1))
            continue
        fi

        total_commitments=$((total_commitments + 1))
        echo -n "  $base ... "

        if "$SETUP_BIN" p2n "$PH1_FILE" "$r1cs" "$ph2_file" >/dev/null 2>&1; then
            success_commitments=$((success_commitments + 1))
            echo "✓"
        else
            echo "✗"
        fi
    done
done

echo ""

# Move initial commitments to 0000_initial directory with subdirectories
INITIAL_DIR="$CONTRIBUTIONS_DIR/0000_initial"
mkdir -p "$INITIAL_DIR/$VERSION"

echo "Organizing initial commitments..."
moved_count=0

if [[ "$VERSION" == "v2" ]]; then
    # Split V2 into v2/ and batch/ subdirectories
    mkdir -p "$INITIAL_DIR/batch"
    mkdir -p "$INITIAL_DIR/v2/r1cs"
    mkdir -p "$INITIAL_DIR/batch/r1cs"

    # Move batch circuits (batch_* naming)
    for f in "$CONTRIBUTIONS_DIR/batch_"*_0000.ph2 "$CONTRIBUTIONS_DIR/batch_"*_0000.evals; do
        [[ -f "$f" ]] && mv "$f" "$INITIAL_DIR/batch/" && moved_count=$((moved_count + 1))
    done

    # Move non-batch V2 circuits (v2_* naming)
    for f in "$CONTRIBUTIONS_DIR/v2_"*_0000.ph2 "$CONTRIBUTIONS_DIR/v2_"*_0000.evals; do
        [[ -f "$f" ]] && mv "$f" "$INITIAL_DIR/v2/" && moved_count=$((moved_count + 1))
    done

    # Copy R1CS files
    echo "  Copying R1CS files..."
    cp "$R1CS_DIR/batch"*.r1cs "$INITIAL_DIR/batch/r1cs/" 2>/dev/null || true
    cp "$R1CS_DIR/v2_"*.r1cs "$INITIAL_DIR/v2/r1cs/" 2>/dev/null || true
else
    # V1 circuits go to v1/
    mkdir -p "$INITIAL_DIR/$VERSION/r1cs"

    for f in "$CONTRIBUTIONS_DIR/${VERSION}"*_0000.ph2 "$CONTRIBUTIONS_DIR/${VERSION}"*_0000.evals; do
        [[ -f "$f" ]] && mv "$f" "$INITIAL_DIR/$VERSION/" && moved_count=$((moved_count + 1))
    done

    # Copy R1CS files
    echo "  Copying R1CS files..."
    cp "$R1CS_DIR/${VERSION}"*.r1cs "$INITIAL_DIR/$VERSION/r1cs/" 2>/dev/null || true
fi

echo "  Moved $moved_count commitment files"
echo ""

echo "========================================="
echo "Ceremony Initialization Complete!"
echo "========================================="
echo "R1CS files: $success_r1cs/$total_r1cs"
echo "Initial commitments: $success_commitments/$total_commitments"
echo ""
echo "Generated files:"
echo "  R1CS: $R1CS_DIR/$VERSION*.r1cs"
if [[ "$VERSION" == "v2" ]]; then
    echo "  V2 Commitments: $INITIAL_DIR/v2/"
    echo "  Batch Commitments: $INITIAL_DIR/batch/"
else
    echo "  Commitments: $INITIAL_DIR/$VERSION/"
fi
echo ""
echo "Next steps:"
echo "  1. Upload: ./upload.sh $VERSION"
echo "  2. Generate URLs: ./generate_urls.sh <bucket> <contributor> 0000_initial/$VERSION"
echo "  3. Share URLs with participants"
echo "  4. After contributions, run: ./verify.sh"
echo "  5. Finally, run: ./finalize.sh"
echo ""
