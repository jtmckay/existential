#!/usr/bin/env bash
# workspace_sync/ask — tell someone a large delete is waiting, and how to answer.
set -euo pipefail
{
    echo "$DECREE_QUESTION"
    echo
    for _event in $DECREE_EVENTS; do
        [[ "$_event" == error ]] && continue
        echo "docker exec automation-backup decree event $DECREE_WAIT_ID $_event"
    done
} | decree emit --machine notify --param ntfy_title="workspace sync: large delete held" >/dev/null
