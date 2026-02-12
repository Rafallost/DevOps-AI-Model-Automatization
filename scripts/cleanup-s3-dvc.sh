#!/usr/bin/env bash
# cleanup-s3-dvc.sh - Remove orphaned files from DVC S3 bucket
#
# Usage:
#   ./cleanup-s3-dvc.sh           # Dry-run (safe, shows what would be deleted)
#   ./cleanup-s3-dvc.sh --confirm # Execute deletion (requires confirmation)
#
# Safety features:
# - Dry-run by default
# - Whitelists active files (from current .dvc manifests)
# - Shows detailed summary before deletion
# - Requires explicit --confirm flag

set -euo pipefail

# Configuration
DVC_BUCKET="s3://wms-dvc-data-055677744286/dvc"
DVC_PREFIX="files/md5"
IMAGES_DVC="WMS/data/training/images.dvc"
MASKS_DVC="WMS/data/training/masks.dvc"
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

# Parse arguments
DRY_RUN=true
if [[ "${1:-}" == "--confirm" ]]; then
    DRY_RUN=false
fi

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "DVC S3 Cleanup Script"
echo "========================================="
echo ""

# Step 1: Extract active hashes from .dvc files
echo "[1/5] Reading active .dvc files..."
if [[ ! -f "${IMAGES_DVC}" ]] || [[ ! -f "${MASKS_DVC}" ]]; then
    echo -e "${RED}ERROR: .dvc files not found${NC}"
    echo "  Expected: ${IMAGES_DVC}, ${MASKS_DVC}"
    exit 1
fi

# Extract .dir manifest hashes from .dvc files
IMAGES_HASH=$(grep "md5:" "${IMAGES_DVC}" | awk '{print $2}')
MASKS_HASH=$(grep "md5:" "${MASKS_DVC}" | awk '{print $2}')

echo "  images.dvc → ${IMAGES_HASH}"
echo "  masks.dvc  → ${MASKS_HASH}"
echo ""

# Step 2: Download and parse .dir manifests
echo "[2/5] Downloading .dir manifests from S3..."
IMAGES_DIR="${TEMP_DIR}/images.dir"
MASKS_DIR="${TEMP_DIR}/masks.dir"

aws s3 cp "${DVC_BUCKET}/${DVC_PREFIX}/${IMAGES_HASH:0:2}/${IMAGES_HASH:2}" "${IMAGES_DIR}" --quiet
aws s3 cp "${DVC_BUCKET}/${DVC_PREFIX}/${MASKS_HASH:0:2}/${MASKS_HASH:2}" "${MASKS_DIR}" --quiet

echo "  ✓ Downloaded ${IMAGES_HASH}"
echo "  ✓ Downloaded ${MASKS_HASH}"
echo ""

# Step 3: Extract JPG hashes from .dir JSON files
echo "[3/5] Parsing referenced JPG files..."
ACTIVE_FILES="${TEMP_DIR}/active_files.txt"

# Add .dir manifests to whitelist
echo "${IMAGES_HASH:0:2}/${IMAGES_HASH:2}" > "${ACTIVE_FILES}"
echo "${MASKS_HASH:0:2}/${MASKS_HASH:2}" >> "${ACTIVE_FILES}"

# Parse .dir JSON and extract md5 hashes (format: [{...,"md5":"hash",...},...]
# Use Python for robust JSON parsing
python3 <<EOF >> "${ACTIVE_FILES}"
import json
import sys

for dir_file in ["${IMAGES_DIR}", "${MASKS_DIR}"]:
    with open(dir_file, 'r') as f:
        entries = json.load(f)
    for entry in entries:
        md5 = entry['md5']
        # DVC stores files as: files/md5/XX/YYYYYY (first 2 chars / rest)
        print(f"{md5[0:2]}/{md5[2:]}")
EOF

ACTIVE_COUNT=$(wc -l < "${ACTIVE_FILES}")
echo "  ✓ Found ${ACTIVE_COUNT} active files (2 .dir + $((ACTIVE_COUNT - 2)) JPG)"
echo ""

# Step 4: List all S3 files and identify orphans
echo "[4/5] Scanning S3 bucket for orphaned files..."
S3_ALL_FILES="${TEMP_DIR}/s3_all_files.txt"
aws s3 ls "${DVC_BUCKET}/${DVC_PREFIX}/" --recursive | awk '{print $4}' | sed "s|^${DVC_PREFIX}/||" > "${S3_ALL_FILES}"

S3_TOTAL=$(wc -l < "${S3_ALL_FILES}")
echo "  Total S3 files: ${S3_TOTAL}"

# Find orphans (files in S3 but not in active whitelist)
ORPHANS="${TEMP_DIR}/orphans.txt"
sort "${S3_ALL_FILES}" > "${TEMP_DIR}/s3_sorted.txt"
sort "${ACTIVE_FILES}" > "${TEMP_DIR}/active_sorted.txt"
comm -23 "${TEMP_DIR}/s3_sorted.txt" "${TEMP_DIR}/active_sorted.txt" > "${ORPHANS}"

ORPHAN_COUNT=$(wc -l < "${ORPHANS}")
KEEP_COUNT=$((S3_TOTAL - ORPHAN_COUNT))

echo ""
echo "========================================="
echo "SUMMARY"
echo "========================================="
echo -e "${GREEN}KEEP: ${KEEP_COUNT} files${NC} (current .dir + referenced JPGs)"
echo -e "${RED}DELETE: ${ORPHAN_COUNT} files${NC} (orphaned .dir + unused JPGs)"
echo ""

if [[ ${ORPHAN_COUNT} -eq 0 ]]; then
    echo -e "${GREEN}✓ No orphaned files found. S3 bucket is clean!${NC}"
    exit 0
fi

# Show sample of files to be deleted
echo "Files to DELETE (showing first 20):"
head -20 "${ORPHANS}" | while read -r file; do
    echo -e "  ${RED}✗${NC} ${DVC_PREFIX}/${file}"
done

if [[ ${ORPHAN_COUNT} -gt 20 ]]; then
    echo "  ... and $((ORPHAN_COUNT - 20)) more files"
fi
echo ""

# Step 5: Execute deletion (if confirmed)
if [[ "${DRY_RUN}" == true ]]; then
    echo -e "${YELLOW}DRY-RUN MODE${NC} - No files were deleted"
    echo "To execute deletion, run: $0 --confirm"
    exit 0
fi

# Confirmation prompt
echo -e "${YELLOW}⚠️  WARNING: This will permanently delete ${ORPHAN_COUNT} files from S3${NC}"
echo "Type 'yes' to confirm deletion:"
read -r CONFIRM

if [[ "${CONFIRM}" != "yes" ]]; then
    echo "Deletion cancelled."
    exit 0
fi

# Execute deletion
echo ""
echo "[5/5] Deleting orphaned files..."
DELETED=0
while read -r file; do
    aws s3 rm "${DVC_BUCKET}/${DVC_PREFIX}/${file}" --quiet && ((DELETED++)) || echo "  Failed: ${file}"
done < "${ORPHANS}"

echo ""
echo "========================================="
echo -e "${GREEN}✓ Cleanup complete!${NC}"
echo "========================================="
echo "  Deleted: ${DELETED}/${ORPHAN_COUNT} files"
echo "  Remaining: ${KEEP_COUNT} files (2 .dir + $((KEEP_COUNT - 2)) JPG)"
echo ""
