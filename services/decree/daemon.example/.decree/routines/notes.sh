#!/bin/bash
# master_routine.sh: Orchestrates the complete note processing pipeline.
# This script MUST be run from its own directory (.decree/routines).

set -euo pipefail

# --- Path Resolution ---
# SCRIPT_DIR is the directory where notes.sh resides.
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Define paths to the required components using relative paths from SCRIPT_DIR.
LIB_NOTES_DIR="${SCRIPT_DIR}/../lib/notes"
SYNC_NEXTCLOUD_SCRIPT="${LIB_NOTES_DIR}/sync-nextcloud.sh"
COMPILE_NOTES_SCRIPT="${LIB_NOTES_DIR}/compile-notes.sh"
GENERATE_INDEX_SCRIPT="${LIB_NOTES_DIR}/generate-index.sh"
SYNC_DROPBOX_SCRIPT="${LIB_NOTES_DIR}/sync-dropbox.sh"

# --- Execution ---
echo "--- Starting master note routine execution (${SCRIPT_DIR}) ---"

# 1. Sync Nextcloud
echo "Running NextCloud sync..."
"${SYNC_NEXTCLOUD_SCRIPT}"

# 2. Compile Notes
echo "Compiling notes..."
"${COMPILE_NOTES_SCRIPT}"

# 3. Generate Index
echo "Generating index..."
"${GENERATE_INDEX_SCRIPT}"

# 4. Sync Dropbox
echo "Syncing Dropbox..."
"${SYNC_DROPBOX_SCRIPT}"

echo "--- Master note routine execution finished successfully ---"