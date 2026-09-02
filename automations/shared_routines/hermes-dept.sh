#!/usr/bin/env bash
# hermes-dept — run one task against one hermes department profile.
#
# One routine for every department. Which department is a message parameter,
# because a department's identity lives in its profile definition
# (ai/hermes/profiles/<name>/profile.yml), not in a routine file:
#
#   ---
#   routine: hermes-dept
#   profile: research
#   output_name: competition
#   ---
#   <the task>
#
# hermes-router writes exactly that after choosing a department; dropping the
# message yourself bypasses the router entirely.
#
# The profile is called directly over its OpenAI-compatible endpoint at
# /p/<profile>/v1. Hermes is itself an agent running its own tool loop against
# its own MCP servers, so routing this through opencode would wrap an agent in
# an agent — and opencode's streaming parser rejects hermes' custom
# `event: hermes.tool.progress` SSE frames, which fails every profile that owns
# tools. Coding work that genuinely wants a repo-editing agent still goes to
# `develop`/`agent-task`.
#
# Env vars:
#   AGENT_OUTPUT_DIR  where answers are filed        (default /workspace/ai)
#   AGENT_TIMEOUT     seconds for the gateway call   (default 900)
#   AGENT_MAX_TOKENS  cap on the answer              (default 4000)
#   AGENT_NOTIFY      send an ntfy message when done (default true)
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
    command -v curl >/dev/null 2>&1 || precheck_fail "hermes-dept" "curl not found"
    command -v jq >/dev/null 2>&1 || precheck_fail "hermes-dept" "jq not found"
    [ -n "${HERMES_API_KEY:-}" ] || precheck_fail "hermes-dept" \
        "HERMES_API_KEY is empty — enable hermes so the gateway credential is passed through"
    precheck_pass "hermes-dept"
    exit 0
fi

# The department. No default: a message that does not name one is a bug in
# whatever wrote it, and guessing would file the answer under the wrong profile.
profile="${profile:?profile: is required — name the department, e.g. 'profile: research'}"

out_dir="${AGENT_OUTPUT_DIR:-/workspace/ai}"
timeout_s="${agent_timeout:-${AGENT_TIMEOUT:-900}}"
outbox="${OUTBOX_DIR:-/work/.decree/outbox}"
mkdir -p "$outbox"   # decree reads the outbox but never creates it

# The task text is the message body, with the frontmatter stripped.
body="$(awk 'NR==1 && /^---$/{skip=1; next} skip && /^---$/{skip=0; next} !skip' \
    "$message_file" | sed '/./,$!d')"

if [ -z "$body" ] && [ -z "${prompt:-}" ]; then
    echo "Nothing to do: message body and prompt are both empty." >&2
    exit 1
fi
[ -n "${prompt:-}" ] && body="${prompt}

${body}"

system="You are the ${profile} department. Use the tools and knowledgebase
available to you where they would change the answer, and say plainly where you
could not find something rather than inventing it.

Write markdown. Be concrete and brief — no preamble, no encouragement."

name="${output_name:-${message_id:-${profile}-$(date +%s)}}"
name="$(basename "$name")"; name="${name%.md}"
out="${out_dir}/${name}.md"

mkdir -p "$out_dir"

echo "Department : ${profile}"
echo "Routed via : ${routed_by:-direct}"
[ -n "${route_reason:-}" ] && echo "Because    : ${route_reason}"

raw="$(mktemp "${message_dir:-/tmp}/dept.XXXXXX")"
# shellcheck disable=SC2064  # expand raw now, not at trap time
trap "rm -f '$raw'" EXIT

# shellcheck source=../lib/hermes.sh
source "${SCRIPT_DIR}/../lib/hermes.sh"
HERMES_API_URL="$(hermes_profile_url "$profile")"
HERMES_TIMEOUT="$timeout_s"
export HERMES_API_URL HERMES_TIMEOUT

hermes_chat "$system" "$body" "${AGENT_MAX_TOKENS:-4000}" > "$raw" || true

if [ ! -s "$raw" ]; then
    # An empty body is the one failure the gateway does not report as an HTTP
    # error: a tool loop that was cut short still returns 200. Fail so decree
    # retries under max_attempts rather than filing an empty answer.
    #
    # A profile that was never provisioned looks the same from here, so say so:
    # an unknown profile name 404s, and a profile without its own API_SERVER_KEY
    # 401s, both of which arrive as no content.
    echo "The ${profile} profile returned nothing." >&2
    echo "Check: docker logs hermes-agent — a run cut short logs" >&2
    echo "'Interrupted during API call'." >&2
    echo "If the profile was never created, restart hermes: entrypoint.sh" >&2
    echo "provisions ai/hermes/profiles/${profile}/ on boot." >&2
    exit 1
fi

{
    printf -- '---\n'
    printf 'generated_by: %s\n' "$(jq -rn --arg v "hermes-dept" '$v|@json')"
    printf 'profile: %s\n' "$(jq -rn --arg v "$profile" '$v|@json')"
    printf 'generated_at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    [ -n "${source_file:-}" ] && printf 'source_file: %s\n' "$(jq -rn --arg v "$source_file" '$v|@json')"
    [ -n "${route_reason:-}" ] && printf 'routed_because: %s\n' "$(jq -rn --arg v "$route_reason" '$v|@json')"
    printf -- '---\n\n'
    cat "$raw"
} > "$out"

echo "Wrote ${out}"

if [ "${AGENT_NOTIFY:-true}" = "true" ]; then
    cat > "${outbox}/hermes-dept-${profile}-$(date +%s%N).md" << NOTIFY
---
routine: notify
ntfy_title: $(jq -rn --arg v "${profile} — ${name}" '$v|@json')
ntfy_priority: default
ntfy_tags: robot
---
${route_reason:-Handled by the ${profile} department.}

Written to workspace/ai/${name}.md
NOTIFY
fi
