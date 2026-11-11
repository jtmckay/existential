#!/usr/bin/env bash
# Host-side setup for 30-search, run by e2e.sh's stage_checks before the stack
# boots: the `search` command (ai/qmd/recall/search.sh, qmd's) is put in the
# workspace's decree lib, the one place the automation daemon running this check
# can reach it.
#
# Contract: $WORK is the e2e clone. Exit non-zero to fail the run. Every write
# lands inside the clone and is torn down with it.
set -euo pipefail

WORK="${WORK:?}"
grep -q '^EXIST_IS_AI_QMD=true' "$WORK/.env.shared" || exit 0
mkdir -p "$WORK/volumes/workspace_data/.decree/lib/recall"
cp "$WORK/ai/qmd/recall/search.sh" "$WORK/volumes/workspace_data/.decree/lib/recall/"
echo "  staged qmd's search command for the check"
