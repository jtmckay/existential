#!/usr/bin/env bash
# File Router
#
# Receives Nextcloud file events (webhook_listeners, registered by the
# nextcloud-file-events migration), matches the full FILE_SOURCE path against
# every processor in lib/file-processors/, and enqueues one file-processor
# message per match. The file is downloaded per-processor — no shared state.
#
# FILE_SOURCE is "<rclone_src>:<path>", where <path> is the Nextcloud path with
# its "/<user>/files/" prefix stripped — i.e. exactly what the nextcloud rclone
# remote (WebDAV, as the admin user) resolves. "workspace/notes/a.md" is the
# workspace, which Nextcloud serves as Local storage at /workspace.
#
# Matching here is mechanical and cheap: PATTERN against the path, nothing else.
# A processor may also declare a CRITERIA= line — a natural-language test of the
# file's CONTENT — which is carried through to file-processor and evaluated
# there, after the download. Splitting it that way means the expensive half only
# runs for files that already passed the cheap half.
#
# Only uploads THROUGH Nextcloud raise events — the desktop client, the web UI,
# WebDAV, rclone. Hermes, code-server and decree write workspace_data straight
# to disk; nextcloud-cron's scan makes those visible to clients but fires
# nothing. That is what stops an agent's own output from triggering another run.
#
# Event shapes (verified against nextcloud:34.0.3):
#
#   NodeWrittenEvent  {"event":{"node":{"path":"/admin/files/x.md"},"class":"..."}}
#                     a new file AND an overwrite — so NodeCreatedEvent is not
#                     subscribed; it would double every upload.
#   NodeDeletedEvent  same shape, no id.
#   NodeRenamedEvent  {"event":{"source":{"path":...},"target":{"path":...}}}
#
# A payload says nothing about file vs folder, and a new folder raises
# NodeWrittenEvent too. PATTERNs that anchor on an extension never notice; one
# that matches a bare prefix will see folders as well.
#
# Example webhook trigger (fired by the /files endpoint):
#
#   ---
#   routine: file-router
#   rclone_src: nextcloud
#   ---
#   {"event":{"node":{"id":91,"path":"/admin/files/workspace/a.md"},"class":"OCP\\Files\\Events\\Node\\NodeWrittenEvent"},"user":{...},"time":...}
set -euo pipefail

message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    command -v jq >/dev/null 2>&1 || precheck_fail "file-router" "jq not found"
    precheck_pass "file-router"
    exit 0
fi

rclone_src="${rclone_src:-nextcloud}"

# Parse the event
_json=$(awk 'NR==1 && /^---$/{skip=1; next} skip && /^---$/{skip=0; next} !skip' \
    "$message_file" | sed '/./,$!d')

if [ -z "$_json" ]; then
    echo "Empty message body, nothing to route."
    exit 0
fi

_class=$(echo "$_json" | jq -r '.event.class // empty')
if [ -z "$_class" ]; then
    echo "Could not parse event.class — verify Nextcloud's webhook_listeners is the sender."
    echo "Payload: $_json"
    exit 1
fi

# "/admin/files/workspace/f.pdf" -> "workspace/f.pdf"
_rel() { echo "$1" | sed -E 's#^/[^/]+/files/##'; }

# Build the (action, path) pairs this event produces, flattened into the two
# action strings every processor reads:
#   Written -> created      Deleted -> removed      Renamed -> both
_pairs=()
case "${_class##*\\}" in
    NodeWrittenEvent)
        _pairs+=("created|$(_rel "$(echo "$_json" | jq -r '.event.node.path')")")
        ;;
    NodeDeletedEvent)
        _pairs+=("removed|$(_rel "$(echo "$_json" | jq -r '.event.node.path')")")
        ;;
    NodeRenamedEvent)
        _pairs+=("removed|$(_rel "$(echo "$_json" | jq -r '.event.source.path')")")
        _pairs+=("created|$(_rel "$(echo "$_json" | jq -r '.event.target.path')")")
        ;;
    *)
        echo "Unhandled event '$_class' — skipping."
        exit 0
        ;;
esac

_processors_dir="$(dirname "${BASH_SOURCE[0]}")/../lib/file-processors"
_matched=0

for _pair in "${_pairs[@]}"; do
    _file_action="${_pair%%|*}"
    _file_source="${rclone_src}:${_pair#*|}"

    echo "Event:  ${_class##*\\} → $_file_action"
    echo "Source: $_file_source"

    # Find all matching processors and enqueue a file-processor message for each
    for _processor in "$_processors_dir"/*.sh; do
        [ -f "$_processor" ] || continue
        _raw=$(grep -m1 '^PATTERN=' "$_processor" || true)
        _pattern=$(echo "$_raw" | sed "s/^PATTERN=[\"']\(.*\)[\"']$/\1/")
        [ -z "$_pattern" ] && continue

        if [[ "$_file_source" =~ $_pattern ]]; then
            _processor_name=$(basename "$_processor" .sh)
            # decree reads the outbox but never creates it, so every routine that
            # queues a message has to. This router was the one that did not, and it
            # failed on the first event a fresh install ever routed.
            _outbox_dir="${OUTBOX_DIR:-/work/.decree/outbox}"
            mkdir -p "$_outbox_dir"
            # _matched is in the filename because a rename enqueues the same
            # processor twice (removed, then created) and the two must not collide.
            _outbox_file="${_outbox_dir}/${message_id}-${_matched}-${_processor_name}.md"

            _raw_ref=$(grep -m1 '^IS_PRE_SIGNED=' "$_processor" || true)
            _is_pre_signed=$(echo "$_raw_ref" | sed "s/^IS_PRE_SIGNED=[\"']\?\([^\"']*\)[\"']\?$/\1/")

            # Optional natural-language gate, evaluated by file-processor once the
            # content is actually on disk — the path is all we have here. Quoted
            # through jq because criteria are prose: colons and quotes are normal in
            # them — as they are in rclone_path, which carries a file path and
            # so is whatever the user named their file. "Report: Q3.pdf" produces a
            # ": " in the value; unquoted, that message is invalid YAML and decree
            # re-runs it forever without ever writing run.json. Only processor,
            # file_action and is_pre_signed below are genuinely mechanical.
            _raw_crit=$(grep -m1 '^CRITERIA=' "$_processor" || true)
            _criteria=$(echo "$_raw_crit" | sed "s/^CRITERIA=[\"']\(.*\)[\"']$/\1/")

            # subroutine duplicates processor on purpose: processor is file-processor's
            # own dispatch input, subroutine is the generic "which sub-thing did this
            # run actually do" convention afterEach.sh surfaces to Grafana. Same value
            # here, but they answer different questions and a future routine's
            # subroutine won't always equal some other field it also happens to set.

            cat > "$_outbox_file" << EOF
---
routine: file-processor
rclone_path: $(jq -rn --arg v "${_file_source}" '$v|@json')
processor: ${_processor_name}
subroutine: ${_processor_name}
file_action: ${_file_action}
is_pre_signed: ${_is_pre_signed:-false}
criteria: $(jq -rn --arg v "${_criteria}" '$v|@json')
---
EOF
            echo "Queued: $_processor_name"
            _matched=$((_matched + 1))
        fi
    done
done

if [ "$_matched" -eq 0 ]; then
    echo "No processors matched."
else
    echo "Routed to $_matched processor(s)."
fi
