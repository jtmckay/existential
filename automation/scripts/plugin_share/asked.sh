#!/usr/bin/env bash
# One message naming who asks for what, and how to answer.
set -euo pipefail
printf '%s asks for the machine %s.\n\nSend it:  docker exec automation decree event %s share\nRefuse:   docker exec automation decree event %s refuse\n\nUnanswered, it is refused in a day.\n' \
    "$DECREE_DATA_CLIENT" "$DECREE_DATA_MACHINE" "$DECREE_WAIT_ID" "$DECREE_WAIT_ID" |
    "${DECREE:-decree}" emit --machine notify --param ntfy_title="A stack asks for a machine" --param ntfy_tags=package >/dev/null
echo "plugin_share: ${DECREE_DATA_CLIENT} asks for the machine ${DECREE_DATA_MACHINE}"
