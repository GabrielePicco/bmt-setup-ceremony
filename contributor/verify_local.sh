#!/usr/bin/env bash
set -euo pipefail

# Verify a contributor's latest local contribution using saved offline inputs.
# Usage: ./verify_local.sh [verify_inputs_dir] [semaphore_bin] [expected_hashes_file]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

VERIFY_DIR="${1:-}"
SEMAPHORE_BIN="${2:-}"
EXPECTED_HASHES_FILE="${3:-}"
VERIF_LOG="${VERIF_LOG:-$SCRIPT_DIR/verification_hashes.txt}"

if [[ -z "$VERIFY_DIR" ]]; then
  # Pick the latest contribution workspace by timestamp in the contributor folder
  latest_dir=$(ls -d "$SCRIPT_DIR"/ceremony_contribution_* 2>/dev/null | sort | tail -1 || true)
  if [[ -z "${latest_dir:-}" ]]; then
    echo "Error: No contribution workspace found under $SCRIPT_DIR/ceremony_contribution_*"
    echo "Hint: Run contribute.sh first on this machine, or pass a path to verify_inputs explicitly."
    exit 1
  fi
  VERIFY_DIR="$latest_dir/verify_inputs"
fi

if [[ -z "$SEMAPHORE_BIN" ]]; then
  # Prefer repo binary; fall back to contribution's built binary
  if [[ -f "$ROOT_DIR/semaphore-mtb-setup/semaphore-mtb-setup" ]]; then
    SEMAPHORE_BIN="$ROOT_DIR/semaphore-mtb-setup/semaphore-mtb-setup"
  elif [[ -f "${latest_dir:-}/semaphore-mtb-setup/semaphore-mtb-setup" ]]; then
    SEMAPHORE_BIN="${latest_dir}/semaphore-mtb-setup/semaphore-mtb-setup"
  else
    echo "Error: semaphore-mtb-setup binary not found."
    echo "Build it with: (cd $ROOT_DIR/semaphore-mtb-setup && go build -o semaphore-mtb-setup .)"
    exit 1
  fi
fi

[[ ! -x "$SEMAPHORE_BIN" ]] && echo "Error: $SEMAPHORE_BIN is not executable" && exit 1

INITIAL_DIR="$ROOT_DIR/contributions/0000_initial"
if [[ ! -d "$INITIAL_DIR" ]]; then
  echo "Warning: $INITIAL_DIR not found."
  echo "You need the initial 0000 parameters to verify. Ask the coordinator for read links if needed."
fi

echo "VERIFY_DIR: $VERIFY_DIR"
echo "SEMAPHORE_BIN: $SEMAPHORE_BIN"
echo "INITIAL_DIR: $INITIAL_DIR"
echo ""

total=0
failed=0

# Initialize verification log (per-circuit hashes of verified inputs)
{
  echo "Verification Hashes"
  echo "Date: $(date -u)"
  echo "VerifyDir: $VERIFY_DIR"
  echo ""
} > "$VERIF_LOG"

for ver in v1 v2 batch; do
  ver_dir="$VERIFY_DIR/$ver"
  [[ -d "$ver_dir" ]] || continue
  shopt -s nullglob
  for f in "$ver_dir"/*.ph2; do
    [[ -f "$f" ]] || continue
    total=$((total + 1))
    base=$(basename "$f" .ph2)
    circuit=$(echo "$base" | sed -E 's/(_0000|_[^_]+_contribution_[0-9]+)$//')
    initial="$INITIAL_DIR/$ver/${circuit}_0000.ph2"
    if [[ ! -f "$initial" ]]; then
      echo "SKIP: $circuit (initial not found: $initial)"
      failed=$((failed + 1))
      continue
    fi
    if "$SEMAPHORE_BIN" p2v "$f" "$initial" >/dev/null 2>&1; then
      echo "PASS: $circuit"
    else
      echo "FAIL: $circuit"
      failed=$((failed + 1))
    fi

    # Compute per-circuit SHA256 of the verified contribution file for manual comparison
    if command -v shasum >/dev/null 2>&1; then
      file_sha=$(shasum -a 256 "$f" | awk '{print $1}')
    elif command -v sha256sum >/dev/null 2>&1; then
      file_sha=$(sha256sum "$f" | awk '{print $1}')
    else
      file_sha="NO_SHA_TOOL"
    fi
    echo "$circuit: $file_sha" >> "$VERIF_LOG"
  done
  shopt -u nullglob
done

echo ""
echo "Verified: $((total - failed))/$total circuits"

# Show verification log digest for sharing/comparison
if command -v shasum >/dev/null 2>&1; then
  verif_log_sha=$(shasum -a 256 "$VERIF_LOG" | awk '{print $1}')
elif command -v sha256sum >/dev/null 2>&1; then
  verif_log_sha=$(sha256sum "$VERIF_LOG" | awk '{print $1}')
else
  verif_log_sha="NO_SHA_TOOL"
fi
echo ""
echo "Verification log: $VERIF_LOG"
echo "SHA256(verification_hashes.txt): $verif_log_sha"

# Also show the contribution hashes file digest if present
hash_file_candidate=$(ls "$SCRIPT_DIR"/ceremony_contribution_*/output/contribution_hashes.txt 2>/dev/null | sort | tail -1 || true)
if [[ -f "${hash_file_candidate:-}" ]]; then
  if command -v shasum >/dev/null 2>&1; then
    hash_sha=$(shasum -a 256 "$hash_file_candidate" | awk '{print $1}')
  elif command -v sha256sum >/dev/null 2>&1; then
    hash_sha=$(sha256sum "$hash_file_candidate" | awk '{print $1}')
  else
    hash_sha="(no sha256 tool available)"
  fi
  echo ""
  echo "Hashes file: $hash_file_candidate"
  echo "SHA256(contribution_hashes.txt): $hash_sha"

  # Optional per-circuit comparison with an expected attestation file
  if [[ -n "${EXPECTED_HASHES_FILE}" ]] && [[ -f "${EXPECTED_HASHES_FILE}" ]]; then
    echo ""
    echo "Per-circuit attestation comparison vs: $EXPECTED_HASHES_FILE"
    tmp_dir=$(mktemp -d)
    # Normalize to "name hash" format and sort by name
    awk -F": " '/: /{print $1" "$2}' "$hash_file_candidate" | LC_ALL=C sort > "$tmp_dir/local.txt"
    awk -F": " '/: /{print $1" "$2}' "$EXPECTED_HASHES_FILE" | LC_ALL=C sort > "$tmp_dir/exp.txt"
    # Join by name; show name, local, expected (MISSING when absent)
    join -a1 -a2 -e MISSING -o 0,1.2,2.2 "$tmp_dir/local.txt" "$tmp_dir/exp.txt" | while read -r name lh eh; do
      if [[ "$lh" = "MISSING" ]]; then
        echo "ONLY_EXPECTED: $name -> expected=$eh"
      elif [[ "$eh" = "MISSING" ]]; then
        echo "ONLY_LOCAL:    $name -> local=$lh"
      elif [[ "$lh" = "$eh" ]]; then
        echo "MATCH:         $name"
      else
        echo "DIFF:          $name -> local=$lh expected=$eh"
      fi
    done
    rm -rf "$tmp_dir"
  fi
fi

exit $([[ $failed -eq 0 ]] && echo 0 || echo 1)


