#!/usr/bin/env bash
# openviking-watch-dirs — register one or more directories as watched resources
# in OpenViking via POST /api/v1/resources.
#
# Runs as a decree migration or cron. Safe to re-run: duplicate watches are
# harmless but will appear in the watch list.
#
# Env vars (set via cron/migration frontmatter):
#   WATCH_DIRS   newline-separated list of file:// URIs to watch, e.g.:
#                  file:///app/notes
#                  file:///app/resources
#
# Env vars (passed through sidecar compose env):
#   OPENVIKING_API_KEY  Bearer token for the OpenViking REST API
set -euo pipefail

if [[ "${DECREE_PRE_CHECK:-}" == "true" ]]; then
    command -v curl >/dev/null 2>&1 || { echo "curl not found" >&2; exit 1; }
    [[ -n "${OPENVIKING_API_KEY:-}" ]] || { echo "OPENVIKING_API_KEY not set" >&2; exit 1; }
    [[ -n "${WATCH_DIRS:-}" ]]         || { echo "WATCH_DIRS not set in frontmatter" >&2; exit 1; }
    exit 0
fi

OPENVIKING_URL="${OPENVIKING_URL:-http://openviking:1933}"

while IFS= read -r dir; do
    [[ -z "${dir// }" ]] && continue
    echo "Registering watched directory: ${dir}"
    curl -fsS -X POST --max-time 60 \
        -H "Authorization: Bearer ${OPENVIKING_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"path\": \"${dir}\", \"watch_interval\": 300, \"preserve_structure\": true}" \
        "${OPENVIKING_URL}/api/v1/resources" >/dev/null \
        && echo "  registered ${dir}" \
        || { echo "  failed to register ${dir}" >&2; exit 1; }
done <<< "${WATCH_DIRS}"

echo "OpenViking watched directories registered."
