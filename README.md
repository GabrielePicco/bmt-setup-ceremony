# BMT trusted setup ceremony

### For Contributors

1. Receive `contribution_urls.json` from coordinator
2. Run:
```bash
cd contributor
./contribute.sh contribution_urls.json
```
3. When you're done, delete the files and wipe RAM — eg by shutting down machine and disconnecting from power


### How to verify contributions

*tba


### For Coordinators

#### 1. Initial Setup

```bash
cd coordinator

# Set up service account for URL signing
./create_key.sh <bucket-name>

# Initialize ceremony (generates R1CS and initial contribution)
export LIGHT_PROVER_BIN="path/to/light-prover"
./init.sh
```

#### 2. Upload Initial Contribution

```bash
# Upload to Google Cloud Storage
gsutil -m cp -r ../contributions/0000_initial gs://<bucket>/ceremony/contributions/

# Verify upload
gsutil ls gs://<bucket>/ceremony/contributions/0000_initial/ | head -5
```

#### 3. Manage Contributors

For each contributor in sequence:

```bash
# Generate presigned URLs for contributor
./generate_urls.sh <bucket> alice 0000_initial
# → Creates 0001_alice_urls.json

# Send JSON file to Alice securely
# Wait for Alice to complete contribution

# Verify the contribution
./verify.sh 0001_alice

# If verification passes, continue to next contributor
./generate_urls.sh <bucket> bob 0001_alice
# → Creates 0002_bob_urls.json
```

#### 4. Complete Ceremony

After the final contribution:

```bash
# Extract proving and verification keys
./extract_keys.sh XXXX_final_contributor

# Keys will be in ../proving-keys/
# Option to upload to GCS when prompted
```

#### 5. Publish Results

- Share final keys publicly
- Publish all contributions for transparency
- Create attestation document with contributor list

#### Coordinator Workflow

```
init.sh → upload → generate_urls.sh → [wait] → verify.sh → repeat → extract_keys.sh
```

## Files

```
coordinator/
├── init.sh           # Initialize ceremony from R1CS
├── generate_urls.py  # Create presigned URLs for contributor
├── verify.sh         # Verify contributions
└── extract_keys.sh   # Extract final keys

contributor/
└── contribute.sh     # Run contribution with URLs file
```

## Circuits

- **89 total circuits**
  - V1: 30 circuits (tree height 26)
  - V2: 56 circuits (tree heights 32/40)
  - Batch: 3 circuits (batch operations)

- **PTAU sizes**
  - PTAU 19 for V1/V2 circuits
  - PTAU 24 for batch circuits

## Dependencies

**Coordinator:**
- `light-prover` binary (for R1CS generation)
- `python3` with `google-cloud-storage`
- `gsutil` for GCS operations

**Contributor:**
- `jq` (auto-installed if missing)
- `go` (to build semaphore-mtb-setup)
