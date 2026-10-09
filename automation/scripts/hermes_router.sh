#!/usr/bin/env bash
# Hermes Router
#
# Decides which department should handle a message, then emits agent_task with
# that department as its profile. It does not do the work itself.
#
# Departments are discovered, not configured: every ai/hermes/profiles/<name>/
# is a candidate and its profile.yml `description:` is what the router sees —
# the same file hermes' entrypoint provisions the profile from, so a description
# is written once. Adding a department is adding a directory; nothing here
# changes. The router profile itself is skipped: it cannot route to itself.
#
# The decision runs against the hermes 'router' profile (/p/router/v1), which
# carries no toolsets and no MCP servers because naming a department needs
# neither. That profile costs ~630 prompt tokens per call against ~40,000 for
# the default one, which is the whole reason routing is split out.
#
# The profile is called directly over its OpenAI-compatible endpoint, through
# lib/hermes.sh. Hermes runs its own tool loop, so there is nothing for a CLI
# agent to add here — and a direct, non-streaming call is also the one shape
# that never trips over hermes' custom `event: hermes.tool.progress` SSE frames.
#
# The reply is validated against the discovered list. Anything unrecognized —
# a hallucinated department, an empty answer, a gateway failure — ends the run
# in `not_routed`, with the reason in its log. This script never guesses.
#
#   decree emit --machine hermes_router --param source_file=notes/lead.md <<<'<the task>'
set -euo pipefail

: "${HERMES_API_KEY:?HERMES_API_KEY is empty — enable hermes so the gateway credential is passed through}"

ROUTER_PROFILE="${ROUTER_PROFILE:-router}"
# The profile definitions, read off decree's read-only /repo mount. Read-only is
# all this needs: provisioning happens in hermes' own entrypoint, which is the
# only place that can reach the CLI and the data volume.
PROFILE_DEFS="${PROFILE_DEFS:-/repo/ai/hermes/profiles}"
ROUTER_TIMEOUT="${ROUTER_TIMEOUT:-300}"
source_file="$DECREE_DATA_SOURCE_FILE"
output_name="$DECREE_DATA_OUTPUT_NAME"

# --- What can we route to? -------------------------------------------------

_departments=()
_catalog=""
for _f in "${PROFILE_DEFS}"/*/profile.yml; do
    [ -f "$_f" ] || continue
    _n="$(basename "$(dirname "$_f")")"
    # A profile cannot route to itself, and the router owns no tools with which
    # to do the work anyway.
    [ "$_n" = "$ROUTER_PROFILE" ] && continue
    _d="$(grep -m1 '^description:' "$_f" | sed 's/^description:[[:space:]]*//')"
    _departments+=("$_n")
    _catalog="${_catalog}- ${_n}: ${_d:-(no description)}"$'\n'
done

if [ "${#_departments[@]}" -eq 0 ]; then
    echo "No department profiles found in ${PROFILE_DEFS} — nothing to route to." >&2
    exit 1
fi

echo "Departments: ${_departments[*]}"

# --- The message we are routing --------------------------------------------

_body="$(awk 'NR==1 && /^---$/{skip=1; next} skip && /^---$/{skip=0; next} !skip' \
    "$DECREE_MESSAGE" | sed '/./,$!d')"

if [ -z "$_body" ]; then
    echo "Empty message body — nothing to route."
    exit 0
fi

# --- Ask the router profile ------------------------------------------------

_prompt="Choose the single department best suited to handle the message below.

## Departments

${_catalog}
## Message

${_body}

## Instructions

Respond with ONLY the department name, exactly as written above. No explanation,
no punctuation. If no department is a clear match, respond with: none"

echo "Asking the ${ROUTER_PROFILE} profile..."

# shellcheck source=../lib/hermes.sh
source "${DECREE_LIB}/hermes.sh"
HERMES_API_URL="$(hermes_profile_url "$ROUTER_PROFILE")"
HERMES_TIMEOUT="$ROUTER_TIMEOUT"
export HERMES_API_URL HERMES_TIMEOUT

_system="You route work to departments. You reply with one department name and nothing else."

# A wrong answer here is handled below, so a failed call is not fatal: it lands
# in the same not-routed branch as a hallucinated name.
_choice="$(hermes_chat "$_system" "$_prompt" 32 || true)"
_choice="$(printf '%s' "$_choice" | sed '/^[[:space:]]*$/d' | tail -1 \
    | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[.,]$//' | tr '[:upper:]' '[:lower:]')"

echo "Router said: ${_choice:-(nothing)}"

# --- Validate, then hand off ------------------------------------------------

_matched=""
for _d in "${_departments[@]}"; do
    [ "$_choice" = "$_d" ] && { _matched="$_d"; break; }
done

if [ -z "$_matched" ]; then
    # Never guess. An unrecognized answer is a routing failure, not a hint.
    if [ -z "$_choice" ]; then
        _reason="the router returned no answer (gateway failure or timeout)"
    elif [ "$_choice" = "none" ]; then
        _reason="the router found no department matching this message"
    else
        _reason="the router answered '${_choice}', which is not a department"
    fi
    echo "Not routed: ${_reason}"
    echo "  candidates : ${_departments[*]}"
    [ -n "$source_file" ] && echo "  source     : ${source_file}"
    echo not_routed > "$DECREE_EVENT_FILE"
    exit 0
fi

echo "Routed to: ${_matched}"

decree emit --machine agent_task --param profile="$_matched" \
    --param file_path="$source_file" --param output_name="$output_name" \
    >/dev/null <<<"$_body"

echo "Queued agent_task for the ${_matched} profile."
