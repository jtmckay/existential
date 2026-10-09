#!/usr/bin/env bash
# notes — Orchestrates the complete note processing pipeline.
#
# Container paths (all absolute):
#   /data/notes     — Nextcloud sync cache (in the decree_data volume: notes/)
#   /data/dropbox   — compiled output for Dropbox (in the decree_data volume: dropbox/)
#   $DECREE_LIB/notes/ — pipeline scripts (automation/lib/notes/)

set -euo pipefail

echo "--- Starting notes pipeline ---"

bash "$DECREE_LIB"/notes/pull-nextcloud.sh
bash "$DECREE_LIB"/notes/compile-notes.sh
bash "$DECREE_LIB"/notes/generate-index.sh
bash "$DECREE_LIB"/notes/push-dropbox.sh

echo "--- Notes pipeline finished ---"