#!/usr/bin/env bash
# Router
#
# Decides which department should handle a message, then emits agent_task in
# that department. It does not do the work itself.
#
# Departments are discovered, not configured: every lib/departments/<name>.yml
# is a candidate and its `description:` is what the model sees — the same file
# pi_run takes the department's tools from, so a description is written once.
# Adding a department is adding a file; nothing here changes.
#
# The decision is one plain completion (lib/model.sh), not a pi run: naming a
# department needs no tools, and every tool would be paid for on every message.
#
# The reply is validated against the discovered list. Anything unrecognized —
# a hallucinated department, an empty answer, a failed call — ends the run in
# `not_routed`, with the reason in its log. This script never guesses.
#
#   decree emit --machine router --param source_file=notes/lead.md <<<'<the task>'
set -euo pipefail

DEPARTMENTS="${DEPARTMENTS:-${DECREE_LIB}/departments}"
ROUTER_TIMEOUT="${ROUTER_TIMEOUT:-300}"
source_file="$DECREE_DATA_SOURCE_FILE"
output_name="$DECREE_DATA_OUTPUT_NAME"

# --- What can we route to? -------------------------------------------------

_departments=()
_catalog=""
for _f in "${DEPARTMENTS}"/*.yml; do
    [ -f "$_f" ] || continue
    _n="$(basename "$_f" .yml)"
    _d="$(grep -m1 '^description:' "$_f" | sed 's/^description:[[:space:]]*//')"
    _departments+=("$_n")
    _catalog="${_catalog}- ${_n}: ${_d:-(no description)}"$'\n'
done

if [ "${#_departments[@]}" -eq 0 ]; then
    echo "No departments found in ${DEPARTMENTS} — nothing to route to." >&2
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

# --- Ask the model ---------------------------------------------------------

_prompt="Choose the single department best suited to handle the message below.

## Departments

${_catalog}
## Message

${_body}

## Instructions

Respond with ONLY the department name, exactly as written above. No explanation,
no punctuation. If no department is a clear match, respond with: none"

# shellcheck source=../lib/model.sh
source "${DECREE_LIB}/model.sh"

_system="You route work to departments. You reply with one department name and nothing else."

# A wrong answer here is handled below, so a failed call is not fatal: it lands
# in the same not-routed branch as a hallucinated name.
_choice="$(MODEL_TIMEOUT="$ROUTER_TIMEOUT" model_chat "$_system" "$_prompt" 32 || true)"
_choice="$(printf '%s' "$_choice" | sed '/^[[:space:]]*$/d' | tail -1 \
    | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[.,]$//' | tr '[:upper:]' '[:lower:]')"

echo "Model said: ${_choice:-(nothing)}"

# --- Validate, then hand off ------------------------------------------------

_matched=""
for _d in "${_departments[@]}"; do
    [ "$_choice" = "$_d" ] && { _matched="$_d"; break; }
done

if [ -z "$_matched" ]; then
    # Never guess. An unrecognized answer is a routing failure, not a hint.
    if [ -z "$_choice" ]; then
        _reason="the model returned no answer (failed call or timeout)"
    elif [ "$_choice" = "none" ]; then
        _reason="the model found no department matching this message"
    else
        _reason="the model answered '${_choice}', which is not a department"
    fi
    echo "Not routed: ${_reason}"
    echo "  candidates : ${_departments[*]}"
    [ -n "$source_file" ] && echo "  source     : ${source_file}"
    echo not_routed > "$DECREE_EVENT_FILE"
    exit 0
fi

echo "Routed to: ${_matched}"

decree emit --machine agent_task --param department="$_matched" \
    --param file_path="$source_file" --param output_name="$output_name" \
    >/dev/null <<<"$_body"

echo "Queued agent_task in the ${_matched} department."
