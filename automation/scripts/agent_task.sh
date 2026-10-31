#!/usr/bin/env bash
# Agent Task
#
# Hands a task to pi on the stack's own chat model and files the answer in
# workspace/ai/.
#
# pi runs its own tool loop against the MCP servers pi_configure registered —
# openviking search, firecrawl web search, playwright — so the prompt does not
# need to name tools, only to say what it wants. A machine that wants Claude
# instead uses lib/agent.sh. Repo-editing work belongs to a coding agent on the
# host, not to this stack.
#
# `department` picks which tools it gets (lib/departments/<name>.yml; empty:
# pi's defaults and every MCP server).
#
# The prompt is the `prompt` param, or else the message body:
#
#   decree emit --machine agent_task --param department=research \
#       --param file_path=notes/decisions.md <<<'What should I do about this?'
set -euo pipefail

prompt="$DECREE_DATA_PROMPT"
if [ -z "$prompt" ]; then
    prompt="$(awk 'NR==1 && /^---$/{skip=1; next} skip && /^---$/{skip=0; next} !skip' "$DECREE_MESSAGE" | sed '/./,$!d')"
fi
department="$DECREE_DATA_DEPARTMENT"
file_path="$DECREE_DATA_FILE_PATH"
output_name="$DECREE_DATA_OUTPUT_NAME"
AGENT_OUTPUT_DIR="${AGENT_OUTPUT_DIR:-/workspace/ai}"
AGENT_NOTIFY="${AGENT_NOTIFY:-true}"

if [ -z "$prompt" ]; then
    echo "prompt is required: a prompt param, or a message body." >&2
    exit 1
fi

# shellcheck source=../lib/pi.sh
source "${DECREE_LIB}/pi.sh"

# --- Build the full prompt -------------------------------------------------

# Said plainly rather than as tool wiring: pi decides for itself when to reach
# for openviking or the web, and telling it what is available is enough.
system_prompt="Search this workspace's knowledgebase and the web where your tools
allow it and it would change the answer, and say plainly where you could not find
something rather than inventing it. You are not here to edit files: your answer
is filed for you. Write markdown. Be concrete and brief — no preamble, no
encouragement."

full_prompt="${prompt}"

if [ -n "$file_path" ]; then
    full_prompt="${full_prompt}

The file this is about is ${file_path}."
fi

# --- Run it ----------------------------------------------------------------

_name="${output_name:-${DECREE_MESSAGE_ID}}"
# One path component only: a source path in output_name would otherwise escape
# the output directory, and the whole point of that directory is containment.
_name="$(basename "$_name")"
_name="${_name%.md}"
out="${AGENT_OUTPUT_DIR}/${_name}.md"

mkdir -p "$AGENT_OUTPUT_DIR"

echo "Asking pi${department:+ (${department})} (timeout ${DECREE_DATA_AGENT_TIMEOUT}s)..."
_raw="$(mktemp "${DECREE_RUN_DIR}/agent_task.XXXXXX")"
trap 'rm -f "$_raw"' EXIT

PI_TIMEOUT="$DECREE_DATA_AGENT_TIMEOUT" pi_run "$department" "$system_prompt" "$full_prompt" > "$_raw" || true

if [ ! -s "$_raw" ]; then
    echo "pi${department:+ (${department})} returned nothing." >&2
    echo "Check that EXIST_MODEL_URL_CHAT is reachable and the chat model can carry a" >&2
    echo "tool-using turn; the run's log has pi's own error above." >&2
    exit 1
fi

{
    printf -- '---\n'
    printf 'generated_by: agent_task\n'
    printf 'department: %s\n' "$(jq -rn --arg v "${department:-default}" '$v|@json')"
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
    decree emit --machine notify \
        --param ntfy_title="Agent task done — ${_name}" \
        --param ntfy_priority=default --param ntfy_tags=robot >/dev/null <<EOF
${FILE_MATCH_REASON:-${prompt}}

Written to workspace/ai/${_name}.md
EOF
fi
