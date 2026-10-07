#!/usr/bin/env bash
# Outbox relay — turn each workspace/outbox/*.md into a real decree message.
#
# This is the ONLY door from workspace/ into decree's inbox. Hermes (or
# anything else confined to workspace/) has no mount into automation/ and must
# never be given one — shared_routines/ is read-only from inside the main
# daemon on purpose (see .claude/reference/services.md). Drop a message here
# instead:
#
#   ---
#   routine: agent-task
#   prompt: Summarize this week's notes.
#   correlation_id: D0002-1939-triage-0
#   ---
#
# A poll, not a file event: hermes writes workspace_data straight to disk, and
# only uploads through Nextcloud fire events. It reads the directory directly —
# this daemon mounts the workspace — so there is no second copy to reconcile.
# A relayed file is deleted; a real outbox empties once its mail is sent.
#
# correlation_id is optional and is NOT decree's own chain — decree's
# collect_outbox always stamps a relayed message with the chain of whoever is
# draining the outbox (this routine's run), discarding any chain/seq the dropped
# file names. correlation_id is a plain custom field that survives untouched
# (decree only reserves id/chain/seq/routine/migration/trigger), so routines
# downstream can read it back with correlation_id="${correlation_id:-$chain}"
# (see agent-task.sh) to trace a flow across hops.
#
#   ---
#   cron: "* * * * *"
#   routine: outbox-relay
#   ---
set -euo pipefail

message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

WORKSPACE_OUTBOX="${WORKSPACE_OUTBOX:-/workspace/outbox}"
OUTBOX_DIR="${OUTBOX_DIR:-/work/.decree/outbox}"

if [[ "${DECREE_PRE_CHECK:-}" == "true" ]]; then
    command -v yq >/dev/null 2>&1   || { echo "yq not found" >&2; exit 1; }
    [[ -d "${WORKSPACE_OUTBOX%/*}" ]] || { echo "${WORKSPACE_OUTBOX%/*} is not mounted" >&2; exit 1; }
    exit 0
fi

[[ -d "$WORKSPACE_OUTBOX" ]] || exit 0
# decree reads the outbox but never creates it — an absent dir is silently
# treated as "no messages", so a relay would vanish without an error.
mkdir -p "$OUTBOX_DIR"

# Older than a few seconds, so a file hermes is still writing is left for the
# next tick rather than relayed half-written.
find "$WORKSPACE_OUTBOX" -maxdepth 1 -type f -name '*.md' -not -newermt '-5 seconds' -print0 |
while IFS= read -r -d '' _file; do
    _name="${_file##*/}"

    # A real message's frontmatter starts on line 1. Anything else (README.md,
    # a note that merely shows an example message) is not mail: leave it be.
    [[ "$(head -1 "$_file")" == "---" ]] || continue

    frontmatter="$(awk 'BEGIN{fm=0} /^---$/{fm++; if (fm==2) exit; next} fm==1' "$_file")"
    body="$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2' "$_file" | sed '/\S/,$!d')"

    routine="$(printf '%s\n' "$frontmatter" | yq eval '.routine // ""' -)"
    # Routine names are slugs — constraining to that shape means a value safe
    # to print straight into the frontmatter built below.
    if ! [[ "$routine" =~ ^[a-z0-9-]+$ ]]; then
        # Renamed out of *.md so it is reported once, not every minute.
        mv -- "$_file" "${_file}.rejected"
        echo "Missing or invalid 'routine' in ${_name} — left as ${_name}.rejected" >&2
        continue
    fi

    correlation_id="$(printf '%s\n' "$frontmatter" | yq eval '.correlation_id // ""' -)"
    # workspace/ content is attacker-influenceable as far as this script is
    # concerned — constrain it before it goes near a constructed YAML value.
    [[ "$correlation_id" =~ ^[A-Za-z0-9._-]+$ ]] || correlation_id=""

    # Everything else is a parameter for the target routine — forwarded
    # verbatim, re-serialized by yq (not string-built), so whatever it contains
    # cannot break out of its own field. chain/seq/id are decree's own and it
    # overwrites them on collection regardless.
    extra="$(printf '%s\n' "$frontmatter" | yq eval 'del(.routine, .correlation_id, .chain, .seq, .id)' -)"

    {
        printf -- '---\n'
        printf 'routine: %s\n' "$routine"
        [[ -n "$correlation_id" ]] && printf 'correlation_id: %s\n' "$correlation_id"
        [[ "$extra" != "{}" ]] && printf '%s\n' "$extra"
        printf -- '---\n\n'
        printf '%s\n' "$body"
    } > "${OUTBOX_DIR}/outbox-relay-$(date +%s%N).md"

    rm -f -- "$_file"
    echo "Relayed ${_name} -> routine=${routine}${correlation_id:+ correlation_id=${correlation_id}}"
done
