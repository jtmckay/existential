#!/usr/bin/env bash
# Route Failed
#
# The catch-all. Records that a message could not be routed, and stops.
#
# It calls no model, spawns no agent, and touches nothing outside its own log —
# deliberately. This is where messages land when the system does not know what
# to do with them, and the one thing it must never do is guess. It is also
# decree's `default_routine`, which means it catches anything that arrives with
# no `routine:` at all and no router to decide one.
#
# It exits 0. The run is recorded with its reason and stops there — no retries,
# no dead-letter backlog to clear. Look for these in the decree run log, or in
# Grafana filtered to routine=route-failed; a rising count means the router or
# the department list needs attention, not that anything is broken.
#
# Written by hermes-router when the router's answer does not name a real
# department:
#
#   ---
#   routine: route-failed
#   route_reason: the router answered 'legal', which is not a department
#   route_attempted: legal
#   route_candidates: research sales
#   ---
set -euo pipefail

message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # No dependencies on purpose: the catch-all must work when nothing else does.
    exit 0
fi

route_reason="${route_reason:-}"
route_attempted="${route_attempted:-}"
route_candidates="${route_candidates:-}"
source_file="${source_file:-}"

if [ -n "$route_attempted" ]; then
    echo "FAILED TO ROUTE to '${route_attempted}'"
else
    echo "FAILED TO ROUTE at all — no department was chosen."
fi

[ -n "$route_reason" ]     && echo "  reason     : ${route_reason}"
[ -n "$route_candidates" ] && echo "  candidates : ${route_candidates}"
[ -n "$source_file" ]      && echo "  source     : ${source_file}"
[ -n "$message_id" ]       && echo "  message    : ${message_id}"

# A short excerpt so the log says what was dropped, without copying the whole
# message into it. The full text stays in the run directory either way.
_body="$(awk 'NR==1 && /^---$/{skip=1; next} skip && /^---$/{skip=0; next} !skip' \
    "$message_file" 2>/dev/null | sed '/./,$!d' | head -c 400)"
if [ -n "$_body" ]; then
    echo "  --- message (first 400 chars) ---"
    printf '%s\n' "$_body" | sed 's/^/  /'
fi

echo "Nothing was run for this message."
exit 0
