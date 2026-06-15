#!/usr/bin/env bash
# notes — Orchestrates the complete note processing pipeline.
#
# Container paths (all absolute):
#   /data/notes     — Nextcloud sync cache (tier-3 bind: services/decree/data/notes/)
#   /data/dropbox   — compiled output for Dropbox (tier-3 bind: services/decree/data/dropbox/)
#   /work/.decree/lib/notes/ — pipeline scripts (automations/lib/notes/)

set -euo pipefail

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    DECREE_PRE_CHECK=true bash /work/.decree/lib/notes/pull-nextcloud.sh || exit 1
    precheck_pass "notes"
    exit 0
fi

echo "--- Starting notes pipeline ---"

bash /work/.decree/lib/notes/pull-nextcloud.sh
bash /work/.decree/lib/notes/compile-notes.sh
bash /work/.decree/lib/notes/generate-index.sh
bash /work/.decree/lib/notes/push-dropbox.sh

echo "--- Notes pipeline finished ---"