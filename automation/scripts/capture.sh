#!/usr/bin/env bash
# Capture
#
# Appends the message body to workspace/.capture/ through lib/capture/capture.sh,
# the same redaction and stream code-server's Claude Code and opencode write to.
# automation-webhook's POST /capture queues it:
#
#   curl -X POST https://automation-webhook.<domain>/capture \
#     -H "Authorization: Bearer <secret>" -d '{"source":"phone","text":"buy filters"}'
#
# A JSON body's `source` wins over the param; a plain-text body is the text.
set -euo pipefail

body=$(awk 'NR==1 && /^---$/{skip=1; next} skip && /^---$/{skip=0; next} !skip' "$DECREE_MESSAGE")

# Waits, unlike the hooks, so this run's log holds the write and any failure.
CAPTURE_DIR="${CAPTURE_DIR:-/workspace/.capture}" CAPTURE_HOST=automation CAPTURE_WAIT=1 \
    bash "${DECREE_LIB}/capture/capture.sh" "${DECREE_DATA_SOURCE:-webhook}" <<<"$body"
