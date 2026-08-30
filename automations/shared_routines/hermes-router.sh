#!/usr/bin/env bash
# Hermes Router
#
# Decides which department should handle a message, then writes an outbox
# message naming that department's routine. It does not do the work itself.
#
# Departments are discovered, not configured: every dept-<name>.sh in
# shared_routines/ is a candidate, and its DEPT_DESCRIPTION line is what the
# router sees. Adding a department is adding a file — nothing here changes.
#
# The decision runs against the hermes 'router' profile (/p/router/v1), which
# carries no toolsets and no MCP servers because naming a department needs
# neither. That profile costs ~630 prompt tokens per call against ~40,000 for
# the default one, which is the whole reason routing is split out.
#
# The profile is called directly over its OpenAI-compatible endpoint rather than
# through opencode. Hermes runs its own tool loop, so opencode would be an agent
# wrapping an agent — and its streaming parser rejects hermes' custom
# `event: hermes.tool.progress` SSE frames outright, which breaks any profile
# that owns tools. Direct, non-streaming calls have neither problem.
#
# The reply is validated against the discovered list. Anything unrecognized —
# a hallucinated department, an empty answer, a gateway failure — routes to
# route-failed instead, which logs and stops. This routine never guesses.
#
#   ---
#   routine: hermes-router
#   source_file: notes/lead.md
#   ---
#   <the task to route>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "${SCRIPT_DIR}/../lib/precheck.sh"
    command -v curl >/dev/null 2>&1 || precheck_fail "hermes-router" "curl not found"
    command -v jq >/dev/null 2>&1 || precheck_fail "hermes-router" "jq not found"
    [ -n "${HERMES_API_KEY:-}" ] || precheck_fail "hermes-router" \
        "HERMES_API_KEY is empty — enable hermes so the gateway credential is passed through"
    compgen -G "${SCRIPT_DIR}/dept-*.sh" >/dev/null 2>&1 || precheck_fail "hermes-router" \
        "no dept-*.sh routines found in shared_routines/ — nothing to route to"
    precheck_pass "hermes-router"
    exit 0
fi

ROUTER_PROFILE="${ROUTER_PROFILE:-router}"
ROUTER_TIMEOUT="${ROUTER_TIMEOUT:-300}"
FALLBACK_ROUTINE="${FALLBACK_ROUTINE:-route-failed}"
OUTBOX_DIR="${OUTBOX_DIR:-/work/.decree/outbox}"
# decree reads the outbox but never creates it — an absent dir is silently
# treated as "no messages", so a handoff would vanish without an error.
mkdir -p "$OUTBOX_DIR"

# --- What can we route to? -------------------------------------------------

_departments=()
_catalog=""
for _f in "${SCRIPT_DIR}"/dept-*.sh; do
    [ -f "$_f" ] || continue
    _n="$(basename "$_f" .sh)"; _n="${_n#dept-}"
    _d="$(grep -m1 '^# DEPT_DESCRIPTION:' "$_f" | sed 's/^# DEPT_DESCRIPTION:[[:space:]]*//')"
    _departments+=("$_n")
    _catalog="${_catalog}- ${_n}: ${_d:-(no description)}"$'\n'
done

if [ "${#_departments[@]}" -eq 0 ]; then
    echo "No dept-*.sh routines found — nothing to route to." >&2
    exit 1
fi

echo "Departments: ${_departments[*]}"

# --- The message we are routing --------------------------------------------

_body="$(awk 'NR==1 && /^---$/{skip=1; next} skip && /^---$/{skip=0; next} !skip' \
    "$message_file" | sed '/./,$!d')"

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
source "${SCRIPT_DIR}/../lib/hermes.sh"
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

    cat > "${OUTBOX_DIR}/route-failed-$(date +%s%N).md" << EOF
---
routine: ${FALLBACK_ROUTINE}
route_reason: $(jq -rn --arg v "$_reason" '$v|@json')
route_attempted: $(jq -rn --arg v "${_choice:-}" '$v|@json')
route_candidates: $(jq -rn --arg v "${_departments[*]}" '$v|@json')
source_file: $(jq -rn --arg v "${source_file:-}" '$v|@json')
---

${_body}
EOF
    exit 0
fi

echo "Routed to: ${_matched}"

cat > "${OUTBOX_DIR}/dept-${_matched}-$(date +%s%N).md" << EOF
---
routine: dept-${_matched}
routed_by: hermes-router
route_reason: $(jq -rn --arg v "routed to ${_matched} by the ${ROUTER_PROFILE} profile" '$v|@json')
source_file: $(jq -rn --arg v "${source_file:-}" '$v|@json')
output_name: $(jq -rn --arg v "${output_name:-}" '$v|@json')
---

${_body}
EOF

echo "Queued dept-${_matched}."
