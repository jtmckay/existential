#!/usr/bin/env bash
# Decree Routines Snapshot
#
# Writes a markdown snapshot of every enabled decree routine — name,
# description, parameters — to workspace/ai/. Hermes has no mount
# into automation/, so this is how it learns what routines exist and how to
# trigger them, without a new MCP server or any filesystem access beyond
# workspace/ (which it already has). Overwritten in place each run; reuses
# `decree routine` for the listing rather than re-parsing the registry.
#
# Not chained from anything. Copy cron.example/routines-snapshot.md to keep it
# current, or drop a bare `routine: routines-snapshot` message in the inbox to
# refresh it by hand.
set -euo pipefail

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    command -v decree >/dev/null 2>&1 || precheck_fail "routines-snapshot" "decree not found"
    [ -d "${AGENT_OUTPUT_DIR:-/workspace/ai}" ] || precheck_fail "routines-snapshot" \
        "${AGENT_OUTPUT_DIR:-/workspace/ai} does not exist — is ../../workspace mounted into the decree container?"
    precheck_pass "routines-snapshot"
    exit 0
fi

# Decree parameters
message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

AGENT_OUTPUT_DIR="${AGENT_OUTPUT_DIR:-/workspace/ai}"
mkdir -p "$AGENT_OUTPUT_DIR"

out="${AGENT_OUTPUT_DIR}/decree-routines.md"
tmp="$(mktemp "${message_dir:-/tmp}/routines-snapshot.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

{
    printf -- '---\n'
    printf 'generated_by: routines-snapshot\n'
    printf 'generated_at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf -- '---\n\n'
    echo "# Decree Routines"
    echo
    echo "Every routine currently enabled on this decree daemon. To run one,"
    echo "write a message with \`routine: <name>\` plus any parameters listed"
    echo "below (as YAML frontmatter fields) and drop it in the decree inbox."
    echo

    # \`decree routine\` with no name lists every enabled routine, one per
    # line: "  name   description". Names are single-token slugs, so the
    # first field is always the name.
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        echo "## ${name}"
        echo
        # Detail view is "name (container path)", a blank line, then
        # description/params — drop both, the path is internal plumbing
        # hermes can't reach anyway and we already printed our own heading.
        decree --no-color routine "$name" | tail -n +3
        echo
    done < <(decree --no-color routine | awk '{print $1}')
} > "$tmp"

mv "$tmp" "$out"
echo "Wrote ${out}"
