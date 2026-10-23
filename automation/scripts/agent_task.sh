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
# The gateway is called directly, through lib/hermes.sh — the same path
# lib/hermes-cli.sh gives a human in code-server's terminal. There is no AI CLI
# in this container: hermes already runs the tool loop, and wrapping it in a
# second agent both added nothing and broke on hermes' custom
# `event: hermes.tool.progress` SSE frames. Repo-editing work belongs to a
# coding agent on the host, not to this stack.
#
# `profile` picks which hermes profile answers (default: the default profile).
#
# hermes is told how to ask for follow-up work — automation-webhook's /hermes/*
# endpoints — with this run's TRACEPARENT, so its follow-up joins this trace.
# hermes has no mount into automation/, and shouldn't.
#
# The prompt is the `prompt` param, or else the message body — which is how
# hermes' /hermes/task/<profile> endpoint sends it:
#
#   decree emit --machine agent_task --param profile=research \
#       --param file_path=notes/decisions.md <<<'What should I do about this?'
set -euo pipefail

: "${HERMES_API_KEY:?HERMES_API_KEY is empty — enable hermes so the gateway credential is passed through}"

prompt="$DECREE_DATA_PROMPT"
if [ -z "$prompt" ]; then
    prompt="$(awk 'NR==1 && /^---$/{skip=1; next} skip && /^---$/{skip=0; next} !skip' "$DECREE_MESSAGE" | sed '/./,$!d')"
fi
profile="$DECREE_DATA_PROFILE"
file_path="$DECREE_DATA_FILE_PATH"
output_name="$DECREE_DATA_OUTPUT_NAME"
AGENT_OUTPUT_DIR="${AGENT_OUTPUT_DIR:-/workspace/ai}"
AGENT_TIMEOUT="$DECREE_DATA_AGENT_TIMEOUT"
AGENT_NOTIFY="${AGENT_NOTIFY:-true}"
AGENT_MAX_TOKENS="${AGENT_MAX_TOKENS:-4000}"

if [ -z "$prompt" ]; then
    echo "prompt is required: a prompt param, or a message body." >&2
    exit 1
fi

# shellcheck source=../lib/hermes.sh
source "${DECREE_LIB}/hermes.sh"

# --- Build the full prompt -------------------------------------------------

# Said plainly rather than as tool wiring: hermes decides for itself when to
# reach for openviking or the web, and telling it what is available is enough.
system_prompt="You have search over this workspace's knowledgebase (OpenViking)
and over the web. Use them where they would change the answer, and say plainly
where you could not find something rather than inventing it.

$(hermes_followup_notice)
Write markdown. Be concrete and brief — no preamble, no encouragement."

full_prompt="${prompt}"

if [ -n "$file_path" ]; then
    full_prompt="${full_prompt}

The file this is about is workspace/${file_path}."
fi

# --- Run it ----------------------------------------------------------------

_name="${output_name:-${DECREE_MESSAGE_ID}}"
# One path component only: a source path in output_name would otherwise escape
# the output directory, and the whole point of that directory is containment.
_name="$(basename "$_name")"
_name="${_name%.md}"
out="${AGENT_OUTPUT_DIR}/${_name}.md"

mkdir -p "$AGENT_OUTPUT_DIR"

echo "Asking the ${profile:-default} profile (timeout ${AGENT_TIMEOUT}s)..."
_raw="$(mktemp "${DECREE_RUN_DIR}/agent_task.XXXXXX")"
trap 'rm -f "$_raw"' EXIT

HERMES_API_URL="$(hermes_profile_url "$profile")"
HERMES_TIMEOUT="$AGENT_TIMEOUT"
export HERMES_API_URL HERMES_TIMEOUT

hermes_chat "$system_prompt" "$full_prompt" "$AGENT_MAX_TOKENS" > "$_raw" || true

if [ ! -s "$_raw" ]; then
    # An empty body is the one failure the gateway does not report as an HTTP
    # error: a tool loop cut short still returns 200 with no choices. Fail
    # rather than file an empty answer.
    echo "The ${profile:-default} profile returned nothing." >&2
    echo "Check: docker logs hermes-agent for 'Interrupted during API call', and" >&2
    echo "confirm EXIST_MODEL_URL_CHAT is reachable and the chat model can carry a" >&2
    echo "tool-using turn." >&2
    exit 1
fi

{
    printf -- '---\n'
    printf 'generated_by: agent_task\n'
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
    decree emit --machine notify \
        --param ntfy_title="Agent task done — ${_name}" \
        --param ntfy_priority=default --param ntfy_tags=robot >/dev/null <<EOF
${FILE_MATCH_REASON:-${prompt}}

Written to workspace/ai/${_name}.md
EOF
fi
