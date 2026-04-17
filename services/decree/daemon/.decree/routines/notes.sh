#!/bin/bash
# master_routine.sh: Orchestrates the complete note processing pipeline.
# This script MUST be run from its own directory (.decree/routines).

set -euo pipefail

# --- Path Resolution ---
# SCRIPT_DIR is the directory where notes.sh resides.
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Define paths to the required components using relative paths from SCRIPT_DIR.
LIB_NOTES_DIR="${SCRIPT_DIR}/../lib/notes"
PULL_NEXTCLOUD_SCRIPT="${LIB_NOTES_DIR}/pull-nextcloud.sh"
COMPILE_NOTES_SCRIPT="${LIB_NOTES_DIR}/compile-notes.sh"
GENERATE_INDEX_SCRIPT="${LIB_NOTES_DIR}/generate-index.sh"
PUSH_DROPBOX_SCRIPT="${LIB_NOTES_DIR}/push-dropbox.sh"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    precheck_pass "notes"
    exit 0
fi

# --- Execution ---
echo "--- Starting master note routine execution (${SCRIPT_DIR}) ---"

# 1. Sync Nextcloud
echo "Running NextCloud sync..."
"${PULL_NEXTCLOUD_SCRIPT}"

# 2. Compile Notes
echo "Compiling notes..."
"${COMPILE_NOTES_SCRIPT}"

# 3. Generate Index
echo "Generating index..."
"${GENERATE_INDEX_SCRIPT}"

# 4. Sync Dropbox
echo "Syncing Dropbox..."
"${PUSH_DROPBOX_SCRIPT}"

echo "--- Master note routine execution finished successfully ---"