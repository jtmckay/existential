#!/usr/bin/env bash
# File Router
#
# Receives Nextcloud file events (webhook_listeners, registered by the
# nextcloud_file_events migration), matches the full FILE_SOURCE path against
# every processor in lib/file-processors/, and emits one file_processor
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
# nothing here. (A file handler in workspace/.decree/handlers.yml does see them.)
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
# The message body is the event, exactly as automation-webhook's /files got it:
#
#   {"event":{"node":{"id":91,"path":"/admin/files/workspace/a.md"},"class":"OCP\\Files\\Events\\Node\\NodeWrittenEvent"},"user":{...},"time":...}
set -euo pipefail

rclone_src="$DECREE_DATA_RCLONE_SRC"

# Parse the event
_json=$(awk 'NR==1 && /^---$/{skip=1; next} skip && /^---$/{skip=0; next} !skip' \
    "$DECREE_MESSAGE" | sed '/./,$!d')

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

_processors_dir="${DECREE_LIB}/file-processors"
_matched=0

for _pair in "${_pairs[@]}"; do
    _file_action="${_pair%%|*}"
    _file_source="${rclone_src}:${_pair#*|}"

    echo "Event:  ${_class##*\\} → $_file_action"
    echo "Source: $_file_source"

    # Find all matching processors and emit a file_processor message for each
    for _processor in "$_processors_dir"/*.sh; do
        [ -f "$_processor" ] || continue
        _raw=$(grep -m1 '^PATTERN=' "$_processor" || true)
        _pattern=$(echo "$_raw" | sed "s/^PATTERN=[\"']\(.*\)[\"']$/\1/")
        [ -z "$_pattern" ] && continue

        if [[ "$_file_source" =~ $_pattern ]]; then
            _processor_name=$(basename "$_processor" .sh)

            _raw_ref=$(grep -m1 '^IS_PRE_SIGNED=' "$_processor" || true)
            _is_pre_signed=$(echo "$_raw_ref" | sed "s/^IS_PRE_SIGNED=[\"']\?\([^\"']*\)[\"']\?$/\1/")

            # Optional natural-language gate, evaluated by file_processor once the
            # content is actually on disk — the path is all we have here.
            _raw_crit=$(grep -m1 '^CRITERIA=' "$_processor" || true)
            _criteria=$(echo "$_raw_crit" | sed "s/^CRITERIA=[\"']\(.*\)[\"']$/\1/")

            # --param values reach decree as argv and decree writes the YAML, so a
            # path like "Report: Q3.pdf" or prose criteria need no quoting here.
            decree emit --machine file_processor \
                --param rclone_path="${_file_source}" \
                --param processor="${_processor_name}" \
                --param file_action="${_file_action}" \
                --param is_pre_signed="${_is_pre_signed:-false}" \
                --param criteria="${_criteria}" </dev/null >/dev/null
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
