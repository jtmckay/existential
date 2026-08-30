#!/usr/bin/env bash
# Agent Task
#
# Hands a task to hermes and files the answer in workspace/ai/.
#
# Hermes is an agent gateway that runs its own tool loop, so this reaches every
# MCP server hermes has registered — openviking search, firecrawl web search,
# playwright — without any per-routine wiring. The prompt does not need to name
# tools, only to say what it wants.
#
# The gateway is called directly rather than through opencode: opencode's
# streaming parser rejects hermes' custom `event: hermes.tool.progress` SSE
# frames, which fails every turn where hermes actually uses a tool. Coding work
# that wants a repo-editing agent goes to `develop`, which drives opencode
# against a plain model endpoint.
#
# `profile` picks which hermes profile answers (default: the default profile).
# The dept-<name> routines are this same call bound to one profile each.
#
# Chained by a file processor, or run by hand by dropping a message in the inbox
# (services/decree/decree/inbox/<name>.md):
#
#   ---
#   routine: agent-task
#   prompt: What should I do about the thing in this file?
#   file_path: notes/decisions.md
#   output_name: decisions-followup
#   profile: research
#   ---
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
    command -v curl >/dev/null 2>&1 || precheck_fail "agent-task" "curl not found"
    command -v jq >/dev/null 2>&1 || precheck_fail "agent-task" "jq not found"
    [ -n "${HERMES_API_KEY:-}" ] || precheck_fail "agent-task" \
        "HERMES_API_KEY is empty — enable hermes so the gateway credential is passed through"
    [ -d "${AGENT_OUTPUT_DIR:-/workspace/ai}" ] || precheck_fail "agent-task" \
        "${AGENT_OUTPUT_DIR:-/workspace/ai} does not exist — is ../../workspace mounted into the decree container?"
    precheck_pass "agent-task"
    exit 0
fi

prompt="${prompt:-}"
profile="${profile:-}"
file_path="${file_path:-}"
output_name="${output_name:-}"
AGENT_OUTPUT_DIR="${AGENT_OUTPUT_DIR:-/workspace/ai}"
AGENT_TIMEOUT="${agent_timeout:-${AGENT_TIMEOUT:-900}}"
AGENT_NOTIFY="${AGENT_NOTIFY:-true}"
AGENT_MAX_TOKENS="${AGENT_MAX_TOKENS:-4000}"

OUTBOX_DIR="${OUTBOX_DIR:-/work/.decree/outbox}"
mkdir -p "$OUTBOX_DIR"   # decree reads the outbox but never creates it

if [ -z "$prompt" ]; then
    echo "prompt is required." >&2
    exit 1
fi

# --- Build the full prompt -------------------------------------------------

# Said plainly rather than as tool wiring: hermes decides for itself when to
# reach for openviking or the web, and telling it what is available is enough.
system_prompt="You have search over this workspace's knowledgebase (OpenViking)
and over the web. Use them where they would change the answer, and say plainly
where you could not find something rather than inventing it.

Write markdown. Be concrete and brief — no preamble, no encouragement."

full_prompt="${prompt}"

if [ -n "$file_path" ]; then
    full_prompt="${full_prompt}

The file this is about is workspace/${file_path}."
fi

# --- Run it ----------------------------------------------------------------

_name="${output_name:-${message_id:-agent-task-$(date +%s)}}"
# One path component only: a source path in output_name would otherwise escape
# the output directory, and the whole point of that directory is containment.
_name="$(basename "$_name")"
_name="${_name%.md}"
out="${AGENT_OUTPUT_DIR}/${_name}.md"

mkdir -p "$AGENT_OUTPUT_DIR"

echo "Asking the ${profile:-default} profile (timeout ${AGENT_TIMEOUT}s)..."
_raw="$(mktemp "${message_dir:-/tmp}/agent-task.XXXXXX")"
trap 'rm -f "$_raw"' EXIT

# shellcheck source=../lib/hermes.sh
source "${SCRIPT_DIR}/../lib/hermes.sh"
HERMES_API_URL="$(hermes_profile_url "$profile")"
HERMES_TIMEOUT="$AGENT_TIMEOUT"
export HERMES_API_URL HERMES_TIMEOUT

hermes_chat "$system_prompt" "$full_prompt" "$AGENT_MAX_TOKENS" > "$_raw" || true

if [ ! -s "$_raw" ]; then
    # An empty body is the one failure the gateway does not report as an HTTP
    # error: a tool loop cut short still returns 200 with no choices. Fail so
    # decree retries under max_attempts rather than filing an empty answer.
    echo "The ${profile:-default} profile returned nothing." >&2
    echo "Check: docker logs hermes-agent for 'Interrupted during API call', and" >&2
    echo "confirm EXIST_OLLAMA_URL is reachable and the chat model can carry a" >&2
    echo "tool-using turn." >&2
    exit 1
fi

{
    printf -- '---\n'
    printf 'generated_by: agent-task\n'
    printf 'profile: %s\n' "$(jq -rn --arg v "${profile:-default}" '$v|@json')"
    printf 'generated_at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if [ -n "$file_path" ]; then
        printf 'source_file: %s\n' "$(jq -rn --arg v "$file_path" '$v|@json')"
    fi
    if [ -n "${FILE_MATCH_REASON:-}" ]; then
        printf 'matched_because: %s\n' "$(jq -rn --arg v "$FILE_MATCH_REASON" '$v|@json')"
    fi
    printf -- '---\n\n'
    cat "$_raw"
} > "$out"

echo "Wrote ${out}"

# --- Tell someone ----------------------------------------------------------

if [ "$AGENT_NOTIFY" = "true" ]; then
    cat > "${OUTBOX_DIR}/agent-task-$(date +%s%N).md" << EOF
---
routine: notify
ntfy_title: Agent task done — ${_name}
ntfy_priority: default
ntfy_tags: robot
---
${FILE_MATCH_REASON:-${prompt}}

Written to workspace/ai/${_name}.md
EOF
fi
